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
#      As of 2026-09-05 (session 10) this falls back to OCR (tesseract,
#      via a sandbox workaround -- see that file's docstring) when a
#      PDF has no extractable text layer, which is most NDWR well-log
#      scans. OCR quality varies a lot across scans; see
#      parse_well_log_pdf.R for the specific, ground-truthed caveats
#      (some digits get misread even when the right field is located).
#      As of 2026-09-12 (session 24) it also extracts Section/Township/
#      Range (with a BLM-PLSS-service lat/lon fallback), type of work,
#      proposed use, and hole/casing diameter.
#   2. Regardless of (1), also try a free, no-OCR-needed fallback: the
#      filename is assumed to be the well's NDWR log number, which is
#      cross-referenced against the already-ingested NDWR
#      WellLogQuery basin tables (TM/PV htm exports under
#      data/raw/ndwr/) for owner name, PLSS location, coordinates,
#      and completion date.
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
# hash) is reprocessed.
#
# 2026-09-12 (session 24) additions, prompted by a much larger batch
# of new files (64 log numbers, many with a second "(2)"
# reformatted/streamlined scan -- confirmed by direct inspection that
# BOTH the original and "(2)" scans are image-only, no text layer, so
# both need OCR the same way):
#   - A log number's primary file and its "(2)" alternate (if present)
#     are tracked on the SAME Well_Log_Documents row (alt_file_path/
#     alt_file_hash columns), not as two separate documents. Both are
#     OCR'd; a field missing from the primary source is filled from the
#     alternate.
#   - Exact-duplicate re-downloads (e.g. "147778 (1).pdf" alongside an
#     already-ingested "147778.pdf" with identical content) are
#     detected by content hash ACROSS all existing documents (not just
#     the same file_path) and skipped without wasting OCR time.
#   - New fields (Section/Township/Range, work_type, proposed_use,
#     hole/casing diameter) are stored on Well_Log_Documents and, when
#     promoted, also written to a new Well_Work_Events row (one row
#     per document) so a well's status history over time -- new,
#     deepened, abandoned, etc. -- is a queryable time series, not a
#     single overwritten snapshot.
#   - promote_well_log_documents() and register_provisional_well_logs()
#     both had a real, pre-existing bug: their "does a water-level
#     observation already exist for this well" check only matched on
#     (well_id, method), not (well_id, method, timestamp) -- meaning
#     only the FIRST driller's report ever ingested for a given well
#     had its static water level stored; every later report (e.g. a
#     deepening or re-permit log with a different date) was silently
#     dropped. Fixed here by including timestamp in the check, matching
#     the table's own UNIQUE(well_id, timestamp, method) constraint.
#   - Well_Lithology (schema existed, nothing had ever written to it)
#     now gets populated from each document's best-effort
#     lithology_intervals attribute, tagged
#     confidence = 'ocr_heuristic_unvalidated' -- still not blindly
#     trusted, but now visible/joinable instead of stranded.
# ============================================================

library(DBI)
library(dplyr)
library(rvest)
library(fs)
library(digest)

source("scripts/ingest/helpers/parse_well_log_pdf.R")

#' Best-effort parse of a driller's-report completion date into a clean
#' YYYY-MM-DD, or NA if it isn't parseable. Used to decide the timestamp
#' for the Water_Level_Observations row a well log's static water level
#' gets promoted into.
#'
#' 2026-09-05 (session 11) bug fix: both promote_well_log_documents() and
#' register_provisional_well_logs() previously stored *whatever*
#' completion_date_raw held -- including unparseable OCR noise like
#' "OF en" or "92 2018" -- directly as the observation timestamp, and
#' fell back to `Sys.time()` (today's date) when it was NA. Both are
#' wrong: an unparseable or missing historical date should not silently
#' become garbage text or today's date in a real observation table --
#' found by inspecting the data-availability chart (scripts/analysis/
#' data_availability.R), which showed an implausible "most recent water
#' level observation: today" data point traced back to this.
.safe_completion_date <- function(raw) {
  if (is.na(raw) || trimws(raw) == "") return(NA_character_)
  for (fmt in c("%Y-%m-%d", "%m/%d/%Y", "%B %d, %Y", "%b %d, %Y", "%b. %d, %Y")) {
    d <- tryCatch(as.Date(trimws(raw), format = fmt), error = function(e) NA)
    if (!is.na(d)) return(as.character(d))
  }
  # last resort: a bare 4-digit year somewhere in the text (e.g. OCR
  # noise "92 2018" -- keep only the year, dated to Jan 1 as a clearly
  # approximate placeholder, never "today").
  yr <- regmatches(raw, regexpr("(19|20)\\d{2}", raw))
  if (length(yr) == 1 && nzchar(yr)) return(paste0(yr, "-01-01"))
  NA_character_
}

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

