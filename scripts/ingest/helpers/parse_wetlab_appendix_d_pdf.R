# ------------------------------------------------------------
# parse_wetlab_appendix_d_pdf.R
#
# Purpose (added 2026-09-30):
# Parse the "Appendix D: Geochemical Results from Injection Composite
# Sample" lab-report pages found in NDEP TFT Compliance Reports --
# WETLAB (Western Environmental Testing Laboratory) format, structurally
# different from the SGS-format report parse_ndep_prr_pdf.R already
# handles (different header text, different column layout: "Analyte
# Method Results Units DF RL Analyzed LabID" vs SGS's "Parameter Method
# Result Units PQL Analyst Date/Time Analyzed").
#
# This project's FIRST position-aware PDF table parser. The existing
# SGS parser uses `pdftools::pdf_text()` + `strsplit(line, "\\s{2,}")`
# on `pdftotext -layout`-rendered lines -- confirmed, by direct
# inspection, to badly misalign this WETLAB table (values shifted
# relative to their analyte-name rows by one or more visual lines).
# `pdftools::pdf_data()` gives each word's own real x/y coordinates on
# the page, which turns out to reconstruct the table correctly: every
# analyte row's name/method/result/units genuinely share one exact y
# value (confirmed by direct inspection of a real report -- e.g.
# Chloride's row is cleanly "Chloride | EPA | 300.0 | 794 | mg/L | 20 |
# 20.0 | <date> | <labid>" at one y, recovering a plausible real
# 794 mg/L chloride value that `pdftotext -layout` could not).
#
# Real, confirmed limitation of this document type (not a parser bug):
# both TFT reports checked so far contain exactly ONE real WETLAB
# sample per report -- a single required UIC-permit injection composite
# (e.g. "250709-001 G2 Injection"), not per-production-well chemistry.
# "24-5" in one report's filename refers to a production-well-group
# flow narrative elsewhere in the document, not this lab sample. See
# AGENTS.md and docs/action_items_for_user.md for the full context.
# ------------------------------------------------------------

library(pdftools)
library(stringr)
library(dplyr)

#' Detect whether a PDF is (at least in part) a WETLAB-format lab
#' report, so ingest_ndep_prr.R can route it to this parser instead of
#' the SGS-format one.
is_wetlab_format <- function(path) {
  txt <- paste(pdf_text(path), collapse = " ")
  str_detect(txt, "WETLAB") || str_detect(txt, "Western Environmental Testing Laboratory")
}

#' Assign each word to the nearest header column, using the header
#' row's own word x-positions as column boundaries (midpoints between
#' consecutive header words) -- general to any WETLAB report's exact
#' column pixel positions, not hardcoded to one document.
.assign_column <- function(x, header_x, header_names) {
  # header_x, header_names assumed sorted by x ascending.
  boundaries <- c(-Inf, (header_x[-1] + header_x[-length(header_x)]) / 2, Inf)
  idx <- findInterval(x, boundaries)
  header_names[idx]
}

