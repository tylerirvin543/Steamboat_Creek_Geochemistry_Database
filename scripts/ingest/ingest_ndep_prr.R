# ============================================================
# ingest_ndep_prr.R
#
# Purpose:
# Pilot ingestion of NDEP Public Records Request (PRR) documents --
# distinct from the open-data NDEP Water Quality Portal handled by
# ingest_ndep.R. Parses PDF lab-analytical-report pages (currently
# the SGS-format layout, via parse_ndep_prr_lab_report()) and stages
# results in Staging_NDEP_WQ for human review/promotion, rather than
# writing directly to Lab_Analyses/Samples -- PDF text extraction is
# failure-prone (see the wrapped-parameter-name caveat in
# parse_ndep_prr_pdf.R), so nothing here is treated as final.
#
# Scope (2026-09-05, pilot): only the SGS lab-report layout, found in
# "Steamboat 2024 Semi-annual Digital Submittal (UNEV2007204).pdf".
# Several of the other 9 PRR documents are fully scanned (no text
# layer) and would need OCR -- NOT attempted here (see the
# `pdf_text_char_count` check below, which skips + warns on those
# rather than erroring the whole ingest run).
#
# Folder convention:
#   data/raw/ndep/PRR/PPR_<date>/*.pdf  -- one dated folder per
#   records request, never overwritten; new requests get a new
#   sibling folder.
#
# Idempotency:
#   Documents_Processed tracks (filename, content hash). Re-running
#   after dropping a REVISED version of the same-named PDF re-parses
#   it (hash differs); an unchanged file is skipped.
# ============================================================

library(DBI)
library(dplyr)
library(fs)
library(digest)

source("scripts/ingest/helpers/parse_ndep_prr_pdf.R")
source("scripts/ingest/helpers/parse_wetlab_appendix_d_pdf.R")

# 2026-09-30: WETLAB-format documents (TFT Compliance Reports' Appendix
# D) use a different Customer-Sample-ID-per-composite naming scheme than
# a fixed station list -- this maps the real composite names seen so far
# to a stable, canonical station name so repeat samples at the same
# physical injection point (different dates, different composite
# numbers) resolve to the SAME Location once promoted, rather than a new
# one per date. Falls back to the raw customer_sample_id (kept distinct/
# unresolved) for any pattern not yet seen, rather than guessing.
.normalize_wetlab_station_name <- function(customer_sample_id) {
  dplyr::case_when(
    stringr::str_detect(customer_sample_id, "G1 Injection") ~ "Galena 1 Injection Composite (TFT)",
    stringr::str_detect(customer_sample_id, "G2 Injection") ~ "Galena 2 Injection Composite (TFT)",
    stringr::str_detect(customer_sample_id, "G3 Injection") ~ "Galena 3 Injection Composite (TFT)",
    stringr::str_detect(customer_sample_id, "SBHR") ~ "SBHR Injection Composite (TFT)",
    stringr::str_detect(customer_sample_id, "SB2|SB3") ~ "SB2/3 Injection Composite (TFT)",
    TRUE ~ customer_sample_id
  )
}

