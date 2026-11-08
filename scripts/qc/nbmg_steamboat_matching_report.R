# ============================================================
# nbmg_steamboat_matching_report.R
#
# Purpose: READ-ONLY report matching the NBMG statewide permit/well
# compilation (data/raw/nbmg/GEOTHERM06102019.csv) to this project's Wells
# table, and listing compilation wells that are not yet in the database.
# No database writes.
#
# Datum rule: UTM columns are NAD27 zone 11 (EPSG:26711) when NAD == "27",
# NAD83 zone 11 (EPSG:26911) when NAD == "83". The conversion is validated
# against the NBMG ArcGIS layer (Geothermal_Wells.csv, NAD83 lat/lon) by API.
#
# Match order: API -> NDOM permit -> normalized name -> Well_Aliases
# -> confirmed spelling variants. A row that hits more than one Wells row,
# or whose coordinate is > 200 m from the matched well, is HELD (not merged).
#
# Outputs (data/derived/):
#   nbmg_steamboat_well_matching.csv   one row per compilation row
#   nbmg_steamboat_new_wells.csv       rows with no match in Wells
#   nbmg_nad27_validation.csv          NAD27 conversion vs ArcGIS lat/lon
# ============================================================

library(DBI); library(dplyr); library(readr); library(sf); library(stringr)

.hav_m <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000; k <- pi / 180
  a <- sin((lat2 - lat1) * k / 2)^2 + cos(lat1 * k) * cos(lat2 * k) * sin((lon2 - lon1) * k / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

#' Core token of a well name: "Industrial Production Well No. 44-32" -> "44-32"
.norm_well_name <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("^(INDUSTRIAL )?(INJECTION|PRODUCTION|OBSERVATION|DOMESTIC|THERMAL GRADIENT)( WELL)?( NO\\.?)? *", "", x)
  x <- gsub("^WELL NO\\.? *", "", x)
  x <- gsub("^NO\\.? *", "", x)
  gsub("[^A-Z0-9]", "", x)
}

nbmg_utm_to_latlon <- function(df) {
  df$latitude <- NA_real_; df$longitude <- NA_real_; df$utm_crs <- NA_character_
  e <- suppressWarnings(as.numeric(df$UTME)); n <- suppressWarnings(as.numeric(df$UTMN))
  ok <- !is.na(e) & !is.na(n) & e > 0 & n > 0
  for (nad in c("27", "83")) {
    idx <- ok & df$NAD %in% nad
    if (!any(idx)) next
    epsg <- if (nad == "27") 26711 else 26911
    p <- st_transform(st_as_sf(data.frame(e = e[idx], n = n[idx]), coords = c("e", "n"), crs = epsg), 4326)
    ll <- st_coordinates(p)
    df$longitude[idx] <- ll[, 1]; df$latitude[idx] <- ll[, 2]
    df$utm_crs[idx] <- paste0("NAD", nad, "_zone11")
  }
  df
}

