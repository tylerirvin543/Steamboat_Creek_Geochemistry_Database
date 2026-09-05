# ============================================================
# promote_staged_ndep.R
#
# Purpose:
# Promote rows from Staging_NDEP_WQ (populated by ingest_ndep_prr.R,
# never written to directly by anything else) into the core
# Samples / Sampling_Events / Lab_Analyses tables, once -- and only
# once -- a station has a human-confirmed location.
#
# This is deliberately a *separate*, manually-invoked step from
# ingest_ndep_prr.R itself: PDF-extracted chemistry should never
# silently become "real" data without a location to anchor it, and a
# station_name -> external_station_code mapping is exactly the kind
# of judgment call (see ingest_image_locations.R's identical
# philosophy) that stays with a human-maintained CSV, not inferred.
#
# Mapping file: data/raw/ndep/PRR/staged_ndep_location_map.csv
#   columns: station_name, external_station_code, name, site_type,
#            latitude, longitude, coordinate_source,
#            coordinate_uncertainty_m, notes
#   Rows with blank lat/long are left unresolved on purpose (see
#   notes column for why) -- their Staging_NDEP_WQ rows are simply
#   skipped, not promoted, until coordinates are filled in.
#
# Idempotency: adds a `promoted_at` column to Staging_NDEP_WQ (no-op
# migration if already present) and only promotes rows where it is
# still NULL; once promoted, a row is never re-inserted even if this
# script is re-run.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

# SGS lab-report parameter name -> project-standard analyte code, matching
# the convention already used for open-data NDEP chemistry (see
# database/schema/ndep_analyte_map.R: Cl, Ca, Na, K, SO4, HCO3, SiO2, ...).
# Without this mapping, promoted PRR chemistry would use verbatim SGS
# names ("Chloride", "Calcium", ...) and silently NOT match
# vw_major_ions' WHERE analyte IN ('Ca','Mg','Na','K','Cl','SO4','HCO3')
# filter -- i.e. it would never appear in the GIS/major-ions layer at all.
sgs_analyte_map <- c(
  "Chloride" = "Cl",
  "Sulfate" = "SO4",
  "Calcium" = "Ca",
  "Magnesium" = "Mg",
  "Sodium" = "Na",
  "Potassium" = "K",
  "Fluoride" = "F",
  "Bromide" = "Br",
  "Silica as SiO2" = "SiO2",
  "Alkalinity, Total (As CaCO3)" = "HCO3",
  "Alkalinity, Bicarbonate (As CaCO3)" = "HCO3",
  "Alkalinity, Bicarbonate (As" = "HCO3",  # truncated variant from a wrapped source line -- see parse_ndep_prr_pdf.R
  "Alkalinity, Carbonate (As CaCO3)" = "CO3",
  "Total Dissolved Solids" = "TDS",
  "Suspended Solids" = "TSS",
  "Antimony" = "Sb",
  "Arsenic" = "As",
  "Boron" = "B",
  "Lithium" = "Li"
)

