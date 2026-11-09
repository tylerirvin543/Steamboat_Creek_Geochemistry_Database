# ============================================================
# ingest_nbmg_compilation.R
#
# Loads the Steamboat-area rows of the NBMG statewide well/permit compilation
# (data/raw/nbmg/GEOTHERM06102019.csv) into NBMG_Compilation_Records (staging,
# every row verbatim) and, for real wells only, into Wells.
#
# Rules:
#  * Permit-only rows (expired, not permitted, not in use, project areas) and
#    box_context_only rows stay in staging.
#  * Rows matched to exactly one existing well within 200 m (api / ndom permit /
#    normalized name / alias): fill-only (api_number, ndom_permit, dates,
#    total_depth, field_name, coordinate if NULL). Never overwrites.
#  * HOLD rows (several candidates, or > 200 m from the matched well) are staged
#    as 'held_probable' with the candidate well id; Wells is not touched.
#  * Unmatched real wells become new Wells rows (coordinate converted from the
#    row's own datum; elevation left empty for refresh_dem_elevations()).
#  * Idempotent: staging is keyed on (api, permit, well); a changed source row
#    updates staging only (row_hash) and is reported.
# ============================================================
library(DBI); library(dplyr); library(readr); library(digest)
source("scripts/qc/nbmg_steamboat_matching_report.R")

.parse_nbmg_date <- function(x) {
  x <- trimws(x)
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  d <- suppressWarnings(as.Date(x, format = if (grepl("[0-9]{4}$", x)) "%d %b %Y" else "%d %b %y"))
  if (is.na(d)) return(NA_character_)
  # %y reads 00-68 as 20xx; NBMG dates here are 1946-1968 as well, so anything in the future is a century early
  if (d > Sys.Date()) d <- seq(d, by = "-100 years", length.out = 2)[2]
  format(d, "%Y-%m-%d")
}
.num_commas <- function(x) suppressWarnings(as.numeric(gsub(",", "", x)))

.role_from_class <- function(cls, status, name) {
  s <- tolower(paste(cls, status, name))
  if (grepl("injection", s) && !grepl("domestic", s)) "injection"
  else if (grepl("production|geothermal", s) && !grepl("domestic|observation|test|auger", s)) "production"
  else if (grepl("domestic|water well", s)) "domestic"
  else if (grepl("observation|thermal grad|strat|test|auger", s)) "monitor"
  else "unknown"
}
.use_from_row <- function(api, cls, status, name, role) {
  if (api %in% c("27-031-80029", "27-031-80030", "27-031-80031", "27-031-80032")) return("resort_spa")
  s <- tolower(paste(cls, name))
  if (grepl("thermal grad|^tg ", s)) "thermal_gradient"
  else if (grepl("strat", s)) "stratigraphic_test"
  else if (grepl("auger|^test|test well", s) || (grepl("^27-031-800", api) && role %in% c("monitor", "unknown", "production"))) "historical_exploration"
  else switch(role, production = "production", injection = "injection", monitor = "observation", domestic = "domestic", "unknown")
}
.status_std <- function(status) {
  s <- tolower(ifelse(is.na(status), "", status))
  if (s == "p&a") "plugged_abandoned"
  else if (s == "abandoned") "abandoned_unplugged"
  else if (grepl("shut", s)) "shut_in"
  else if (s == "idle") "idle"
  else "unknown"
}

