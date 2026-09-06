# ============================================================
# ingest_well_logs.R
#
# Purpose:
# Reusable ingestion of NDWR "WELL DRILLER'S REPORT" PDF well logs
# (currently data/raw/ndwr/Ormat_well_logs/, but designed to run
# against any future directory of the same document type -- pass a
# different `log_dir` and this all still works).
#
# For each PDF:
#   1. Try parse_well_log_pdf() (scripts/ingest/helpers/parse_well_log_pdf.R).
#      As of 2026-09-05 (session 10) this now falls back to OCR
#      (tesseract, via a sandbox workaround -- see that file's
#      docstring) when a PDF has no extractable text layer, which is
#      most NDWR well-log scans (11 of 12 files on hand). OCR quality
#      varies a lot across scans; see parse_well_log_pdf.R for the
#      specific, ground-truthed caveats (some digits get misread even
#      when the right field is located).
#   2. Regardless of (1), also try a free, no-OCR-needed fallback: the
#      filename is assumed to be the well's NDWR log number, which is
#      cross-referenced against the already-ingested NDWR
#      WellLogQuery basin tables (TM/PV htm exports under
#      data/raw/ndwr/) for owner name, PLSS location, coordinates,
#      and completion date. This is how most of these 12 files get
#      *any* location/owner info despite having no OCR-able content.
#   3. Every file (matched or not) gets a Well_Log_Documents row --
#      this is a staging/tracking table, not a promise that the well
#      is identified. well_id stays NULL until a human confirms which
#      Wells row (if any) a given log number corresponds to.
#
# Promotion to Wells/Water_Level_Observations happens separately, via
# promote_well_log_documents() below, driven by a human-maintained
# mapping file (data/raw/ndwr/well_log_document_map.csv: log_number,
# well_name, notes) -- mirrors this project's established pattern of
# never auto-guessing an identity match when the evidence is
# ambiguous (see promote_staged_ndep.R for the same philosophy applied
# to NDEP PRR chemistry).
#
# Idempotency: Well_Log_Documents is keyed on (file_path, file_hash) --
# an unchanged file is skipped on re-run; a replaced/revised PDF (new
# hash) is reprocessed. promote_well_log_documents() only ever fills
# currently-NULL Wells columns / inserts a Water_Level_Observations
# row if one doesn't already exist for that well+timestamp+method.
# ============================================================

library(DBI)
library(dplyr)
library(rvest)
library(fs)
library(digest)

source("scripts/ingest/helpers/parse_well_log_pdf.R")

#' Read one NDWR WellLogQuery basin export (the same htm files parsed
#' elsewhere in this project) into a data.frame with real column names.
.read_ndwr_welllog_table <- function(htm_path) {
  if (!file_exists(htm_path)) return(NULL)
  html <- read_html(htm_path)
  tbl <- html_table(html, header = FALSE, fill = TRUE)[[1]]
  hdr_row <- which(apply(tbl, 1, function(r) any(grepl("^Owner$", trimws(r)))))
  if (length(hdr_row) == 0) return(NULL)
  colnames(tbl) <- as.character(unlist(tbl[hdr_row[1], ]))
  tbl[-(1:hdr_row[1]), ]
}

