# ============================================================
# resolve_nbmg_held.R
#
# Applies the hand-made decisions in data/raw/nbmg/nbmg_held_resolutions.csv to the
# NBMG staging rows ingest_nbmg_compilation() holds as 'held_probable'.
#
# A row is held when it matches an existing well (exact API or name) but the NBMG
# coordinate is more than 200 m from the stored one. Every decision here confirms the
# identity (exact API, or exact name + depth + operator + date) and keeps the stored
# coordinate; the NBMG point is recorded as a discrepancy (and rejected where the DEM or
# the distance shows it is wrong). Effects:
#   * staging row: disposition 'filled_existing', loaded_well_id = matched well,
#     review_flag 'RESOLVED_<decision>'
#   * Wells: fill-only for api_number, ndom_permit, dates, total_depth, field_name;
#     coordinates never touched; a note records the decision and the distance
# Idempotent (only rows still 'held_probable' are processed).
# Report: data/derived/nbmg_held_resolution_report.csv
# ============================================================
suppressPackageStartupMessages(library(DBI))
source("scripts/ingest/ingest_nbmg_compilation.R")   # .parse_nbmg_date, .num_commas

resolve_nbmg_held <- function(con, csv = "data/raw/nbmg/nbmg_held_resolutions.csv", report = "data/derived/nbmg_held_resolution_report.csv") {
  message("---- Resolving held NBMG rows ----")
  if (!file.exists(csv)) { message("  -> ", csv, " not found; skipped"); return(invisible(NULL)) }
  x <- utils::read.csv(csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  rep <- list(); n_done <- 0L; n_fill <- 0L
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    s <- dbGetQuery(con, "SELECT * FROM NBMG_Compilation_Records WHERE src_api = ? AND src_well = ? AND disposition = 'held_probable'", params = list(r$src_api, r$src_well))
    if (nrow(s) != 1) next
    wid <- s$matched_well_id
    if (is.na(wid)) { warning("[resolve_nbmg_held] ", r$src_well, ": no candidate well id; skipped"); next }
    ex <- dbGetQuery(con, "SELECT * FROM Wells WHERE well_id = ?", params = list(wid))
    upd <- function(col, val) {
      if (!is.na(val) && is.na(ex[[col]][1])) { dbExecute(con, sprintf("UPDATE Wells SET %s = ? WHERE well_id = ?", col), params = list(val, wid)); n_fill <<- n_fill + 1L }
    }
    taken <- dbGetQuery(con, "SELECT 1 FROM Wells WHERE api_number = ? AND well_id <> ?", params = list(s$src_api, wid))
    if (nrow(taken) == 0) upd("api_number", s$src_api)
    if (grepl("^[0-9]{4}$", ifelse(is.na(s$src_permit), "", s$src_permit))) upd("ndom_permit", s$src_permit)
    upd("spud_date", .parse_nbmg_date(s$src_spud_date)); upd("completion_date", .parse_nbmg_date(s$src_compl_date))
    upd("total_depth", .num_commas(s$src_td)); upd("field_name", "Steamboat Springs")
    note <- sprintf("[NBMG 2019 compilation, API %s (%s): confirmed same well (%s); its coordinate is %s m from the stored one and was not used (%s: %s).]",
                    s$src_api, s$src_well, r$decision, round(s$distance_m), r$nbmg_point_assessment, r$evidence)
    cur <- ex$notes[1]
    if (is.na(cur) || !grepl(paste0("NBMG 2019 compilation, API ", s$src_api), cur, fixed = TRUE))
      dbExecute(con, "UPDATE Wells SET notes = ? WHERE well_id = ?", params = list(if (is.na(cur) || !nzchar(cur)) note else paste(cur, note), wid))
    dbExecute(con, "UPDATE NBMG_Compilation_Records SET disposition = 'filled_existing', loaded_well_id = ?, review_flag = ? WHERE record_id = ?",
              params = list(wid, paste0("RESOLVED_", r$decision), s$record_id))
    n_done <- n_done + 1L
    rep[[length(rep) + 1]] <- data.frame(record_id = s$record_id, src_api = s$src_api, src_well = s$src_well, well_id = wid, well_name = ex$well_name[1],
                                          distance_m = round(s$distance_m), nbmg_point_assessment = r$nbmg_point_assessment, decision = r$decision, stringsAsFactors = FALSE)
  }
  if (length(rep)) { dir.create(dirname(report), showWarnings = FALSE, recursive = TRUE); utils::write.csv(do.call(rbind, rep), report, row.names = FALSE) }
  left <- dbGetQuery(con, "SELECT COUNT(*) n FROM NBMG_Compilation_Records WHERE disposition = 'held_probable'")$n
  message(sprintf("  -> %d held row(s) resolved, %d fill-only field(s) set; %d still held", n_done, n_fill, left))
  invisible(n_done)
}
