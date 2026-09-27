# ============================================================
# qc_location_proximity.R
#
# Purpose (added 2026-09-27):
# A systematic, repeatable coordinate-proximity scan across every
# coordinate-having Locations row (which is also every real-world
# point a Conductivity_Loggers/Temperature_Loggers row resolves to,
# since neither logger table carries its own lat/lon -- both link via
# location_id into Locations), plus a separate Wells-vs-Locations pass
# (Wells is an independent point table with its own latitude/
# longitude, only sometimes linked to a Locations row via
# Wells.location_id).
#
# This generalizes the one-off, conversation-driven discovery of the
# SBRR/SB5/SB6/STBT02Steamboat-2a cluster (see AGENTS.md, the plan that
# introduced Location_Aliases / database/schema/19_location_aliases_
# schema.R) into a standing, regenerable report -- mirrors
# qc_well_log_matches.R's own established pattern exactly (reuses its
# .haversine_m() helper, copied rather than sourced/imported, matching
# this project's existing convention of small helper duplication across
# independent QC scripts).
#
# Deliberately does NOT write to the database, create a
# Location_Aliases row, or merge/re-point anything -- same standing
# rule as every other identity-matching step in this project: never
# guess an identity from proximity alone. A human reviews the CSV and,
# if confident, adds a row to data/raw/locations/location_aliases.csv
# or data/raw/wells/well_aliases.csv themselves.
# ============================================================

library(DBI)
library(dplyr)

#' Haversine distance in meters between two lat/lon pairs (vectorized).
#' Copied from scripts/qc/qc_well_log_matches.R -- kept independent on
#' purpose (see file header).
.haversine_m <- function(lat1, lon1, lat2, lon2) {
  R <- 6371000
  phi1 <- lat1 * pi / 180; phi2 <- lat2 * pi / 180
  dphi <- (lat2 - lat1) * pi / 180
  dlambda <- (lon2 - lon1) * pi / 180
  a <- sin(dphi / 2)^2 + cos(phi1) * cos(phi2) * sin(dlambda / 2)^2
  2 * R * atan2(sqrt(a), sqrt(1 - a))
}

