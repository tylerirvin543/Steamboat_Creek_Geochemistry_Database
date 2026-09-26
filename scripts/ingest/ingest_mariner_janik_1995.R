# ============================================================
# ingest_mariner_janik_1995.R
#
# Purpose:
# Ingests the raw (non-reconstituted) 1991-1994 chemistry analyses from
# Table 1 of Mariner, R.H. and Janik, C.J. (1995), "Geochemical Data and
# Conceptual Model for the Steamboat Hills Geothermal System, Washoe
# County, Nevada" (Geothermal Resources Council Transactions, v. 19),
# read directly from
# docs/literature/Geochem Data and concept model Mariner & Janik 1995.pdf
# (pages 9-10 rendered to PNG at 250 dpi and read visually, since
# pdftotext -layout badly scrambles this table's multi-column OCR
# layout -- the same class of problem already flagged project-wide for
# the NDEP TFT Appendix D tables, well-log lithology, and Sorey &
# Colvard's own Appendix G).
#
# Only the RAW analyses are transcribed/ingested -- Table 1's
# "Recalc." rows (boiling-corrected, reconstituted whole-fluid
# compositions) are deliberately skipped. Reconstituted values are a
# derived quantity, not a field/lab measurement, and mixing them into
# Lab_Analyses under the same analyte codes as real measurements would
# misrepresent them -- consistent with this project's existing
# TWH-vs-TDH-vs-T_NaKCa distinction in the Sorey & Colvard (1992)
# ingest. A future session could add them under separate
# clearly-derived codes if the reconstituted-fluid history becomes
# analytically useful.
#
# Data file: data/raw/historical/mariner_janik_1995_table1_chemistry.csv
#   (hand-transcribed from the rendered page images, one row per
#   sample). match_type/matched_name records exactly how each site name
#   was resolved:
#     - "well_exact"      : Table 1 site name is a literal Wells.well_name
#     - "well_alias"      : resolved via an existing Well_Aliases row
#                           (e.g. "PW2-1" (no space) -> "PW 2-1")
#     - "location_exact"  : resolved to an existing, unambiguous Locations
#                           row (Brown School, Steinhardt)
#     - "location_ambiguous": tentatively matched but NOT certain (Curti,
#                           Herz -- this project's DB has more than one
#                           plausible candidate entity and the paper text
#                           doesn't disambiguate which one); flagged in
#                           notes, never silently treated as confirmed.
#     - "unresolved"      : no existing Wells/Locations match found
#                           (Stuart, Peigh, Stmgid 4, and five regional
#                           background creek/spring comparison sites) --
#                           a new, coordinate-less provisional Locations
#                           row is created, per this project's standing
#                           provisional-entity convention (never guessed).
#
# Value parsing: several cells are non-detects written as "<X" (e.g.
# "<.02"). .parse_qualified_value() splits these into a NULL value +
# a detection_limit + qualifier "<", matching how detection-limited
# values are represented elsewhere in Lab_Analyses.
#
# Idempotency: matched on external_station_code (Locations),
# external_sample_id (Samples), and (sample_id, analyte, source_id)
# for Lab_Analyses (anti_join) -- same pattern as
# ingest_historical_sorey1992.R. Safe to re-run.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

.parse_qualified_value <- function(x) {
  x <- trimws(as.character(x))
  if (is.na(x) || x == "") return(list(value = NA_real_, dl = NA_real_, qual = NA_character_))
  if (grepl("^<", x)) {
    return(list(value = NA_real_, dl = as.numeric(sub("^<", "", x)), qual = "<"))
  }
  list(value = suppressWarnings(as.numeric(x)), dl = NA_real_, qual = NA_character_)
}