ingest_nbmg_compilation <- function(con, compilation_csv = "data/raw/nbmg/GEOTHERM06102019.csv") {
  message("---- Ingesting NBMG permit compilation (Steamboat) ----")
  if (!file.exists(compilation_csv)) { message("  -> no file, skipping"); return(invisible(NULL)) }
  rep <- run_nbmg_steamboat_matching_report(con, compilation_csv = compilation_csv)
  m <- rep$matching; g <- rep$raw
  stopifnot(nrow(m) == nrow(g))
  src_cols <- c("API","CONF","COUNTY","KGRA","PERMIT","FILE_NO","OPERATOR","WELL","S","T","R","PARTSECT","DISTFROMLI",
                "PERMIT_ISS","SPUD_DATE","COMPL_DATE","STATUS","CLASS","TD","ELEVATION","TOPS","ANALYSES","LOGS","SAMPLES",
                "DEPTH_TEMP","REMARKS","UTMN","UTME","NAD","ZONE")
  st <- list(new_stage = 0L, changed_stage = 0L, created = 0L, filled_fields = 0L, held = 0L, staging_only = 0L)
  existing_names <- dbGetQuery(con, "SELECT well_name FROM Wells")$well_name
  ph <- function(n) paste(rep("?", n), collapse = ",")

  for (i in seq_len(nrow(g))) {
    r <- g[i, ]; mm <- m[i, ]
    key <- dbGetQuery(con, "SELECT record_id, row_hash FROM NBMG_Compilation_Records
      WHERE COALESCE(src_api,'')=? AND COALESCE(src_permit,'')=? AND COALESCE(src_well,'')=?",
      params = list(ifelse(is.na(r$API), "", r$API), ifelse(is.na(r$PERMIT), "", r$PERMIT), ifelse(is.na(r$WELL), "", r$WELL)))
    h <- digest(paste(unlist(r[src_cols]), collapse = "|"))
    disp <- NA_character_; loaded <- NA_integer_
    mid <- mm$matched_well_id

    if (nrow(key) > 0) {
      if (!identical(key$row_hash[1], h)) {
        sets <- paste0("src_", tolower(src_cols), " = ?", collapse = ", ")
        dbExecute(con, paste0("UPDATE NBMG_Compilation_Records SET ", sets, ", row_hash = ? WHERE record_id = ?"),
                  params = c(unname(as.list(unlist(r[src_cols]))), list(h, key$record_id[1])))
        st$changed_stage <- st$changed_stage + 1L
        message("  [changed source row] ", r$API, " ", r$WELL, " -- staging updated, Wells untouched")
      }
      next
    }

    if (mm$scope == "box_context_only") { disp <- "staging_only_context"; st$staging_only <- st$staging_only + 1L
    } else if (isTRUE(mm$permit_only)) { disp <- "staging_only_permit"; st$staging_only <- st$staging_only + 1L
    } else if (grepl("^HOLD", mm$review_flag)) { disp <- "held_probable"; st$held <- st$held + 1L
    } else if (!is.na(mid)) {
      ex <- dbGetQuery(con, "SELECT * FROM Wells WHERE well_id = ?", params = list(mid))
      upd <- function(col, val) {
        if (!is.na(val) && is.na(ex[[col]][1])) {
          dbExecute(con, sprintf("UPDATE Wells SET %s = ? WHERE well_id = ?", col), params = list(val, mid))
          st$filled_fields <<- st$filled_fields + 1L
        }
      }
      api_taken <- dbGetQuery(con, "SELECT 1 FROM Wells WHERE api_number = ? AND well_id <> ?", params = list(r$API, mid))
      if (nrow(api_taken) == 0) upd("api_number", r$API)
      if (grepl("^[0-9]{4}$", ifelse(is.na(r$PERMIT), "", r$PERMIT))) upd("ndom_permit", r$PERMIT)
      upd("spud_date", .parse_nbmg_date(r$SPUD_DATE)); upd("completion_date", .parse_nbmg_date(r$COMPL_DATE))
      upd("total_depth", .num_commas(r$TD)); upd("field_name", "Steamboat Springs")
      if (is.na(ex$latitude[1]) && !is.na(mm$latitude)) {
        dbExecute(con, "UPDATE Wells SET latitude=?, longitude=?, coord_key=?, coordinate_source=?, coordinate_uncertainty_m=75 WHERE well_id=?",
                  params = list(mm$latitude, mm$longitude, paste0(mm$latitude, "_", mm$longitude),
                                paste0("nbmg_geothermal_compilation_", tolower(mm$utm_crs), "_converted"), mid))
        st$filled_fields <- st$filled_fields + 1L
      }
      disp <- "filled_existing"; loaded <- mid
    } else {
      nm <- trimws(r$WELL)
      generic <- tolower(nm) %in% c("domestic", "domestic well", "well", "test well", "well no. 2", "water well")
      if (generic || nm %in% existing_names) nm <- paste0(nm, " (", r$API, ")")
      role <- .role_from_class(r$CLASS, r$STATUS, nm)
      use <- .use_from_row(r$API, r$CLASS, r$STATUS, nm, role)
      sstd <- .status_std(r$STATUS)
      has <- !is.na(mm$latitude)
      note <- paste0("NBMG compilation (GEOTHERM06102019), API ", r$API,
                     if (!is.na(r$PERMIT)) paste0(", permit ", r$PERMIT) else "",
                     "; status ", r$STATUS, "; class ", r$CLASS, ". ",
                     ifelse(is.na(r$REMARKS), "", substr(trimws(r$REMARKS), 1, 400)))
      permit_ok <- grepl("^[0-9]{4}$", ifelse(is.na(r$PERMIT), "", r$PERMIT))
      cols <- c("well_name","well_role","latitude","longitude","coord_key","total_depth","coordinate_source",
                "coordinate_uncertainty_m","notes","ndom_permit","api_number","spud_date","completion_date",
                "field_name","well_use","well_status_std")
      vals <- list(nm, role, if (has) mm$latitude else NA_real_, if (has) mm$longitude else NA_real_,
                   if (has) paste0(mm$latitude, "_", mm$longitude) else NA_character_, .num_commas(r$TD),
                   if (has) paste0("nbmg_geothermal_compilation_", tolower(mm$utm_crs), "_converted") else NA_character_,
                   if (has) 75 else NA_real_, note, if (permit_ok) r$PERMIT else NA_character_,
                   r$API, .parse_nbmg_date(r$SPUD_DATE), .parse_nbmg_date(r$COMPL_DATE),
                   if (grepl("^Steamboat", r$KGRA)) "Steamboat Springs" else NA_character_, use, sstd)
      dbExecute(con, paste0("INSERT INTO Wells (", paste(cols, collapse = ","), ") VALUES (", ph(length(cols)), ")"), params = vals)
      loaded <- dbGetQuery(con, "SELECT last_insert_rowid() id")$id
      existing_names <- c(existing_names, nm)
      disp <- "created_well"; st$created <- st$created + 1L
    }

    stage_cols <- c(paste0("src_", tolower(src_cols)), "scope", "utm_crs", "latitude", "longitude", "match_method",
                    "n_candidates", "matched_well_id", "review_flag", "distance_m", "permit_only", "disposition",
                    "loaded_well_id", "row_hash")
    dbExecute(con, paste0("INSERT INTO NBMG_Compilation_Records (", paste(stage_cols, collapse = ","), ") VALUES (", ph(length(stage_cols)), ")"),
      params = c(unname(as.list(unlist(r[src_cols]))),
                 list(mm$scope, mm$utm_crs, mm$latitude, mm$longitude, mm$match_method, mm$n_candidates, mid,
                      mm$review_flag, mm$distance_m, as.integer(isTRUE(mm$permit_only)), disp, loaded, h)))
    st$new_stage <- st$new_stage + 1L
  }
  message("  -> staged ", st$new_stage, " new row(s); created ", st$created, " well(s); filled ", st$filled_fields,
          " field(s) on existing wells; held ", st$held, "; staging-only ", st$staging_only, "; changed source rows ", st$changed_stage)
  invisible(st)
}
