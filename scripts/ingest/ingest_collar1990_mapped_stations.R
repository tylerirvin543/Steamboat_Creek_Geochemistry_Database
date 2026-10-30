# Ingest the Collar (1990) Table 4 stream-chemistry rows for stations whose
# location is already established. Only S10 (Steamboat Creek at Rhodes Road =
# SBRR; high confidence in data/raw/wells/historical_name_crosswalk.csv) is
# loaded. The other 62 stations stay in the CSV until Plate 4 is georeferenced.
#
# Idempotent: skips any (station, date) already present as an external_event_id.

library(DBI); library(dplyr)

ingest_collar1990_mapped_stations <- function(con,
    csv = "data/raw/historical/collar1990_table4_stream_chemistry.csv",
    station_map = c(S10 = "SBRR")) {
  message("---- Ingesting mapped Collar (1990) Table 4 stations ----")
  d <- read.csv(csv, stringsAsFactors = FALSE)
  d <- d[d$station %in% names(station_map), ]
  if (nrow(d) == 0) { message("  -> none"); return(invisible(0L)) }
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, notes) VALUES ('Collar 1990 M.S. thesis (Table 4)', 'Collar, R.J., 1990, M.S. thesis, Univ. of Auckland; stream chemistry, transcribed from the thesis page images')")
  sid <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name='Collar 1990 M.S. thesis (Table 4)'")$source_id
  n <- 0L
  for (i in seq_len(nrow(d))) {
    r <- d[i, ]
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ? OR external_station_code = ? LIMIT 1", params = list(station_map[[r$station]], station_map[[r$station]]))$location_id
    if (length(loc) == 0) { warning("No Locations row for ", station_map[[r$station]]); next }
    eid <- paste0("COLLAR1990_", r$station, "_", r$date)
    if (nrow(dbGetQuery(con, "SELECT 1 FROM Sampling_Events WHERE external_event_id = ?", params = list(eid))) > 0) next
    dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, ?, 'historical', ?)",
              params = list(eid, r$date, sprintf("Collar (1990) Table 4 station %s, thesis p.%s; discharge %s cfs", r$station, r$thesis_page, r$discharge_cfs)))
    ev <- dbGetQuery(con, "SELECT event_id FROM Sampling_Events WHERE external_event_id = ?", params = list(eid))$event_id
    dbExecute(con, "INSERT INTO Samples (location_id, event_id, sample_type, collection_time, data_source, external_event_id, notes) VALUES (?, ?, 'historical literature', ?, 'Collar 1990 Table 4', ?, ?)",
              params = list(loc, ev, r$date, eid, sprintf("Station %s (= SBRR per crosswalk).", r$station)))
    smp <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
    ins <- function(analyte, v) if (!is.na(v)) dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, source_id) VALUES (?, ?, ?, 'mg/L', ?)", params = list(smp, analyte, v, sid))
    ins("Cl", r$chloride_mg_l); ins("B", r$boron_mg_l)
    n <- n + 1L
  }
  message("  -> ", n, " Collar sample(s) added")
  invisible(n)
}
