# ------------------------------------------------------------
# link_collar_logs_to_wells.R
#
# Folds a provisional "(NDWR Log N)" Wells row into the well it was judged to
# be (human-maintained data/raw/wells/collar_log_well_links.csv). Everything
# attached to the provisional well moves to the target well; target fields are
# filled only when NULL. The provisional row is then deleted; its name is kept
# as a Well_Aliases entry. Idempotent: a link whose provisional well is gone is
# skipped.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

link_collar_logs_to_wells <- function(con, csv = "data/raw/wells/collar_log_well_links.csv") {
  message("---- Linking Collar App. B logs to sampled wells ----")
  if (!file.exists(csv)) return(invisible(0L))
  l <- read.csv(csv, stringsAsFactors = FALSE); n <- 0L
  tabs <- Filter(function(t) !grepl("^vw_|^Wells$", t) && "well_id" %in% dbListFields(con, t), dbListTables(con))
  for (i in seq_len(nrow(l))) {
    prov <- dbGetQuery(con, "SELECT * FROM Wells WHERE well_name = ?", params = list(l$provisional_well_name[i]))
    tgt  <- dbGetQuery(con, "SELECT * FROM Wells WHERE well_name = ?", params = list(l$target_well_name[i]))
    if (nrow(prov) != 1 || nrow(tgt) != 1) next
    pid <- prov$well_id; tid <- tgt$well_id
    dbWithTransaction(con, {
      for (col in c("total_depth", "top_perforation", "bottom_perforation", "diameter_in", "completion_date", "well_role")) {
        if (col %in% names(prov) && is.na(tgt[[col]]) && !is.na(prov[[col]]) && !(col == "well_role" && prov[[col]] == "unknown"))
          dbExecute(con, sprintf("UPDATE Wells SET %s = ? WHERE well_id = ?", col), params = list(prov[[col]], tid))
      }
      for (t in tabs) {
        dbExecute(con, sprintf("UPDATE OR IGNORE %s SET well_id = ? WHERE well_id = ?", t), params = list(tid, pid))
        dbExecute(con, sprintf("DELETE FROM %s WHERE well_id = ?", t), params = list(pid))
      }
      dbExecute(con, "INSERT OR IGNORE INTO Well_Aliases (well_id, alias, alias_type, notes) VALUES (?, ?, 'ndwr_permit', ?)",
                params = list(tid, l$alias[i], sprintf("NDWR log %s linked (%s): %s", l$log_number[i], l$confidence[i], l$basis[i])))
      dbExecute(con, "UPDATE Wells SET notes = TRIM(COALESCE(notes,'') || ?) WHERE well_id = ?",
                params = list(sprintf(" [Collar App. B NDWR log %s linked, %s confidence; depth/screen/lithology/water level from that log.]", l$log_number[i], l$confidence[i]), tid))
      dbExecute(con, "DELETE FROM Wells WHERE well_id = ?", params = list(pid))
    })
    message("  -> ", l$provisional_well_name[i], " folded into ", l$target_well_name[i]); n <- n + 1L
  }
  invisible(n)
}
