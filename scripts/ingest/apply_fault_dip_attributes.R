# ------------------------------------------------------------
# apply_fault_dip_attributes.R
#
# Fills dip direction, stated dip angle, its basis and its source on Fault_Traces from the
# hand-maintained table data/raw/arcgis/faults/fault_dip_attributes.csv. The digitized
# Dhakal fault layer carries no dip, so every value here comes from the literature and says
# so: dip_assignment = 'zone-level' means the value describes a fault zone, not a
# measurement on that individual trace. The CSV is the source of truth for these columns.
# Idempotent: a second run changes nothing.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

apply_fault_dip_attributes <- function(con, csv = "data/raw/arcgis/faults/fault_dip_attributes.csv") {
  if (!file.exists(csv)) { message("[fault_dip] ", csv, " not found; skipped"); return(invisible(NULL)) }
  if (!"Fault_Traces" %in% dbListTables(con)) { message("[fault_dip] Fault_Traces does not exist yet; skipped"); return(invisible(NULL)) }
  need <- c("dip_angle_deg", "dip_angle_basis", "dip_assignment", "dip_source", "dip_note")
  have <- dbListFields(con, "Fault_Traces")
  if (!all(need %in% have)) { warning("[fault_dip] dip columns missing; run database/schema/11_fault_traces_schema.R first"); return(invisible(NULL)) }
  x <- utils::read.csv(csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  changed <- 0; missing <- character()
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    cur <- dbGetQuery(con, "SELECT fault_id, dip_direction, dip_angle_deg, dip_angle_basis, dip_assignment, dip_source, dip_note FROM Fault_Traces WHERE fault_name = ?", params = list(r$fault_name))
    if (nrow(cur) == 0) { missing <- c(missing, r$fault_name); next }
    same <- function(a, b) (is.na(a) && is.na(b)) || (!is.na(a) && !is.na(b) && a == b)
    for (k in seq_len(nrow(cur))) {
      if (same(cur$dip_direction[k], r$dip_direction) && same(cur$dip_angle_deg[k], r$dip_angle_deg) && same(cur$dip_angle_basis[k], r$dip_angle_basis) &&
          same(cur$dip_assignment[k], r$dip_assignment) && same(cur$dip_source[k], r$dip_source) && same(cur$dip_note[k], r$dip_note)) next
      dbExecute(con, "UPDATE Fault_Traces SET dip_direction = ?, dip_angle_deg = ?, dip_angle_basis = ?, dip_assignment = ?, dip_source = ?, dip_note = ? WHERE fault_id = ?",
                params = list(r$dip_direction, r$dip_angle_deg, r$dip_angle_basis, r$dip_assignment, r$dip_source, r$dip_note, cur$fault_id[k]))
      changed <- changed + 1
    }
  }
  if (length(missing)) warning("[fault_dip] no Fault_Traces row named: ", paste(missing, collapse = "; "))
  message(sprintf("[fault_dip] %d fault trace(s) updated from %s", changed, basename(csv)))
  invisible(changed)
}