ingest_well_logs <- function(
    con,
    log_dir = "data/raw/ndwr/Ormat_well_logs",
    ndwr_htm_paths = c(
      "data/raw/ndwr/TM_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm",
      "data/raw/ndwr/PV_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm"
    ),
    force_reprocess = FALSE) {

  message("---- Ingesting well-log PDFs from ", log_dir, " ----")

  if (!dir_exists(log_dir)) {
    message("[ingest_well_logs] Directory not found -- skipping.")
    return(invisible(NULL))
  }

  # force_reprocess = TRUE re-parses files even if their (file_path,
  # file_hash) was already staged -- needed after an extraction-logic
  # change (e.g. the OCR support added this session), since the PDFs
  # themselves have not changed so their hash has not either. Existing
  # rows for files in log_dir are deleted first (a well_id link, if
  # ever set by promote_well_log_documents(), would be lost and need
  # re-promoting -- fine here since nothing has been promoted yet).
  if (isTRUE(force_reprocess)) {
    n_deleted <- dbExecute(con, "DELETE FROM Well_Log_Documents WHERE file_path LIKE ?",
                            params = list(paste0(log_dir, "%")))
    message("[ingest_well_logs] force_reprocess = TRUE: deleted ", n_deleted, " existing staged row(s) for this directory.")
  }

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES ('NDWR Well Driller''s Reports', 'Nevada Division of Water Resources well-log PDFs (Form 4013)')
  ")

  pdf_files <- dir_ls(log_dir, regexp = "\\.pdf$", type = "file")
  if (length(pdf_files) == 0) {
    message("[ingest_well_logs] No PDF files found -- skipping.")
    return(invisible(NULL))
  }

  ndwr_tables <- lapply(ndwr_htm_paths, .read_ndwr_welllog_table)
  ndwr_tables <- ndwr_tables[!sapply(ndwr_tables, is.null)]

  existing <- dbGetQuery(con, "SELECT file_path, file_hash FROM Well_Log_Documents")

  n_processed <- 0L
  n_skipped <- 0L
  n_text_layer <- 0L
  n_crossref <- 0L

  for (f in pdf_files) {
    file_hash <- digest(f, algo = "sha256", file = TRUE)

    if (any(existing$file_path == f & existing$file_hash == file_hash)) {
      n_skipped <- n_skipped + 1L
      next
    }

    log_number <- tools::file_path_sans_ext(basename(f))
    message("  Processing ", basename(f), " (log #", log_number, ")")

    parsed <- tryCatch(parse_well_log_pdf(f), error = function(e) {
      warning("  -> parse_well_log_pdf failed for ", basename(f), ": ", conditionMessage(e))
      NULL
    })

    has_text_layer <- !is.null(parsed)
    if (has_text_layer) n_text_layer <- n_text_layer + 1L

    # Cross-reference by log number regardless of text-layer status --
    # even a machine-readable PDF's own extracted lat/lon might be OCR
    # noise (see parse_well_log_pdf.R's sanity flag), so this is a
    # useful independent check either way.
    crossref <- NULL
    for (tbl in ndwr_tables) {
      hit <- tbl[trimws(tbl$Log) == log_number, ]
      if (nrow(hit) > 0) { crossref <- hit[1, ]; break }
    }
    if (!is.null(crossref)) n_crossref <- n_crossref + 1L

    # Prefer parsed values; fall back to the cross-reference; sanity-
    # check parsed lat/lon against Nevada and fall back if insane.
    well_name_parsed <- if (has_text_layer && !is.na(parsed$well_name)) parsed$well_name else NA_character_
    latitude <- if (has_text_layer) parsed$latitude else NA_real_
    longitude <- if (has_text_layer) parsed$longitude else NA_real_

    lat_insane <- !is.na(latitude) && (latitude < 34 || latitude > 43)
    lon_insane <- !is.na(longitude) && (longitude < -121 || longitude > -113)

    match_method <- if (has_text_layer && !lat_insane && !lon_insane && !is.na(latitude)) "parsed_text" else NA_character_

    if ((is.na(latitude) || lat_insane || is.na(longitude) || lon_insane) && !is.null(crossref)) {
      latitude <- suppressWarnings(as.numeric(crossref$latitude))
      longitude <- suppressWarnings(as.numeric(crossref$Longitude))
      match_method <- "ndwr_log_number_crossref"
      if (is.na(well_name_parsed)) well_name_parsed <- paste0(trimws(crossref$Owner), " (NDWR Log ", log_number, ")")
    }

    flags <- character(0)
    if (has_text_layer) flags <- c(flags, parsed$flags[!is.na(parsed$flags)])
    if (is.null(crossref) && !has_text_layer) {
      flags <- c(flags, "no text layer AND no NDWR log-number cross-reference match -- essentially no usable data without OCR")
    }

    dbExecute(con, "
      INSERT INTO Well_Log_Documents (
        file_path, file_hash, log_number, well_id, well_name_parsed,
        has_text_layer, latitude, longitude, depth_drilled_ft, cased_depth_ft,
        static_water_level_ft, slot_from_ft, slot_to_ft, completion_date_raw,
        match_method, lithology_raw_text, flags, processed_at, notes
      ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      f, file_hash, log_number, well_name_parsed,
      as.integer(has_text_layer), latitude, longitude,
      if (has_text_layer) parsed$depth_drilled_ft else NA_real_,
      if (has_text_layer) parsed$cased_depth_ft else NA_real_,
      if (has_text_layer) parsed$static_water_level_ft else NA_real_,
      if (has_text_layer) parsed$slot_from_ft else NA_real_,
      if (has_text_layer) parsed$slot_to_ft else NA_real_,
      if (has_text_layer) parsed$completion_date_raw else NA_character_,
      match_method,
      if (has_text_layer) parsed$lithology_raw_text else NA_character_,
      if (length(flags) == 0) NA_character_ else paste(flags, collapse = " | "),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      if (!is.null(crossref)) paste0("NDWR cross-reference: owner=", trimws(crossref$Owner),
                                       ", Sec/Twn/Rng=", trimws(crossref$Sec), "/", trimws(crossref$Twn), "/", trimws(crossref$Rng),
                                       ", completed=", trimws(crossref$`Comp Date`)) else NA_character_
    ))

    n_processed <- n_processed + 1L
  }

  message("  -> Processed ", n_processed, " document(s) (", n_skipped, " unchanged, skipped); ",
          n_text_layer, " had an extractable text layer; ", n_crossref, " matched an NDWR log number cross-reference.")

  dbAppendTable(con, "Ingest_Run_Log", data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    data_source = "WELL_LOGS", script_name = "ingest_well_logs.R",
    samples_inserted = 0, measurements_inserted = n_processed,
    notes = paste0("Well-log PDFs: ", n_processed, " processed, ", n_text_layer, " with text layer, ", n_crossref, " NDWR cross-referenced")
  ))

  invisible(list(processed = n_processed, skipped = n_skipped, text_layer = n_text_layer, crossref = n_crossref))
}