ingest_mariner_janik_1995 <- function(
    con,
    csv_path = "data/raw/historical/mariner_janik_1995_table1_chemistry.csv") {

  message("---- Starting Mariner & Janik (1995) Table 1 chemistry ingest ----")

  if (!file_exists(csv_path)) {
    message("[mariner_janik_1995] No file at ", csv_path, " -- skipping.")
    return(invisible(NULL))
  }

  dbExecute(con, "PRAGMA foreign_keys = ON;")

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES (
      'Mariner & Janik 1995 (GRC Transactions v.19)',
      'Table 1 raw chemistry, docs/literature/Geochem Data and concept model Mariner & Janik 1995.pdf pages 9-10; hand-transcribed from rendered page images 2026-09-26.'
    )
  ")
  source_id <- dbGetQuery(con,
    "SELECT source_id FROM Data_Sources WHERE name = 'Mariner & Janik 1995 (GRC Transactions v.19)'"
  )$source_id[1]

  # Force every value column to character on read -- several contain
  # "<X" non-detect notation which would otherwise force the whole
  # column to character anyway (or silently coerce to NA); reading them
  # all as character keeps parsing explicit and in one place below.
  val_cols <- c("T_c","ph","ph_temp_c","SiO2","Ca","Mg","Na","K","Li",
                "HCO3","F","Cl","Br","SO4","B","H2S","dD","d18O")
  col_spec <- do.call(readr::cols, c(
    list(sample_date = readr::col_character()),
    setNames(rep(list(readr::col_character()), length(val_cols)), val_cols)
  ))
  rows <- read_csv(csv_path, show_col_types = FALSE, col_types = col_spec)

  # ------------------------------------------------------------
  # RESOLVE / CREATE LOCATIONS (one per distinct site name)
  # ------------------------------------------------------------
  sites <- rows %>% distinct(site, match_type, matched_name, entity_hint)
  loc_id_for_site <- character(0)
  locations_created <- 0L

  for (i in seq_len(nrow(sites))) {
    s <- sites[i, ]
    ext_code <- paste0("MJ1995_", gsub("[^A-Za-z0-9]+", "_", s$site))

    existing_loc <- dbGetQuery(con,
      "SELECT location_id FROM Locations WHERE external_station_code = ?",
      params = list(ext_code))

    if (nrow(existing_loc) > 0) {
      loc_id <- existing_loc$location_id[1]
    } else {
      lat <- NA_real_; lon <- NA_real_; name <- s$site; site_type <- s$entity_hint
      coord_source <- NA_character_

      if (s$match_type %in% c("well_exact", "well_alias")) {
        well_match <- dbGetQuery(con,
          "SELECT well_id, latitude, longitude FROM Wells WHERE well_name = ?
           UNION
           SELECT w.well_id, w.latitude, w.longitude FROM Well_Aliases a
           JOIN Wells w ON w.well_id = a.well_id WHERE a.alias = ?",
          params = list(s$matched_name, s$matched_name))
        if (nrow(well_match) > 0) {
          lat <- well_match$latitude[1]; lon <- well_match$longitude[1]
          if (!is.na(lat)) coord_source <- "copied_from_wells_table"
          name <- paste0(s$site, " (Mariner & Janik 1995; = Wells '", s$matched_name, "')")
          site_type <- "well"
        } else {
          warning("[mariner_janik_1995] matched_name '", s$matched_name,
                   "' not found in Wells/Well_Aliases for site '", s$site, "' -- creating unresolved Location instead.")
        }
      } else if (s$match_type %in% c("location_exact", "location_ambiguous")) {
        loc_match <- dbGetQuery(con,
          "SELECT location_id, latitude, longitude, site_type FROM Locations WHERE name = ?",
          params = list(s$matched_name))
        if (nrow(loc_match) > 0) {
          # Reuse the existing Locations row directly rather than
          # creating a second row for the same real-world entity.
          loc_id_for_site[s$site] <- as.character(loc_match$location_id[1])
          next
        } else {
          warning("[mariner_janik_1995] matched_name '", s$matched_name,
                   "' not found in Locations for site '", s$site, "' -- creating unresolved Location instead.")
        }
      }

      ambiguity_note <- if (s$match_type == "location_ambiguous") {
        " NOTE: tentative match only, see CSV notes column -- not confirmed."
      } else if (s$match_type == "unresolved") {
        " Unresolved: no existing Wells/Locations match; provisional entity."
      } else ""

      dbExecute(con, "
        INSERT INTO Locations
          (external_station_code, name, latitude, longitude, crs, site_type,
           coordinate_source, notes)
        VALUES (?, ?, ?, ?, 'EPSG:4326', ?, ?, ?)
      ", params = list(
        ext_code, name, lat, lon, site_type, coord_source,
        paste0("Mariner & Janik (1995) Table 1 site '", s$site, "'.", ambiguity_note)
      ))
      loc_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      locations_created <- locations_created + 1L
    }
    loc_id_for_site[s$site] <- as.character(loc_id)
  }

  rows$location_id <- as.integer(loc_id_for_site[rows$site])

  # ------------------------------------------------------------
  # SAMPLING EVENTS + SAMPLES
  # ------------------------------------------------------------
  events_created <- 0L
  samples_created <- 0L
  sample_id_map <- integer(nrow(rows))

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    ext_id <- paste0("MJ1995_", gsub("[^A-Za-z0-9]+", "_", r$site), "_", r$sample_date)

    existing_event <- dbGetQuery(con,
      "SELECT event_id FROM Sampling_Events WHERE external_event_id = ?",
      params = list(ext_id))
    if (nrow(existing_event) > 0) {
      event_id <- existing_event$event_id[1]
    } else {
      dbExecute(con, "
        INSERT INTO Sampling_Events (external_event_id, date, purpose, notes)
        VALUES (?, ?, 'historical', 'Mariner & Janik (1995) Table 1')
      ", params = list(ext_id, r$sample_date))
      event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      events_created <- events_created + 1L
    }

    existing_sample <- dbGetQuery(con,
      "SELECT sample_id FROM Samples WHERE external_sample_id = ?",
      params = list(ext_id))
    if (nrow(existing_sample) > 0) {
      sample_id <- existing_sample$sample_id[1]
    } else {
      dbExecute(con, "
        INSERT INTO Samples
          (location_id, event_id, sample_type, collection_time,
           external_event_id, external_sample_id, data_source, notes)
        VALUES (?, ?, 'historical', ?, ?, ?, 'Mariner & Janik 1995', ?)
      ", params = list(
        r$location_id, event_id, r$sample_date, ext_id, ext_id, r$notes
      ))
      sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      samples_created <- samples_created + 1L
    }
    sample_id_map[i] <- sample_id
  }
  rows$sample_id <- sample_id_map

  # ------------------------------------------------------------
  # LAB ANALYSES (long format)
  # ------------------------------------------------------------
  analyte_cols <- c(
    T_c = "temperature", ph = "pH", SiO2 = "SiO2", Ca = "Ca", Mg = "Mg",
    Na = "Na", K = "K", Li = "Li", HCO3 = "Alkalinity", F = "F",
    Cl = "Cl", Br = "Br", SO4 = "SO4", B = "B", H2S = "H2S",
    dD = "dD", d18O = "d18O"
  )
  units_for <- c(
    temperature = "deg C", pH = "SU", SiO2 = "mg/L", Ca = "mg/L",
    Mg = "mg/L", Na = "mg/L", K = "mg/L", Li = "mg/L",
    Alkalinity = "mg/L", F = "mg/L", Cl = "mg/L", Br = "mg/L",
    SO4 = "mg/L", B = "mg/L", H2S = "mg/L", dD = "permil VSMOW",
    d18O = "permil VSMOW"
  )

  long_rows <- list()
  for (raw_col in names(analyte_cols)) {
    analyte <- analyte_cols[[raw_col]]
    parsed <- lapply(rows[[raw_col]], .parse_qualified_value)
    val  <- sapply(parsed, function(p) p$value)
    dl   <- sapply(parsed, function(p) p$dl)
    qual <- sapply(parsed, function(p) p$qual)
    keep <- !is.na(val) | !is.na(dl)
    if (!any(keep)) next
    long_rows[[analyte]] <- data.frame(
      sample_id = rows$sample_id[keep],
      analyte = analyte,
      value = val[keep],
      units = units_for[[analyte]],
      fraction = NA_character_,
      method = "Mariner & Janik (1995) Table 1",
      detection_limit = dl[keep],
      qualifier = qual[keep],
      source_id = source_id,
      stringsAsFactors = FALSE
    )
  }
  lab_new <- bind_rows(long_rows)

  existing_lab <- dbGetQuery(con, "SELECT sample_id, analyte, source_id FROM Lab_Analyses")
  lab_new <- lab_new %>% anti_join(existing_lab, by = c("sample_id", "analyte", "source_id"))

  if (nrow(lab_new) > 0) {
    dbAppendTable(con, "Lab_Analyses", lab_new)
  }

  message("  -> Locations created: ", locations_created,
          " | Sampling_Events created: ", events_created,
          " | Samples created: ", samples_created,
          " | Lab_Analyses rows inserted: ", nrow(lab_new))
  message("Mariner & Janik (1995) chemistry ingest complete.")

  invisible(list(
    locations_created = locations_created,
    events_created = events_created,
    samples_created = samples_created,
    lab_rows_inserted = nrow(lab_new)
  ))
}