#' Systematic Locations-vs-Locations and Wells-vs-Locations coordinate-
#' proximity scan. Writes out_csv every run (not appended) -- always
#' reflects current state. Pairs already resolved via the existing
#' Location_Aliases table are excluded, so this only ever surfaces
#' NEW, unreviewed candidates.
qc_location_proximity <- function(con, threshold_m = 200,
                                   out_csv = "data/derived/location_proximity_candidates.csv") {

  message("---- QC: Locations/Wells coordinate-proximity scan ----")

  locs <- dbGetQuery(con, "
    SELECT location_id, name, external_station_code, site_type, latitude, longitude
    FROM Locations
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
  ")

  if (nrow(locs) < 2) {
    message("  -> Fewer than 2 coordinate-having Locations rows -- nothing to compare.")
    return(invisible(NULL))
  }

  # Pairs already known and handled -- never re-flag these.
  known_aliases <- if (dbExistsTable(con, "Location_Aliases")) {
    dbGetQuery(con, "
      SELECT la.location_id AS canonical_location_id, l2.location_id AS alias_location_id
      FROM Location_Aliases la
      JOIN Locations l1 ON l1.location_id = la.location_id
      LEFT JOIN Locations l2
        ON l2.name = la.alias OR l2.external_station_code = la.alias
    ")
  } else {
    data.frame(canonical_location_id = integer(0), alias_location_id = integer(0))
  }
  known_pairs <- unique(na.omit(paste(
    pmin(known_aliases$canonical_location_id, known_aliases$alias_location_id),
    pmax(known_aliases$canonical_location_id, known_aliases$alias_location_id)
  )))

  # ---- Pass 1: Locations vs. Locations ----
  n <- nrow(locs)
  loc_pairs <- list()
  for (i in seq_len(n - 1)) {
    d <- .haversine_m(locs$latitude[i], locs$longitude[i],
                       locs$latitude[(i + 1):n], locs$longitude[(i + 1):n])
    hits <- which(d < threshold_m)
    if (length(hits) > 0) {
      js <- (i + 1):n
      js <- js[hits]
      loc_pairs[[length(loc_pairs) + 1]] <- data.frame(
        pair_type = "location_vs_location",
        id_1 = locs$location_id[i], name_1 = locs$name[i],
        external_station_code_1 = locs$external_station_code[i], site_type_1 = locs$site_type[i],
        id_2 = locs$location_id[js], name_2 = locs$name[js],
        external_station_code_2 = locs$external_station_code[js], site_type_2 = locs$site_type[js],
        distance_m = round(d[hits], 1),
        stringsAsFactors = FALSE
      )
    }
  }
  loc_result <- if (length(loc_pairs) > 0) bind_rows(loc_pairs) else
    data.frame(pair_type = character(0), id_1 = integer(0), name_1 = character(0),
               external_station_code_1 = character(0), site_type_1 = character(0),
               id_2 = integer(0), name_2 = character(0), external_station_code_2 = character(0),
               site_type_2 = character(0), distance_m = numeric(0), stringsAsFactors = FALSE)

  if (nrow(loc_result) > 0) {
    pair_key <- paste(pmin(loc_result$id_1, loc_result$id_2), pmax(loc_result$id_1, loc_result$id_2))
    loc_result <- loc_result[!pair_key %in% known_pairs, , drop = FALSE]
  }

  # ---- Pass 2: Wells vs. Locations (independent coordinate sources) ----
  wells <- dbGetQuery(con, "
    SELECT well_id, well_name, location_id AS linked_location_id, latitude, longitude
    FROM Wells
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
  ")

  well_pairs <- list()
  if (nrow(wells) > 0) {
    for (i in seq_len(nrow(wells))) {
      d <- .haversine_m(wells$latitude[i], wells$longitude[i], locs$latitude, locs$longitude)
      hits <- which(d < threshold_m)
      if (length(hits) > 0) {
        already_linked <- !is.na(wells$linked_location_id[i]) &
          locs$location_id[hits] == wells$linked_location_id[i]
        hits <- hits[!already_linked]
      }
      if (length(hits) > 0) {
        well_pairs[[length(well_pairs) + 1]] <- data.frame(
          pair_type = "well_vs_location",
          id_1 = wells$well_id[i], name_1 = wells$well_name[i],
          external_station_code_1 = NA_character_, site_type_1 = "well",
          id_2 = locs$location_id[hits], name_2 = locs$name[hits],
          external_station_code_2 = locs$external_station_code[hits], site_type_2 = locs$site_type[hits],
          distance_m = round(d[hits], 1),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  well_result <- if (length(well_pairs) > 0) bind_rows(well_pairs) else
    data.frame(pair_type = character(0), id_1 = integer(0), name_1 = character(0),
               external_station_code_1 = character(0), site_type_1 = character(0),
               id_2 = integer(0), name_2 = character(0), external_station_code_2 = character(0),
               site_type_2 = character(0), distance_m = numeric(0), stringsAsFactors = FALSE)

  result <- bind_rows(loc_result, well_result)

  if (nrow(result) == 0) {
    message("  -> No new candidate pairs within ", threshold_m,
            " m found (beyond those already resolved in Location_Aliases).")
    dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
    write.csv(result, out_csv, row.names = FALSE, na = "")
    return(invisible(result))
  }

  result$recommendation <- ifelse(
    result$distance_m < 100,
    ifelse(result$pair_type == "location_vs_location",
           "review: within 100m, consider a Location_Aliases row",
           "review: Wells row may duplicate/co-locate with this Locations row"),
    "review: within threshold but not tight -- likely a genuinely separate nearby point"
  )

  result <- result %>% arrange(distance_m)

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(result, out_csv, row.names = FALSE, na = "")

  n_tight <- sum(result$distance_m < 100, na.rm = TRUE)
  message("  -> Wrote ", nrow(result), " candidate pair(s) to ", out_csv,
          " (", n_tight, " within 100 m -- review before adding any alias; never auto-matched).")

  invisible(result)
}
