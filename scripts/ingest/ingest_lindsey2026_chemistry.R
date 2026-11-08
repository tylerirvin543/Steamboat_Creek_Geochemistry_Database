# ============================================================
# ingest_lindsey2026_chemistry.R
#
# Stores the two Lindsey et al. (2026) Table 5 samples:
#   SBG001 (geysering pipe)  -> Location SBW_0003
#   SBG002 (runoff channel)  -> Location SBF_0001, as a second sample there
# No new Locations. Units follow project convention: Alkalinity on the HCO3
# basis (as printed), Si as element, B/Li/As converted ug/L -> mg/L.
# Idempotent by external_sample_id and (sample, analyte, source).
# ============================================================
library(DBI); library(dplyr); library(readr)

ingest_lindsey2026_chemistry <- function(con, csv = "data/raw/historical/lindsey2026_table5_chemistry.csv") {
  message("---- Ingesting Lindsey et al. (2026) Table 5 chemistry ----")
  if (!file.exists(csv)) { message("  -> no file, skipping"); return(invisible(NULL)) }
  d <- read_csv(csv, col_types = cols(.default = col_character(), sample_date = col_character()), show_col_types = FALSE)
  src_name <- "Lindsey et al. (2026) Table 5, lower sinter terrace samples"
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, notes) VALUES (?, ?)",
            params = list(src_name, "Published table values; samples collected by the NBMG monitoring program June 2025. No temperature reported."))
  source_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ?", params = list(src_name))$source_id
  n_ev <- n_s <- n_l <- 0L
  for (i in seq_len(nrow(d))) {
    r <- d[i, ]
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(r$target_location))$location_id
    if (length(loc) != 1) { warning("Location ", r$target_location, " not found; skipping ", r$sample_id); next }
    ext_ev <- paste0("LINDSEY2026_", r$sample_id, "_", r$sample_date)
    ev <- dbGetQuery(con, "SELECT event_id FROM Sampling_Events WHERE external_event_id = ?", params = list(ext_ev))
    if (nrow(ev) == 0) {
      dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, ?, 'post-eruption', ?)",
                params = list(ext_ev, r$sample_date, paste0("date_precision='", r$date_precision, "'; ", r$description)))
      ev <- dbGetQuery(con, "SELECT last_insert_rowid() AS event_id"); n_ev <- n_ev + 1L
    }
    sm <- dbGetQuery(con, "SELECT sample_id FROM Samples WHERE external_sample_id = ?", params = list(ext_ev))
    if (nrow(sm) == 0) {
      dbExecute(con, "INSERT INTO Samples (location_id, event_id, sample_type, collection_time, external_event_id, external_sample_id, data_source, notes)
                      VALUES (?, ?, 'literature', ?, ?, ?, 'Lindsey 2026', ?)",
                params = list(loc, ev$event_id[1], r$sample_date, ext_ev, ext_ev, paste0(r$sample_id, ": ", r$notes)))
      sm <- dbGetQuery(con, "SELECT last_insert_rowid() AS sample_id"); n_s <- n_s + 1L
    }
    num <- function(x) as.numeric(r[[x]])
    vals <- list(pH = c(num("pH"), "SU"), SC = c(num("conductivity_uS_cm"), "uS/cm"), TDS = c(num("TDS_mg_L"), "mg/L"),
                 Na = c(num("Na_mg_L"), "mg/L"), K = c(num("K_mg_L"), "mg/L"), Ca = c(num("Ca_mg_L"), "mg/L"),
                 Mg = c(num("Mg_mg_L"), "mg/L"), Cl = c(num("Cl_mg_L"), "mg/L"), SO4 = c(num("SO4_mg_L"), "mg/L"),
                 Alkalinity = c(num("Alkalinity_mg_L_as_HCO3"), "mg/L"), Si = c(num("Si_mg_L"), "mg/L"),
                 B = c(num("B_ug_L") / 1000, "mg/L"), Li = c(num("Li_ug_L") / 1000, "mg/L"), As = c(num("As_ug_L") / 1000, "mg/L"))
    for (a in names(vals)) {
      if (nrow(dbGetQuery(con, "SELECT 1 FROM Lab_Analyses WHERE sample_id = ? AND analyte = ? AND source_id = ?",
                          params = list(sm$sample_id[1], a, source_id))) > 0) next
      dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, fraction, method, detection_limit, qualifier, source_id)
                      VALUES (?, ?, ?, ?, NULL, 'Lindsey et al. 2026 Table 5', NULL, NULL, ?)",
                params = list(sm$sample_id[1], a, as.numeric(vals[[a]][1]), vals[[a]][2], source_id))
      n_l <- n_l + 1L
    }
  }
  message("  -> events ", n_ev, ", samples ", n_s, ", Lab_Analyses rows ", n_l)
  invisible(list(events = n_ev, samples = n_s, rows = n_l))
}