ingest_ndep_prr <- function(con, base_dir = "data/raw/ndep/PRR", force_reprocess = FALSE, force_reprocess_pattern = NULL) {

  # 2026-09-30: force_reprocess = TRUE re-parses files even if their
  # (file_name, file_hash) was already marked processed -- needed after
  # an extraction-logic change (e.g. the new WETLAB parser), since the
  # PDFs themselves haven't changed so their hash hasn't either. Mirrors
  # ingest_well_logs.R's own force_reprocess convention.
  if (isTRUE(force_reprocess) && !is.null(force_reprocess_pattern)) {
    .fr_docs <- dbGetQuery(con, "SELECT file_name FROM Documents_Processed WHERE source_dir LIKE ?", params = list(paste0(base_dir, "%")))
    .fr_to_clear <- .fr_docs$file_name[grepl(force_reprocess_pattern, .fr_docs$file_name)]
    for (.fr_fn in .fr_to_clear) dbExecute(con, "DELETE FROM Documents_Processed WHERE file_name = ?", params = list(.fr_fn))
    message("[NDEP PRR] force_reprocess = TRUE: cleared ", length(.fr_to_clear), " Documents_Processed row(s) matching '", force_reprocess_pattern, "'.")
  } else if (isTRUE(force_reprocess)) {
    n_deleted_docs <- dbExecute(con, "DELETE FROM Documents_Processed WHERE source_dir LIKE ?",
                                 params = list(paste0(base_dir, "%")))
    message("[NDEP PRR] force_reprocess = TRUE: cleared ", n_deleted_docs,
            " Documents_Processed row(s) for this directory.")
  }

  message("---- Starting NDEP PRR (pilot) ingest ----")

  if (!dir_exists(base_dir)) {
    message("[NDEP PRR] Directory not found — skipping.")
    return(invisible(NULL))
  }

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Documents_Processed (
      file_name TEXT,
      file_hash TEXT,
      source_dir TEXT,
      processed_at TEXT,
      rows_staged INTEGER,
      PRIMARY KEY (file_name, file_hash)
    )
  ")

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, citation, notes)
    VALUES (
      'Nevada DEP (Public Records Request)',
      'Nevada Division of Environmental Protection -- Public Records Request',
      'Distinct from the open-data NDEP Water Quality Portal source -- see ingest_ndep.R'
    )
  ")

  pdf_files <- dir_ls(base_dir, recurse = TRUE, regexp = "\\.pdf$", type = "file")

  if (length(pdf_files) == 0) {
    message("[NDEP PRR] No PDF files found — skipping.")
    return(invisible(NULL))
  }

  processed <- dbGetQuery(con, "SELECT file_name, file_hash FROM Documents_Processed")
  total_staged <- 0L

  for (f in pdf_files) {

    file_hash <- digest(f, algo = "sha256", file = TRUE)
    already_done <- any(processed$file_name == basename(f) & processed$file_hash == file_hash)

    if (already_done) {
      message("[NDEP PRR] Skipping unchanged file: ", basename(f))
      next
    }

    message("\n[NDEP PRR] Processing: ", basename(f))

    is_wetlab <- tryCatch(is_wetlab_format(f), error = function(e) FALSE)

    char_count <- sum(nchar(pdftools::pdf_text(f)))
    if (char_count == 0) {
      message("  → No extractable text (scanned/image-only PDF) — OCR required, not attempted. Skipping.")
      dbAppendTable(con, "Documents_Processed", data.frame(
        file_name = basename(f), file_hash = file_hash, source_dir = dirname(f),
        processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
        rows_staged = 0L
      ))
      next
    }

    if (is_wetlab) {
      parsed <- tryCatch(
        parse_wetlab_lab_report(f),
        error = function(e) {
          warning("  -> WETLAB parse failed for ", basename(f), ": ", conditionMessage(e), call. = FALSE)
          data.frame()
        }
      )
      if (nrow(parsed) == 0) {
        message("  -> WETLAB format detected, but no Appendix D rows parsed.")
        dbAppendTable(con, "Documents_Processed", data.frame(
          file_name = basename(f), file_hash = file_hash, source_dir = dirname(f),
          processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
          rows_staged = 0L
        ))
        next
      }
      staged <- parsed |>
        transmute(
          station_name = .normalize_wetlab_station_name(customer_sample_id),
          latitude = NA_real_,
          longitude = NA_real_,
          sample_date = collect_datetime,
          analyte,
          value,
          units,
          method,
          detection_limit = NA_real_,
          raw_source_file = source_file
        )
    } else {
    parsed <- tryCatch(
      parse_ndep_prr_lab_report(f),
      error = function(e) {
        warning("  → Parse failed for ", basename(f), ": ", conditionMessage(e), call. = FALSE)
        data.frame()
      }
    )

    if (nrow(parsed) == 0) {
      message("  → No lab-report rows parsed (may not be the SGS layout this pilot supports).")
      dbAppendTable(con, "Documents_Processed", data.frame(
        file_name = basename(f), file_hash = file_hash, source_dir = dirname(f),
        processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
        rows_staged = 0L
      ))
      next
    }

    staged <- parsed |>
      transmute(
        station_name = client_sample_id,
        latitude = NA_real_,
        longitude = NA_real_,
        sample_date = date_sampled,
        analyte = parameter,
        value,
        units,
        method,
        detection_limit = pql,
        raw_source_file = source_file
      )

    }

    dbAppendTable(con, "Staging_NDEP_WQ", staged)
    dbAppendTable(con, "Documents_Processed", data.frame(
      file_name = basename(f), file_hash = file_hash, source_dir = dirname(f),
      processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      rows_staged = nrow(staged)
    ))

    message("  → Staged ", nrow(staged), " result row(s) to Staging_NDEP_WQ (NOT yet in core tables -- ",
            "review Staging_NDEP_WQ and promote manually).")
    total_staged <- total_staged + nrow(staged)
  }

  dbAppendTable(
    con, "Ingest_Run_Log",
    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      data_source = "NDEP_PRR", script_name = "ingest_ndep_prr.R",
      samples_inserted = 0, measurements_inserted = total_staged,
      notes = paste("NDEP PRR pilot: staged", total_staged, "row(s) to Staging_NDEP_WQ (unpromoted)")
    )
  )

  message("\n✅ NDEP PRR ingest complete — ", total_staged, " row(s) staged (review before promoting).")
  invisible(total_staged)
}