run_nbmg_steamboat_matching_report <- function(
    con,
    compilation_csv = "data/raw/nbmg/GEOTHERM06102019.csv",
    arcgis_csv = "data/raw/nbmg/Geothermal_Wells.csv",
    out_dir = "data/derived",
    hold_distance_m = 200, flag_distance_m = 100) {

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  g <- read_csv(compilation_csv, col_types = cols(.default = col_character()), show_col_types = FALSE)

  # Scope: KGRA Steamboat(/Springs) rows, plus nearby unlabeled-KGRA rows (Washoe T17-18N R19-20E) as context
  g <- g |>
    mutate(scope = case_when(
      grepl("^Steamboat", KGRA) ~ "steamboat_kgra",
      COUNTY == "Washoe" & T %in% c("17N", "18N") & R %in% c("19E", "20E") ~ "box_context_only",
      TRUE ~ NA_character_)) |>
    filter(!is.na(scope))
  g <- nbmg_utm_to_latlon(g)

  # ---- NAD27 validation against the ArcGIS layer, by API ----
  gw <- read_csv(arcgis_csv, show_col_types = FALSE)
  val <- g |>
    filter(!is.na(latitude)) |>
    inner_join(gw |> select(apino, a_lat = latdegree, a_lon = longdegree, a_datum = utmdatumzone) |>
                 distinct(apino, .keep_all = TRUE), by = c("API" = "apino")) |>
    mutate(offset_m = round(.hav_m(latitude, longitude, a_lat, a_lon), 1)) |>
    select(API, WELL, NAD, utm_crs, latitude, longitude, a_lat, a_lon, a_datum, offset_m)
  write_csv(val, file.path(out_dir, "nbmg_nad27_validation.csv"))

  # ---- Our wells ----
  w <- dbGetQuery(con, "SELECT well_id, well_name, api_number, ndom_permit, latitude, longitude, well_role FROM Wells")
  al <- dbGetQuery(con, "SELECT a.alias, a.well_id FROM Well_Aliases a")
  w$norm <- .norm_well_name(w$well_name)
  al$norm <- .norm_well_name(al$alias)
  # NDOM-confirmed spelling variants (21-5=21-5R, 13-5=13-5R, 21B-5=21B-5R, 83B-6=83B-6R, 23-33=23-33RD, 46-28-2=46-28)
  nd_var <- c("215" = "215R", "135" = "135R", "21B5" = "21B5R", "83B6" = "83B6R", "2333" = "2333RD", "46282" = "4628")

  res <- vector("list", nrow(g))
  for (i in seq_len(nrow(g))) {
    r <- g[i, ]
    perm <- if (!is.na(r$PERMIT) && grepl("^[0-9]{4}$", r$PERMIT)) r$PERMIT else NA_character_
    nm <- .norm_well_name(r$WELL)
    cand <- integer(0); method <- NA_character_
    h <- w$well_id[!is.na(w$api_number) & w$api_number == r$API]
    if (length(h)) { cand <- h; method <- "api" }
    if (!length(cand) && !is.na(perm)) {
      h <- w$well_id[!is.na(w$ndom_permit) & w$ndom_permit == perm]
      if (length(h)) { cand <- h; method <- "ndom_permit" }
    }
    if (!length(cand) && nzchar(nm)) {
      h <- w$well_id[w$norm == nm]
      if (length(h)) { cand <- h; method <- "normalized_name" }
    }
    if (!length(cand) && nzchar(nm)) {
      h <- unique(al$well_id[al$norm == nm])
      if (length(h)) { cand <- h; method <- "alias" }
    }
    if (!length(cand) && nzchar(nm) && !is.na(nd_var[nm])) {
      h <- w$well_id[w$norm == nd_var[nm]]
      if (length(h)) { cand <- h; method <- "confirmed_variant" }
    }
    res[[i]] <- tibble(
      api = r$API, permit = r$PERMIT, compilation_name = r$WELL, scope = r$scope,
      status = r$STATUS, class = r$CLASS, td_ft = r$TD, section = paste(r$S, r$T, r$R),
      nad = r$NAD, utm_crs = r$utm_crs, latitude = r$latitude, longitude = r$longitude,
      match_method = method, n_candidates = length(cand),
      matched_well_id = if (length(cand) == 1) cand else NA_integer_,
      candidate_well_ids = paste(cand, collapse = ";"))
  }
  m <- bind_rows(res) |>
    left_join(w |> select(well_id, our_name = well_name, our_lat = latitude, our_lon = longitude),
              by = c("matched_well_id" = "well_id")) |>
    mutate(
      distance_m = round(.hav_m(latitude, longitude, our_lat, our_lon), 1),
      review_flag = case_when(
        n_candidates > 1 ~ "HOLD_multiple_candidates",
        n_candidates == 1 & !is.na(distance_m) & distance_m > hold_distance_m ~ "HOLD_distance_over_200m",
        n_candidates == 1 & !is.na(distance_m) & distance_m > flag_distance_m ~ "flag_distance_100_200m",
        n_candidates == 1 ~ "ok",
        TRUE ~ "no_match"),
      permit_only = grepl("Expired|Not permitted|Not in use", status) |
        (is.na(td_ft) & grepl("Unknown|^$", ifelse(is.na(status), "", status))) |
        grepl("Project", compilation_name),
      permit_only = ifelse(is.na(permit_only), FALSE, permit_only))
  write_csv(m, file.path(out_dir, "nbmg_steamboat_well_matching.csv"))

  # same-name collisions inside the compilation
  coll <- m |> mutate(nm = .norm_well_name(compilation_name)) |>
    group_by(nm) |> filter(n() > 1, nzchar(nm)) |> ungroup() |>
    arrange(nm) |> select(nm, api, permit, compilation_name, status, td_ft, matched_well_id)

  newer <- m |> filter(is.na(matched_well_id), n_candidates == 0) |>
    mutate(priority = case_when(
      scope == "box_context_only" ~ "low (outside Steamboat KGRA)",
      permit_only ~ "staging only (permit, not a real well)",
      grepl("^(32|33|29|28|0?5|0?6) ", section) ~ "high (Lower Sinter / field sections)",
      TRUE ~ "medium"))
  write_csv(newer, file.path(out_dir, "nbmg_steamboat_new_wells.csv"))

  list(matching = m, new_wells = newer, validation = val, collisions = coll, raw = g)
}
