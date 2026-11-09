# ============================================================
# ingest_white1964_gs_logs.R
#
# Loads the drill-hole logs of White et al. (1964, USGS PP 458-B, Table 3) from the
# hand-maintained table data/raw/historical/white1964_table3_gs_logs.csv into
# Well_Lithology (GS-6 first; the table is ready for the other GS holes).
#
#  * Intervals are exactly the logged ones; nothing is extended to total depth.
#  * Replaces rows tagged 'NBMG TOPS' for the same well: NBMG's TOPS string is a summary of
#    this same log, so the two would double-count. Other sources' rows are never touched.
#  * Registers the source in Data_Sources. Idempotent.
# Run before ingest_nbmg_lithology() so the coarser NBMG version is not loaded first.
# ============================================================
suppressPackageStartupMessages(library(DBI))
source("database/schema/17_formation_unit_schema.R")

ingest_white1964_gs_logs <- function(con, csv = "data/raw/historical/white1964_table3_gs_logs.csv") {
  message("---- White et al. (1964) Table 3 drill-hole logs ----")
  if (!file.exists(csv)) { message("  -> ", csv, " not found; skipped"); return(invisible(NULL)) }
  migrate_well_lithology_formation_unit(con)
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, citation, url, notes) VALUES (?,?,?,?)",
            params = list("White et al. (1964) USGS PP 458-B, Table 3 drill-hole logs",
                          "White, D.E., Thompson, G.A., and Sandberg, C.H., 1964, Rocks, structure, and geology of Steamboat Springs thermal area, Washoe County, Nevada: USGS Professional Paper 458-B, Table 3 (pp. B9-B18).",
                          NA_character_, "Intervals read from the printed log pages and entered by hand in data/raw/historical/white1964_table3_gs_logs.csv."))
  x <- utils::read.csv(csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  n_ins <- 0L; n_del <- 0L
  for (w in unique(x$well_name)) {
    id <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(w))$well_id
    if (length(id) != 1) { warning("[white1964] '", w, "' matched ", length(id), " Wells rows; skipped"); next }
    d <- x[x$well_name == w, ]
    n_del <- n_del + dbExecute(con, "DELETE FROM Well_Lithology WHERE well_id = ? AND notes LIKE 'NBMG TOPS%'", params = list(id))
    for (k in seq_len(nrow(d))) {
      have <- dbGetQuery(con, "SELECT 1 FROM Well_Lithology WHERE well_id = ? AND depth_from_ft = ? AND depth_to_ft = ? AND notes LIKE 'White et al. (1964)%'",
                         params = list(id, d$depth_from_ft[k], d$depth_to_ft[k]))
      if (nrow(have)) next
      note <- paste0("White et al. (1964) USGS PP 458-B Table 3, p. ", d$page[k], if (!is.na(d$notes[k])) paste0("; ", d$notes[k]) else "")
      dbExecute(con, "INSERT INTO Well_Lithology (well_id, depth_from_ft, depth_to_ft, description, units, notes, formation_unit, formation_unit_basis) VALUES (?,?,?,?, 'ft', ?, ?, ?)",
                params = list(id, d$depth_from_ft[k], d$depth_to_ft[k], d$description[k], note, d$formation_unit[k], d$formation_unit_basis[k]))
      n_ins <- n_ins + 1L
    }
  }
  message(sprintf("  -> %d interval(s) inserted, %d NBMG TOPS interval(s) replaced", n_ins, n_del))
  invisible(c(inserted = n_ins, replaced = n_del))
}