#' Promote Well_Log_Documents rows to Wells/Water_Level_Observations
#' once a human has confirmed which well a log_number corresponds to.
#'
#' @param map_csv data/raw/ndwr/well_log_document_map.csv --
#'   columns: log_number, well_name, notes. well_name must already
#'   exist in Wells (register it first, e.g. via
#'   register_well_network.R/register_well_coordinates.R, if it's a
#'   Dhakal-network well) or the row is skipped with a warning.
promote_well_log_documents <- function(
    con,
    map_csv = "data/raw/ndwr/well_log_document_map.csv") {

  message("---- Promoting well-log documents to Wells ----")

  if (!fs::file_exists(map_csv)) {
    message("[promote_well_log_documents] No mapping file at ", map_csv, " -- nothing to promote.")
    return(invisible(NULL))
  }

  map <- readr::read_csv(map_csv, show_col_types = FALSE) %>%
    mutate(log_number = trimws(as.character(log_number)), well_name = trimws(well_name)) %>%
    filter(!is.na(log_number), log_number != "", !is.na(well_name), well_name != "")

  n_promoted <- 0L
  n_skipped_well <- character(0)

  for (i in seq_len(nrow(map))) {
    row <- map[i, ]

    doc <- dbGetQuery(con, "SELECT * FROM Well_Log_Documents WHERE log_number = ?", params = list(row$log_number))
    if (nrow(doc) == 0) next
    doc <- doc[1, ]

    well <- dbGetQuery(con, "SELECT well_id, top_perforation, bottom_perforation FROM Wells WHERE well_name = ?",
                        params = list(row$well_name))
    if (nrow(well) == 0) {
      n_skipped_well <- c(n_skipped_well, row$well_name)
      next
    }
    well_id <- well$well_id[1]

    if (is.na(doc$well_id)) {
      dbExecute(con, "UPDATE Well_Log_Documents SET well_id = ?, match_method = 'manual' WHERE document_id = ?",
                params = list(well_id, doc$document_id))
    }

    if (!is.na(doc$slot_from_ft) && !is.na(doc$slot_to_ft) && is.na(well$top_perforation[1])) {
      dbExecute(con, "UPDATE Wells SET top_perforation = ?, bottom_perforation = ? WHERE well_id = ?",
                params = list(doc$slot_from_ft, doc$slot_to_ft, well_id))
    }

    if (!is.na(doc$static_water_level_ft)) {
      already <- dbGetQuery(con, "
        SELECT observation_id FROM Water_Level_Observations
        WHERE well_id = ? AND method = 'driller_report'
      ", params = list(well_id))
      if (nrow(already) == 0) {
        dbExecute(con, "
          INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes)
          VALUES (?, ?, ?, 'driller_report', 'driller_report', ?)
        ", params = list(
          well_id,
          if (!is.na(doc$completion_date_raw)) doc$completion_date_raw else format(Sys.time(), "%Y-%m-%d"),
          doc$static_water_level_ft,
          paste0("Static water level at time of drilling, from NDWR well log #", doc$log_number, ". ", row$notes)
        ))
      }
    }

    n_promoted <- n_promoted + 1L
  }

  if (length(n_skipped_well) > 0) {
    warning("[promote_well_log_documents] ", length(n_skipped_well),
            " row(s) reference a well_name not found in Wells -- skipped: ",
            paste(n_skipped_well, collapse = ", "))
  }

  message("  -> Promoted ", n_promoted, " well-log document(s).")
  invisible(list(promoted = n_promoted, skipped_well = n_skipped_well))
}