promote_staged_ndep <- function(con,
                                 map_csv = "data/raw/ndep/PRR/staged_ndep_location_map.csv",
                                 sampling_purpose = "historical") {

  message("---- Starting NDEP staged-data promotion ----")

  staging_cols <- dbListFields(con, "Staging_NDEP_WQ")
  if (!"promoted_at" %in% staging_cols) {
    dbExecute(con, "ALTER TABLE Staging_NDEP_WQ ADD COLUMN promoted_at TEXT")
  }
  if (!"staging_id" %in% staging_cols) {
    # Give staged rows a stable identity to key promotion off of --
    # SQLite's implicit rowid works, but naming it explicitly makes
    # the idempotency logic below legible.
    dbExecute(con, "ALTER TABLE Staging_NDEP_WQ ADD COLUMN staging_id INTEGER")
    dbExecute(con, "UPDATE Staging_NDEP_WQ SET staging_id = rowid WHERE staging_id IS NULL")
  }

  if (!file_exists(map_csv)) {
    message("[promote NDEP] No location map at ", map_csv, " -- nothing to promote.")
    return(invisible(NULL))
  }

  map <- read_csv(map_csv, show_col_types = FALSE) |>
    filter(!is.na(latitude), !is.na(longitude), !is.na(external_station_code))

  if (nrow(map) == 0) {
    message("[promote NDEP] No resolved (lat/lon-having) rows in the location map yet.")
    return(invisible(NULL))
  }

  # ---- Register any locations from the map that don't exist yet ----
  existing_locations <- dbGetQuery(con, "SELECT location_id, external_station_code FROM Locations")
  new_locs <- map |> filter(!(external_station_code %in% existing_locations$external_station_code))
  if (nrow(new_locs) > 0) {
    to_insert <- new_locs |>
      transmute(
        external_station_code,
        name = if_else(!is.na(name) & name != "", name, external_station_code),
        latitude, longitude,
        crs = "EPSG:4326",
        site_type,
        coordinate_source, coordinate_uncertainty_m,
        notes
      )
    dbAppendTable(con, "Locations", to_insert)
    message("  -> Registered ", nrow(to_insert), " new Location(s): ",
            paste(to_insert$external_station_code, collapse = ", "))
  }

  locations <- dbGetQuery(con, "SELECT location_id, external_station_code FROM Locations")

  # ---- Pull unpromoted staged rows for resolvable stations only ----
  staged <- dbGetQuery(con, "SELECT * FROM Staging_NDEP_WQ WHERE promoted_at IS NULL")
  staged <- staged |>
    inner_join(map |> select(station_name, external_station_code), by = "station_name") |>
    inner_join(locations, by = "external_station_code")

  if (nrow(staged) == 0) {
    message("[promote NDEP] No unpromoted rows have a resolvable location yet.")
    return(invisible(NULL))
  }

  source_id <- dbGetQuery(
    con, "SELECT source_id FROM Data_Sources WHERE name = 'Nevada DEP (Public Records Request)'"
  )$source_id[1]

  # ---- One Sampling_Event + one Samples row per (location, date) ----
  events_needed <- staged |> distinct(sample_date)
  existing_events <- dbGetQuery(con, "SELECT event_id, external_event_id FROM Sampling_Events")

  new_events <- events_needed |>
    mutate(external_event_id = paste0("NDEP_PRR_", sample_date)) |>
    filter(!(external_event_id %in% existing_events$external_event_id)) |>
    transmute(
      external_event_id,
      date = sample_date,
      purpose = sampling_purpose,
      notes = "Auto-created for NDEP PRR chemistry promotion"
    )
  if (nrow(new_events) > 0) {
    dbAppendTable(con, "Sampling_Events", new_events)
  }
  events <- dbGetQuery(con, "SELECT event_id, external_event_id FROM Sampling_Events")

  staged <- staged |>
    mutate(external_event_id = paste0("NDEP_PRR_", sample_date)) |>
    left_join(events, by = "external_event_id")

  samples_needed <- staged |> distinct(location_id, event_id, sample_date)
  existing_samples <- dbGetQuery(con, "SELECT sample_id, location_id, event_id, collection_time FROM Samples")

  new_samples <- samples_needed |>
    anti_join(
      existing_samples, by = c("location_id", "event_id")
    ) |>
    transmute(
      location_id, event_id,
      sample_type = "NDEP PRR chemistry",
      collection_time = sample_date,
      data_source = "NDEP PRR"
    )
  if (nrow(new_samples) > 0) {
    dbAppendTable(con, "Samples", new_samples)
  }
  samples <- dbGetQuery(con, "SELECT sample_id, location_id, event_id FROM Samples")

  staged <- staged |> left_join(samples, by = c("location_id", "event_id"))

  # ---- Lab_Analyses rows ----
  unmapped <- staged |>
    filter(!is.na(sample_id), !(analyte %in% names(sgs_analyte_map))) |>
    distinct(analyte)
  if (nrow(unmapped) > 0) {
    message("  -> Note: ", nrow(unmapped), " analyte name(s) have no standard-code mapping, kept as-is: ",
            paste(unmapped$analyte, collapse = ", "))
  }

  to_insert_lab <- staged |>
    filter(!is.na(sample_id)) |>
    mutate(analyte = if_else(analyte %in% names(sgs_analyte_map), sgs_analyte_map[analyte], analyte)) |>
    transmute(
      sample_id, analyte, value, units, method,
      detection_limit,
      source_id = source_id
    )

  if (nrow(to_insert_lab) > 0) {
    dbAppendTable(con, "Lab_Analyses", to_insert_lab)
  }

  dbExecute(
    con,
    paste0("UPDATE Staging_NDEP_WQ SET promoted_at = '",
           format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
           "' WHERE staging_id IN (", paste(staged$staging_id, collapse = ","), ")")
  )

  message("---- Promotion complete: ", nrow(to_insert_lab), " Lab_Analyses row(s), ",
          nrow(new_samples), " new Samples, ", nrow(new_events), " new Sampling_Events ----")
  invisible(list(lab_analyses = nrow(to_insert_lab), samples = nrow(new_samples), events = nrow(new_events)))
}