#' Parse every WETLAB-format Appendix D sample block out of one PDF.
#'
#' @param path path to the PDF.
#' @return data frame with columns: customer_sample_id, wetlab_sample_id,
#'   collect_datetime, receive_date, analyte, method, result_raw, value,
#'   non_detect, units, analyzed_date, lab_id, page, source_file.
parse_wetlab_lab_report <- function(path) {

  pages_text <- pdf_text(path)
  if (sum(nchar(pages_text)) == 0) {
    stop(
      "No extractable text in ", basename(path), " -- this PDF is scanned/",
      "image-only. OCR is required before this parser can run, and is not ",
      "attempted here."
    )
  }

  pages_data <- pdf_data(path)
  all_rows <- list()

  for (page_num in seq_along(pages_data)) {

    p <- pages_data[[page_num]]
    if (nrow(p) == 0) next

    # ---- Locate this page's header row (Analyte/Method/Results/...) ----
    header_words <- p |>
      filter(text %in% c("Analyte", "Method", "Results", "Units", "DF", "RL", "Analyzed", "LabID")) |>
      distinct(text, .keep_all = TRUE)

    if (!all(c("Analyte", "Results") %in% header_words$text)) next  # not a data-table page

    # The real header spans 2 close-together y values on this document
    # ("Results/Units/DF/RL/Analyzed" one row, "Analyte/Method/LabID"
    # the row just below) -- collapse to one reference y per column name
    # by keeping each header word's own (x, name), regardless of its
    # exact y, then use the MAX header y as the "table starts below here"
    # cutoff.
    header_y_max <- max(header_words$y)
    header_words <- header_words[order(header_words$x), ]

    # ---- Locate this block's Customer Sample ID / dates (from the
    # clean, non-misaligned header text lines -- pdf_text is fine here) ----
    lines <- str_split(pages_text[page_num], "\n")[[1]]
    sample_line_idx <- which(str_detect(lines, "^Customer Sample ID"))

    for (block_i in seq_along(sample_line_idx)) {
      li <- sample_line_idx[block_i]
      sample_line <- lines[li]
      wetlab_line <- if ((li + 1) <= length(lines)) lines[li + 1] else ""

      customer_sample_id <- str_trim(str_extract(sample_line, "(?<=Customer Sample ID:)[^C]*(?=Collect Date/Time:|$)"))
      collect_datetime <- str_trim(str_extract(sample_line, "(?<=Collect Date/Time:).*"))
      wetlab_sample_id <- str_trim(str_extract(wetlab_line, "(?<=WETLAB Sample ID:)[^R]*(?=Receive Date:|$)"))
      receive_date <- str_trim(str_extract(wetlab_line, "(?<=Receive Date:).*"))

      # ---- Reconstruct the data rows below the header on this page ----
      body <- p |> filter(y > header_y_max + 5)
      # Stop at the page footer ("DF=Dilution Factor..." / "Page N of M")
      footer_y <- body |> filter(str_detect(text, "^DF=")) |> pull(y) |> (\(v) if (length(v) > 0) min(v) else Inf)()
      body <- body |> filter(y < footer_y)

      if (nrow(body) == 0) next

      body <- body[order(body$y, body$x), ]
      body$column <- .assign_column(body$x, header_words$x, header_words$text)

      row_groups <- split(body, body$y)

      for (row_words in row_groups) {
        name_txt   <- paste(row_words$text[row_words$column == "Analyte"], collapse = " ")
        method_txt <- paste(row_words$text[row_words$column == "Method"], collapse = " ")
        result_txt <- row_words$text[row_words$column == "Results"]
        units_txt  <- paste(row_words$text[row_words$column == "Units"], collapse = " ")
        analyzed_txt <- row_words$text[row_words$column == "Analyzed"]
        labid_txt  <- paste(row_words$text[row_words$column == "LabID"], collapse = " ")

        result_txt <- result_txt[str_detect(result_txt, "^(ND|NA|[0-9.]+)$")]
        if (length(result_txt) == 0 || name_txt == "") next  # section header / no result -- skip

        result_raw <- result_txt[1]
        non_detect <- toupper(result_raw) %in% c("ND", "NA")
        value <- suppressWarnings(as.numeric(result_raw))

        analyzed_date <- analyzed_txt[str_detect(analyzed_txt, "\\d+/\\d+/\\d+")][1]

        all_rows[[length(all_rows) + 1]] <- data.frame(
          customer_sample_id = customer_sample_id,
          wetlab_sample_id = wetlab_sample_id,
          collect_datetime = collect_datetime,
          receive_date = receive_date,
          analyte = name_txt,
          method = method_txt,
          result_raw = result_raw,
          value = value,
          non_detect = non_detect,
          units = units_txt,
          analyzed_date = ifelse(is.na(analyzed_date), NA_character_, analyzed_date),
          lab_id = labid_txt,
          page = page_num,
          source_file = basename(path),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(all_rows) == 0) {
    warning("No WETLAB-format rows parsed from ", basename(path),
            " -- check that it actually contains a WETLAB Appendix D lab report.")
    return(data.frame())
  }

  out <- bind_rows(all_rows)
  # Two pages of this document often repeat the identical sample block
  # (a duplicate page, not a second real sample) -- deliberately kept
  # as-is here (not deduplicated), since ingest_ndep_prr.R's own
  # Documents_Processed/staging dedup downstream handles true
  # duplicates; this parser's job is only to extract what's really on
  # the page.
  out
}
