# ============================================================
# qc_well_log_matches.R
#
# Purpose (added 2026-09-12, session 24):
# A repeatable, regenerable spatial-match candidates report for
# Well_Log_Documents rows that have a coordinate but no confirmed
# well_id -- replaces the earlier pattern (see AGENTS.md, sessions
# 10-11) of a one-off, conversation-driven "nearest NBMG candidate"
# writeup for each new batch of well logs. Every run overwrites
# data/derived/well_log_match_candidates.csv with the current nearest-
# neighbor distances so a human can review and, if confident, add a
# row to data/raw/ndwr/well_log_document_map.csv.
#
# Deliberately does NOT write to the database or auto-match anything --
# same standing rule as every other identity-matching step in this
# project (never guess a specific-well identity from proximity alone).
# ============================================================

library(DBI)
library(dplyr)

#' Haversine distance in meters between two lat/lon pairs (vectorized).
.haversine_m <- function(lat1, lon1, lat2, lon2) {
  R <- 6371000
  phi1 <- lat1 * pi / 180; phi2 <- lat2 * pi / 180
  dphi <- (lat2 - lat1) * pi / 180
  dlambda <- (lon2 - lon1) * pi / 180
  a <- sin(dphi / 2)^2 + cos(phi1) * cos(phi2) * sin(dlambda / 2)^2
  2 * R * atan2(sqrt(a), sqrt(1 - a))
}

#' For every unmatched (well_id IS NULL) Well_Log_Documents row with a
#' coordinate, find the nearest existing Wells row and the nearest
#' existing Locations row, with distance in meters. Written to
#' out_csv every run (not appended) -- always reflects current state.
qc_well_log_matches <- function(con, out_csv = "data/derived/well_log_match_candidates.csv", close_match_threshold_m = 200) {

  message("---- QC: well-log spatial match candidates ----")

  docs <- dbGetQuery(con, "
    SELECT document_id, file_path, alt_file_path, log_number, well_name_parsed,
           latitude, longitude, match_method, plss_latlon_method,
           work_type, proposed_use, flags
    FROM Well_Log_Documents
    WHERE well_id IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL
  ")

  if (nrow(docs) == 0) {
    message("  -> No unmatched, coordinate-having well-log documents to check.")
    return(invisible(NULL))
  }

  wells <- dbGetQuery(con, "SELECT well_id, well_name, latitude, longitude FROM Wells WHERE latitude IS NOT NULL")
  locs <- dbGetQuery(con, "SELECT location_id, name, latitude, longitude FROM Locations WHERE latitude IS NOT NULL")

  nearest <- function(lat, lon, ref, id_col, name_col) {
    if (nrow(ref) == 0) return(list(id = NA, name = NA_character_, dist_m = NA_real_))
    d <- .haversine_m(lat, lon, ref$latitude, ref$longitude)
    i <- which.min(d)
    list(id = ref[[id_col]][i], name = ref[[name_col]][i], dist_m = round(d[i], 1))
  }

  #' Build a plain-English "what to do next" recommendation for one
  #' candidate row. More than one reason can apply (joined with " | ").
  #' close_match_threshold_m is deliberately a named, tunable argument
  #' (not a silent magic number) -- see qc_well_log_matches()'s own
  #' argument of the same name.
  .recommend <- function(has_alt, dist_m, log_number, close_match_threshold_m) {
    reasons <- character(0)
    if (!has_alt) {
      reasons <- c(reasons, paste0(
        "Consider downloading NDWR's reformatted/streamlined PDF page for log #",
        log_number, " and saving it as '", log_number, "(2).pdf' for easier parsing/cross-checking."
      ))
    }
    if (!is.na(dist_m) && dist_m < close_match_threshold_m) {
      reasons <- c(reasons, paste0(
        "Nearest candidate is within ", round(dist_m), " m -- review and consider adding to well_log_document_map.csv."
      ))
    } else {
      reasons <- c(reasons, "No confident match found (nearest candidate is far) -- keep unresolved for now.")
    }
    paste(reasons, collapse = " | ")
  }

  out <- lapply(seq_len(nrow(docs)), function(i) {
    d <- docs[i, ]
    nw <- nearest(d$latitude, d$longitude, wells, "well_id", "well_name")
    nl <- nearest(d$latitude, d$longitude, locs, "location_id", "name")
    best_dist <- suppressWarnings(min(nw$dist_m, nl$dist_m, na.rm = TRUE))
    if (!is.finite(best_dist)) best_dist <- NA_real_
    has_alt <- !is.na(d$alt_file_path)
    data.frame(
      document_id = d$document_id,
      log_number = d$log_number,
      well_name_parsed = d$well_name_parsed,
      latitude = d$latitude, longitude = d$longitude,
      match_method = d$match_method,
      plss_latlon_method = d$plss_latlon_method,
      work_type = d$work_type,
      proposed_use = d$proposed_use,
      has_alt_scan = has_alt,
      nearest_well_name = nw$name, nearest_well_dist_m = nw$dist_m,
      nearest_location_name = nl$name, nearest_location_dist_m = nl$dist_m,
      recommendation = .recommend(has_alt, best_dist, d$log_number, close_match_threshold_m),
      flags = d$flags,
      stringsAsFactors = FALSE
    )
  })

  result <- bind_rows(out) %>% arrange(pmin(nearest_well_dist_m, nearest_location_dist_m, na.rm = TRUE))

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(result, out_csv, row.names = FALSE, na = "")

  n_tight <- sum(pmin(result$nearest_well_dist_m, result$nearest_location_dist_m, na.rm = TRUE) < 100, na.rm = TRUE)
  message("  -> Wrote ", nrow(result), " candidate row(s) to ", out_csv,
          " (", n_tight, " within 100 m of an existing Wells/Locations row -- review before promoting; never auto-matched).")

  invisible(result)
}