#' Group a directory's PDFs by NDWR log number, pairing each primary
#' scan with its "(2)" reformatted alternate (if any) and flagging
#' any other numbered duplicate (e.g. " (1)") as a probable re-download
#' to be content-hash-deduplicated rather than treated as a distinct
#' alternate source.
.group_well_log_files <- function(pdf_files) {
  base <- basename(pdf_files)
  no_ext <- tools::file_path_sans_ext(base)
  # "(2)" (optionally preceded by a space) = the reformatted alternate.
  is_alt <- grepl("\\(2\\)$", no_ext)
  # Any other "(<n>)" suffix (typically " (1)") = an accidental
  # duplicate re-download of the same log, not a distinct source.
  is_dup_suffix <- grepl("\\([0-9]+\\)$", no_ext) & !is_alt
  log_number <- gsub("\\s*\\([0-9]+\\)$", "", no_ext)

  data.frame(
    file = pdf_files, log_number = log_number,
    is_alt = is_alt, is_dup_suffix = is_dup_suffix,
    stringsAsFactors = FALSE
  )
}

ingest_well_logs <- function(
    con,
    log_dir = "data/raw/ndwr/Ormat_well_logs",
    ndwr_htm_paths = c(
      "data/raw/ndwr/TM_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm",
      "data/raw/ndwr/PV_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm"
    ),
    force_reprocess = FALSE,
    source_batch = NA_character_) {

  message("---- Ingesting well-log PDFs from ", log_dir, " ----")

  if (!dir_exists(log_dir)) {
    message("[ingest_well_logs] Directory not found -- skipping.")
    return(invisible(NULL))
  }

  # force_reprocess = TRUE re-parses files even if their (file_path,
  # file_hash) was already staged -- needed after an extraction-logic
  # change, since the PDFs themselves have not changed so their hash
  # has not either. Existing rows for files in log_dir are deleted
  # first (a well_id link, if ever set by promote_well_log_documents(),
  # would be lost and need re-promoting).
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

  grouped <- .group_well_log_files(pdf_files)
  # One row per real log number: primary file (prefer a non-"(2)",
  # non-duplicate-suffix file; else the "(2)" alone if that's all there
  # is) + its alt "(2)" file, if present. Any extra " (1)"-style
  # duplicate-suffix files are handled separately below via content-hash
  # dedup, not treated as their own log entry.
  log_numbers <- unique(grouped$log_number)

  ndwr_tables <- lapply(ndwr_htm_paths, .read_ndwr_welllog_table)
  ndwr_tables <- ndwr_tables[!sapply(ndwr_tables, is.null)]

  existing <- dbGetQuery(con, "SELECT document_id, file_path, file_hash, alt_file_hash FROM Well_Log_Documents")
  # All known content hashes (primary + alt), for cross-filename
  # duplicate-content detection -- catches "147778 (1).pdf" style
  # re-downloads even though their filename differs from anything
  # already ingested.
  known_hashes <- na.omit(c(existing$file_hash, existing$alt_file_hash))

  n_processed <- 0L
  n_skipped <- 0L
  n_dup_content <- 0L
  n_text_layer <- 0L
  n_crossref <- 0L
  n_lithology <- 0L

  n_logs <- length(log_numbers)
  message("[ingest_well_logs] Processing ", n_logs, " log number(s) (", length(pdf_files),
          " file(s) total) -- OCR on scanned files can take a while per file.")
  .pb <- utils::txtProgressBar(min = 0, max = n_logs, style = 3, width = 50)

  for (.i in seq_along(log_numbers)) {
    log_number <- log_numbers[.i]
    rows <- grouped[grouped$log_number == log_number, ]

    primary_candidates <- rows$file[!rows$is_alt]
    alt_candidates <- rows$file[rows$is_alt]
    primary_file <- if (length(primary_candidates) > 0) primary_candidates[1] else if (length(alt_candidates) > 0) alt_candidates[1] else NA
    alt_file <- if (length(alt_candidates) > 0) alt_candidates[1] else NA
    if (identical(primary_file, alt_file)) alt_file <- NA
    # Any remaining files for this log number (extra primary
    # candidates beyond the first, or a second alt) are treated as
    # probable duplicate re-downloads -- checked via content hash below
    # rather than assumed identical by filename alone.
    other_files <- setdiff(rows$file, c(primary_file, alt_file))

    if (is.na(primary_file)) { utils::setTxtProgressBar(.pb, .i); next }

    primary_hash <- digest(primary_file, algo = "sha256", file = TRUE)

    already_row <- existing[existing$file_path == primary_file & existing$file_hash == primary_hash, ]
    if (nrow(already_row) > 0) {
      n_skipped <- n_skipped + 1L
      utils::setTxtProgressBar(.pb, .i)
      next
    }

    if (primary_hash %in% known_hashes) {
      # Content identical to an already-ingested document under a
      # different filename -- record a lightweight duplicate note, do
      # NOT re-run OCR.
      dbExecute(con, "
        INSERT INTO Well_Log_Documents (
          file_path, file_hash, log_number, well_id, has_text_layer,
          match_method, notes, processed_at, source_batch
        ) VALUES (?, ?, ?, NULL, 0, 'duplicate_content_skipped', ?, ?, ?)
      ", params = list(
        primary_file, primary_hash, log_number,
        paste0("Duplicate content of an already-ingested file (same SHA-256 hash) -- skipped without re-running OCR."),
        format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"), source_batch
      ))
      n_dup_content <- n_dup_content + 1L
      utils::setTxtProgressBar(.pb, .i)
      next
    }

    .file_start_time <- Sys.time()
    message("  Processing log #", log_number, " (", basename(primary_file),
            if (!is.na(alt_file)) paste0(" + alt ", basename(alt_file)) else "", ")")

    parsed <- tryCatch(parse_well_log_pdf(primary_file), error = function(e) {
      warning("  -> parse_well_log_pdf failed for ", basename(primary_file), ": ", conditionMessage(e))
      NULL
    })
    has_text_layer <- !is.null(parsed)
    if (has_text_layer) n_text_layer <- n_text_layer + 1L

    alt_hash <- NA_character_
    alt_has_text_layer <- FALSE
    alt_parsed <- NULL
    if (!is.na(alt_file)) {
      alt_hash <- digest(alt_file, algo = "sha256", file = TRUE)
      if (alt_hash %in% known_hashes && !(alt_hash %in% c(primary_hash))) {
        # The "(2)" alternate itself duplicates content already seen
        # elsewhere (rare, but possible) -- keep the primary's parse,
        # skip re-OCR'ing the alt.
        alt_hash <- NA_character_
      } else {
        alt_parsed <- tryCatch(parse_well_log_pdf(alt_file), error = function(e) NULL)
        alt_has_text_layer <- !is.null(alt_parsed)
      }
    }

    # Merge: prefer the primary source's value; fill from the alt only
    # when the primary is NA. Any real disagreement between the two is
    # flagged, not silently resolved.
    merge_field <- function(field) {
      p <- if (has_text_layer) parsed[[field]] else NA
      a <- if (!is.null(alt_parsed)) alt_parsed[[field]] else NA
      if (!is.na(p) && !is.na(a) && !identical(p, a)) {
        list(value = p, conflict = TRUE)
      } else if (!is.na(p)) {
        list(value = p, conflict = FALSE)
      } else {
        list(value = a, conflict = FALSE)
      }
    }

    merge_flags <- character(0)
    # Lat/lon confidence ranking (lower = more trustworthy): a primary
    # scan's lower-confidence method (e.g. an unlabeled whole-text
    # guess) should NOT beat an alt scan's higher-confidence method
    # (e.g. a properly labeled field) just because it is "primary" --
    # confirmed as a real problem during testing (log 48594: primary
    # scan's unlabeled_scan guess of 40.32/-119.74 lost to the alt
    # scan's labeled_field reading of 39.394361/-119.7... which is the
    # one actually worth keeping).
    .latlon_rank <- function(method) {
      switch(as.character(method),
        labeled_field = 1, utm_conversion = 2, unlabeled_scan = 3,
        plss_section_centroid = 4, 99)
    }
    p_method <- if (has_text_layer) parsed$latlon_method else NA
    a_method <- if (!is.null(alt_parsed)) alt_parsed$latlon_method else NA
    p_rank <- if (!is.na(p_method)) .latlon_rank(p_method) else Inf
    a_rank <- if (!is.na(a_method)) .latlon_rank(a_method) else Inf
    latlon_winner <- if (is.infinite(p_rank) && is.infinite(a_rank)) NULL
                      else if (a_rank < p_rank) "alt" else "primary"

    fields_to_merge <- c(
      "well_name", "county",
      "depth_drilled_ft", "cased_depth_ft", "static_water_level_ft",
      "slot_from_ft", "slot_to_ft", "completion_date_raw",
      "section", "township_no", "township_dir", "range_no", "range_dir",
      "work_type", "proposed_use", "hole_diameter_in", "casing_diameter_in"
    )
    merged <- setNames(vector("list", length(fields_to_merge) + 3), c(fields_to_merge, "latitude", "longitude", "latlon_method"))
    for (fld in fields_to_merge) {
      m <- merge_field(fld)
      merged[[fld]] <- m$value
      if (isTRUE(m$conflict)) merge_flags <- c(merge_flags, paste0(fld, ": primary/alt scans disagree (", parsed[[fld]], " vs ", alt_parsed[[fld]], ") -- primary kept, verify manually"))
    }
    if (is.null(latlon_winner)) {
      merged$latitude <- NA_real_; merged$longitude <- NA_real_; merged$latlon_method <- NA_character_
    } else if (identical(latlon_winner, "alt")) {
      merged$latitude <- alt_parsed$latitude; merged$longitude <- alt_parsed$longitude; merged$latlon_method <- alt_parsed$latlon_method
      if (!is.na(p_method) && !identical(p_method, a_method)) {
        merge_flags <- c(merge_flags, paste0("latitude/longitude: alt scan's '", a_method, "' extraction preferred over primary scan's lower-confidence '", p_method, "' -- verify manually"))
      }
    } else {
      merged$latitude <- parsed$latitude; merged$longitude <- parsed$longitude; merged$latlon_method <- parsed$latlon_method
    }

    well_name_parsed <- if (!is.na(merged$well_name)) merged$well_name else NA_character_
    latitude <- suppressWarnings(as.numeric(merged$latitude))
    longitude <- suppressWarnings(as.numeric(merged$longitude))

    lat_insane <- !is.na(latitude) && (latitude < 34 || latitude > 43)
    lon_insane <- !is.na(longitude) && (longitude < -121 || longitude > -113)

    match_method <- if (!is.na(latitude) && !lat_insane && !lon_insane) "parsed_text" else NA_character_

    # Cross-reference by log number regardless of text-layer status --
    # even a machine-readable PDF's own extracted lat/lon might be OCR
    # noise, so this is a useful independent check either way.
    crossref <- NULL
    for (tbl in ndwr_tables) {
      hit <- tbl[trimws(tbl$Log) == log_number, ]
      if (nrow(hit) > 0) { crossref <- hit[1, ]; break }
    }
    if (!is.null(crossref)) n_crossref <- n_crossref + 1L

    if ((is.na(latitude) || lat_insane || is.na(longitude) || lon_insane) && !is.null(crossref)) {
      latitude <- suppressWarnings(as.numeric(crossref$latitude))
      longitude <- suppressWarnings(as.numeric(crossref$Longitude))
      match_method <- "ndwr_log_number_crossref"
      if (is.na(well_name_parsed)) well_name_parsed <- paste0(trimws(crossref$Owner), " (NDWR Log ", log_number, ")")
    }

    flags <- character(0)
    if (has_text_layer) flags <- c(flags, parsed$flags[!is.na(parsed$flags)])
    if (!is.null(alt_parsed)) flags <- c(flags, alt_parsed$flags[!is.na(alt_parsed$flags)])
    flags <- c(flags, merge_flags)
    if (is.null(crossref) && !has_text_layer && is.null(alt_parsed)) {
      flags <- c(flags, "no text layer AND no NDWR log-number cross-reference match -- essentially no usable data without OCR")
    }
    if (length(other_files) > 0) {
      other_hashes <- vapply(other_files, function(f) digest(f, algo = "sha256", file = TRUE), character(1))
      novel <- other_files[!(other_hashes %in% c(known_hashes, primary_hash, alt_hash))]
      if (length(novel) > 0) {
        flags <- c(flags, paste0("additional file(s) for this log number not processed as primary/alt (possible extra duplicate download, distinct content not verified): ",
                                  paste(basename(novel), collapse = ", ")))
      }
    }

    plss_latlon_method <- if (!is.na(merged$latlon_method) && identical(merged$latlon_method, "plss_section_centroid")) "plss_section_centroid" else NA_character_

    dbExecute(con, "
      INSERT INTO Well_Log_Documents (
        file_path, file_hash, alt_file_path, alt_file_hash, alt_has_text_layer,
        log_number, well_id, well_name_parsed,
        has_text_layer, latitude, longitude, depth_drilled_ft, cased_depth_ft,
        static_water_level_ft, slot_from_ft, slot_to_ft, completion_date_raw,
        section, township, range, plss_latlon_method, work_type, proposed_use,
        hole_diameter_in, casing_diameter_in,
        match_method, lithology_raw_text, flags, processed_at, notes, source_batch
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      primary_file, primary_hash, alt_file, alt_hash, as.integer(alt_has_text_layer),
      log_number, well_name_parsed,
      as.integer(has_text_layer), latitude, longitude,
      merged$depth_drilled_ft, merged$cased_depth_ft,
      merged$static_water_level_ft, merged$slot_from_ft, merged$slot_to_ft,
      merged$completion_date_raw,
      merged$section,
      if (!is.na(merged$township_no)) paste0(merged$township_no, merged$township_dir) else NA_character_,
      if (!is.na(merged$range_no)) paste0(merged$range_no, merged$range_dir) else NA_character_,
      plss_latlon_method,
      merged$work_type, merged$proposed_use,
      merged$hole_diameter_in, merged$casing_diameter_in,
      match_method,
      if (has_text_layer) parsed$lithology_raw_text else NA_character_,
      if (length(flags) == 0) NA_character_ else paste(flags, collapse = " | "),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      if (!is.null(crossref)) paste0("NDWR cross-reference: owner=", trimws(crossref$Owner),
                                       ", Sec/Twn/Rng=", trimws(crossref$Sec), "/", trimws(crossref$Twn), "/", trimws(crossref$Rng),
                                       ", completed=", trimws(crossref$`Comp Date`)) else NA_character_,
      source_batch
    ))

    doc_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    # Populate Well_Lithology from the primary parse's best-effort
    # interval extraction (never from the alt scan -- one document's
    # worth is enough, and mixing two OCR sources' guesses would only
    # add noise). Tagged unvalidated, same posture as every other
    # OCR-derived field.
    lith_df <- attr(parsed, "lithology_intervals")
    if (has_text_layer && !is.null(lith_df) && nrow(lith_df) > 0) {
      for (r in seq_len(nrow(lith_df))) {
        dbExecute(con, "
          INSERT INTO Well_Lithology (well_id, depth_from_ft, depth_to_ft, description, source_document_id, notes)
          VALUES (NULL, ?, ?, ?, ?, 'confidence=ocr_heuristic_unvalidated; well_id NULL until log is promoted to a confirmed well')
        ", params = list(lith_df$depth_from_ft[r], lith_df$depth_to_ft[r], lith_df$description[r], doc_id))
      }
      n_lithology <- n_lithology + nrow(lith_df)
    }

    n_processed <- n_processed + 1L
    known_hashes <- c(known_hashes, primary_hash, alt_hash)

    .file_elapsed <- round(as.numeric(difftime(Sys.time(), .file_start_time, units = "secs")), 1)
    message("    (", .file_elapsed, " sec)")
    utils::setTxtProgressBar(.pb, .i)
  }
  close(.pb)

  message("  -> Processed ", n_processed, " log number(s) (", n_skipped, " unchanged, skipped; ",
          n_dup_content, " skipped as duplicate content under a different filename); ",
          n_text_layer, " had an extractable primary text/OCR layer; ", n_crossref,
          " matched an NDWR log number cross-reference; ", n_lithology,
          " lithology interval(s) staged (unvalidated).")

  dbAppendTable(con, "Ingest_Run_Log", data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    data_source = "WELL_LOGS", script_name = "ingest_well_logs.R",
    samples_inserted = 0, measurements_inserted = n_processed,
    notes = paste0("Well-log PDFs: ", n_processed, " processed, ", n_dup_content,
                    " duplicate-content skipped, ", n_text_layer, " with text layer, ",
                    n_crossref, " NDWR cross-referenced, ", n_lithology, " lithology intervals staged")
  ))

  invisible(list(processed = n_processed, skipped = n_skipped, dup_content = n_dup_content,
                 text_layer = n_text_layer, crossref = n_crossref, lithology = n_lithology))
}

