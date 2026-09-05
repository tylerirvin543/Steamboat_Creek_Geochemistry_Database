# ------------------------------------------------------------
# parse_ndep_prr_pdf.R
#
# Purpose:
# Parse lab-analytical-report pages out of an NDEP Public Records
# Request PDF (pilot: "Steamboat 2024 Semi-annual Digital Submittal
# (UNEV2007204).pdf" -- an SGS Silver State Analytical Laboratories
# report format). Returns a data frame ready to stage in
# Staging_NDEP_WQ, one row per parameter result.
#
# Design notes (from inspecting the pilot PDF directly with pdftools):
# - Each "sample block" starts with a header line
#   "Laboratory ID   Client Sample ID   Date/Time Sampled   Date Received"
#   followed immediately by the actual values for that block.
# - A block's data rows are introduced by a second header line
#   "Parameter   Method   Result   Units   PQL   Analyst   Date/Time
#   Analyzed   [Data Flag]" and continue until a blank line.
# - Columns are separated by >=2 spaces (fixed-width layout), so
#   `strsplit(line, "\\s{2,}")` recovers the columns reliably for
#   single-line rows. A parameter name that wraps onto a second
#   physical line (seen once in the pilot, e.g. "Alkalinity,
#   Bicarbonate (As" / "CaCO3)") does NOT split into the expected
#   7/8 fields and is deliberately DROPPED rather than guessed at --
#   this is a staging step (Staging_NDEP_WQ), so a human reviewing
#   before promotion to core tables can go back to the source PDF
#   page for anything dropped here.
# - NOT all PRR PDFs share this layout -- other document types (IMR
#   reports, UIC forms, etc.) will need their own parser function
#   when tackled, per the phased PRR ingestion plan.
# ------------------------------------------------------------

library(pdftools)
library(stringr)
library(dplyr)

#' Parse one NDEP PRR lab-report PDF into a long data frame of results.
#'
#' @param path path to the PDF
#' @return data frame with columns: lab_id, client_sample_id,
#'   date_sampled, date_received, parameter, method, result_raw,
#'   value, non_detect, units, pql, analyst, date_analyzed, data_flag,
#'   page, source_file
parse_ndep_prr_lab_report <- function(path) {

  pages <- pdf_text(path)
  if (sum(nchar(pages)) == 0) {
    stop(
      "No extractable text in ", basename(path), " -- this PDF is scanned/",
      "image-only. OCR (e.g. the `tesseract` package) is required before ",
      "this parser can run, and is not attempted here."
    )
  }

  all_rows <- list()

  for (page_num in seq_along(pages)) {

    lines <- strsplit(pages[page_num], "\n")[[1]]

    current_lab_id <- NA_character_
    current_client_id <- NA_character_
    current_date_sampled <- NA_character_
    current_date_received <- NA_character_
    in_data_block <- FALSE

    for (i in seq_along(lines)) {
      line <- lines[i]
      trimmed <- str_trim(line)

      if (trimmed == "") {
        in_data_block <- FALSE
        next
      }

      # New sample block header -> the next non-blank line has the values
      if (str_detect(trimmed, "^Laboratory ID\\s+Client Sample ID")) {
        next_line <- if (i < length(lines)) str_trim(lines[i + 1]) else ""
        parts <- str_split(next_line, "\\s{2,}")[[1]]
        if (length(parts) >= 4) {
          current_lab_id <- parts[1]
          current_client_id <- parts[2]
          current_date_sampled <- parts[3]
          current_date_received <- parts[4]
        }
        in_data_block <- FALSE
        next
      }

      # Data-row header -> subsequent lines (until blank) are results
      if (str_detect(trimmed, "^Parameter\\s+Method\\s+Result")) {
        in_data_block <- TRUE
        next
      }

      if (in_data_block) {
        parts <- str_split(trimmed, "\\s{2,}")[[1]]

        if (length(parts) %in% c(7, 8)) {
          result_raw <- parts[3]
          non_detect <- str_detect(result_raw, "^<") || toupper(result_raw) == "ND"
          value <- suppressWarnings(as.numeric(str_remove(result_raw, "^<")))

          all_rows[[length(all_rows) + 1]] <- data.frame(
            lab_id = current_lab_id,
            client_sample_id = current_client_id,
            date_sampled = current_date_sampled,
            date_received = current_date_received,
            parameter = parts[1],
            method = parts[2],
            result_raw = result_raw,
            value = value,
            non_detect = non_detect,
            units = parts[4],
            pql = suppressWarnings(as.numeric(parts[5])),
            analyst = parts[6],
            date_analyzed = parts[7],
            data_flag = if (length(parts) == 8) parts[8] else NA_character_,
            page = page_num,
            source_file = basename(path),
            stringsAsFactors = FALSE
          )
        }
        # else: doesn't match the expected shape (e.g. a wrapped
        # parameter name) -- deliberately dropped, see header comment.
      }
    }
  }

  if (length(all_rows) == 0) {
    warning("No lab-report rows parsed from ", basename(path),
            " -- check that it actually contains SGS-format lab reports.")
    return(data.frame())
  }

  bind_rows(all_rows)
}