#' Promote Well_Log_Documents rows to Wells/Water_Level_Observations/
#' Well_Work_Events once a human has confirmed which well a log_number
#' corresponds to.
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

    well <- dbGetQuery(con, "SELECT well_id, top_perforation, bottom_perforation, diameter_in FROM Wells WHERE well_name = ?",
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

    diam <- if (!is.na(doc$casing_diameter_in)) doc$casing_diameter_in else doc$hole_diameter_in
    if (!is.na(diam) && is.na(well$diameter_in[1])) {
      dbExecute(con, "UPDATE Wells SET diameter_in = ? WHERE well_id = ?", params = list(diam, well_id))
    }

    completion_date <- .safe_completion_date(doc$completion_date_raw)

    # Well_Work_Events: one row per promoted document, so a well's
    # status history is a real time series (fixes the earlier
    # single-snapshot limitation).
    if (!is.na(doc$work_type) || !is.na(doc$proposed_use) || !is.na(doc$hole_diameter_in) || !is.na(doc$casing_diameter_in)) {
      already_event <- dbGetQuery(con, "
        SELECT event_id FROM Well_Work_Events WHERE source_document_id = ?
      ", params = list(doc$document_id))
      if (nrow(already_event) == 0) {
        dbExecute(con, "
          INSERT INTO Well_Work_Events (well_id, source_document_id, work_type, proposed_use, event_date, hole_diameter_in, casing_diameter_in, notes)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ", params = list(
          well_id, doc$document_id, doc$work_type, doc$proposed_use, completion_date,
          doc$hole_diameter_in, doc$casing_diameter_in,
          paste0("From NDWR well log #", doc$log_number, ". ", row$notes)
        ))
      }
    }

    if (!is.na(doc$static_water_level_ft)) {
      if (is.na(completion_date)) {
        warning("[promote_well_log_documents] log #", doc$log_number,
                " has a static water level but no parseable completion date -- skipping the Water_Level_Observations row rather than defaulting to today's date.")
      } else {
        # 2026-09-12 (session 24) bug fix: previously only checked
        # (well_id, method), which meant only the FIRST driller's
        # report ever ingested for a well got its water level stored --
        # any later report (different date) was silently dropped. Now
        # matches the table's real UNIQUE(well_id, timestamp, method)
        # constraint, so every distinct dated reading is kept.
        already <- dbGetQuery(con, "
          SELECT observation_id FROM Water_Level_Observations
          WHERE well_id = ? AND method = 'driller_report' AND timestamp = ?
        ", params = list(well_id, completion_date))
        if (nrow(already) == 0) {
          wl_notes <- paste0("Static water level at time of drilling, from NDWR well log #", doc$log_number, ". ", row$notes)
          if (identical(doc$work_type, "abandonment")) {
            wl_notes <- paste0(wl_notes, " [FLAG: this report's type of work is 'abandonment' -- this reading may not reflect a representative ambient water table.]")
          }
          dbExecute(con, "
            INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes)
            VALUES (?, ?, ?, 'driller_report', 'driller_report', ?)
          ", params = list(well_id, completion_date, doc$static_water_level_ft, wl_notes))
        }
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

#' Register a provisional Wells row for any Well_Log_Documents row that
#' still has no well_id after promote_well_log_documents() -- i.e. a real
#' log with real coordinates/construction data, but no confirmed identity
#' match to an existing named well (2026-09-05 session 11: none of the
#' 7 real Steamboat logs then on hand cleared the bar for a confident
#' name match -- see AGENTS.md for the per-log nearest-NBMG-candidate
#' comparison).
#'
#' Rather than leaving this real data stranded in the staging table,
#' each qualifying log gets its own placeholder Wells row named
#' "Unidentified Well (NDWR Log <log_number>)" with well_role='unknown'
#' and coordinate_source recording exactly how the location was derived
#' (OCR text, NDWR log-number cross-reference, or -- new as of session
#' 24 -- PLSS section-centroid lookup), so the data is visible/mappable/
#' exportable while being unambiguous that it is NOT a confirmed match
#' to any Dhakal-diagram or NBMG well. If a human later confirms a real
#' identity, add a row to well_log_document_map.csv and re-run
#' promote_well_log_documents() -- reconciling the provisional Wells
#' row at that point is a manual step, not automated here.
#'
#' Deliberately restricted to a Steamboat-area bounding box: several of
#' the logs on hand are confirmed Gerlach-area NVGD wells from an
#' unrelated Ormat project and are skipped, not registered as Steamboat
#' Wells rows.
register_provisional_well_logs <- function(
    con,
    log_dir_filter = "data/raw/ndwr/Ormat_well_logs",
    lat_range = c(39.30, 39.50),
    lon_range = c(-119.85, -119.65)) {

  message("---- Registering provisional Wells rows for unmatched well logs ----")

  docs <- dbGetQuery(con, "
    SELECT * FROM Well_Log_Documents
    WHERE well_id IS NULL AND file_path LIKE ? AND match_method != 'duplicate_content_skipped'
  ", params = list(paste0(log_dir_filter, "%")))

  if (nrow(docs) == 0) {
    message("  -> No unmatched well-log documents to register.")
    return(invisible(list(created = 0L, out_of_scope = character(0), no_coord = character(0))))
  }

  n_created <- 0L
  skipped_oos <- character(0)
  skipped_nocoord <- character(0)

  for (i in seq_len(nrow(docs))) {
    d <- docs[i, ]
    well_name <- paste0("Unidentified Well (NDWR Log ", d$log_number, ")")

    already <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(well_name))
    if (nrow(already) > 0) {
      well_id <- already$well_id[1]
      dbExecute(con, "UPDATE Well_Log_Documents SET well_id = ? WHERE document_id = ?",
                params = list(well_id, d$document_id))
    } else {

      if (is.na(d$latitude) || is.na(d$longitude)) {
        skipped_nocoord <- c(skipped_nocoord, d$log_number)
        next
      }
      if (d$latitude < lat_range[1] || d$latitude > lat_range[2] ||
          d$longitude < lon_range[1] || d$longitude > lon_range[2]) {
        skipped_oos <- c(skipped_oos, d$log_number)
        next
      }

      coord_source <- switch(
        as.character(d$match_method),
        "ndwr_log_number_crossref" = "ndwr_well_log_crossref",
        "parsed_text" = "well_log_ocr_or_text",
        "well_log_unknown_method"
      )
      if (identical(d$plss_latlon_method, "plss_section_centroid")) coord_source <- "well_log_plss_centroid"
      coord_uncertainty_m <- if (identical(d$match_method, "ndwr_log_number_crossref")) 200 else 150
      if (identical(coord_source, "well_log_plss_centroid")) coord_uncertainty_m <- 800

      notes <- paste0(
        "Provisional well, identity NOT confirmed. Created from NDWR well log #", d$log_number,
        " (Well_Log_Documents.document_id=", d$document_id, "). ",
        if (!is.na(d$notes)) paste0(d$notes, " ") else "",
        "See AGENTS.md well-log sessions for nearest-candidate matches considered and rejected."
      )

      dbExecute(con, "
        INSERT INTO Wells (
          well_name, latitude, longitude, total_depth, top_perforation, bottom_perforation,
          diameter_in, well_role, coordinate_source, coordinate_uncertainty_m, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'unknown', ?, ?, ?)
      ", params = list(
        well_name, d$latitude, d$longitude,
        d$depth_drilled_ft, d$slot_from_ft, d$slot_to_ft,
        if (!is.na(d$casing_diameter_in)) d$casing_diameter_in else d$hole_diameter_in,
        coord_source, coord_uncertainty_m, notes
      ))

      well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
      dbExecute(con, "UPDATE Well_Log_Documents SET well_id = ? WHERE document_id = ?",
                params = list(well_id, d$document_id))
      n_created <- n_created + 1L
    }

    if (!is.na(d$work_type) || !is.na(d$proposed_use) || !is.na(d$hole_diameter_in) || !is.na(d$casing_diameter_in)) {
      already_event <- dbGetQuery(con, "SELECT event_id FROM Well_Work_Events WHERE source_document_id = ?", params = list(d$document_id))
      if (nrow(already_event) == 0) {
        dbExecute(con, "
          INSERT INTO Well_Work_Events (well_id, source_document_id, work_type, proposed_use, event_date, hole_diameter_in, casing_diameter_in, notes)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ", params = list(
          well_id, d$document_id, d$work_type, d$proposed_use,
          .safe_completion_date(d$completion_date_raw), d$hole_diameter_in, d$casing_diameter_in,
          paste0("From NDWR well log #", d$log_number, " (provisional well identity).")
        ))
      }
    }

    if (!is.na(d$static_water_level_ft)) {
      completion_date <- .safe_completion_date(d$completion_date_raw)
      if (is.na(completion_date)) {
        message("  (log #", d$log_number, ": static water level has no parseable completion date -- skipping Water_Level_Observations row.)")
      } else {
        # Same (well_id, method, timestamp) fix as promote_well_log_documents().
        already_wl <- dbGetQuery(con, "
          SELECT observation_id FROM Water_Level_Observations
          WHERE well_id = ? AND method = 'driller_report' AND timestamp = ?
        ", params = list(well_id, completion_date))
        if (nrow(already_wl) == 0) {
          wl_notes <- paste0("Static water level at time of drilling, from NDWR well log #", d$log_number, " (provisional well identity).")
          if (identical(d$work_type, "abandonment")) {
            wl_notes <- paste0(wl_notes, " [FLAG: this report's type of work is 'abandonment' -- this reading may not reflect a representative ambient water table.]")
          }
          dbExecute(con, "
            INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes)
            VALUES (?, ?, ?, 'driller_report', 'driller_report', ?)
          ", params = list(well_id, completion_date, d$static_water_level_ft, wl_notes))
        }
      }
    }
  }

  message("  -> Created ", n_created, " provisional Wells row(s); ",
          length(skipped_oos), " skipped (outside Steamboat bounding box -- likely Gerlach-area NVGD wells); ",
          length(skipped_nocoord), " skipped (no coordinate available).")

  invisible(list(created = n_created, out_of_scope = skipped_oos, no_coord = skipped_nocoord))
}
