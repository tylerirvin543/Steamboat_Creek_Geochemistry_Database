# Parse SGS Silver State "Analytical Report" result tables from cached
# tesseract OCR text (data/derived/ndep_prr_ocr/<slug>/pNNNN.rds, built by
# scripts/ingest/ocr_ndep_prr_scans.R).
#
# The text-layer parser (parse_ndep_prr_lab_report) splits columns on runs of
# 2+ spaces, which OCR does not reproduce, so this one matches each result
# line with a single regex anchored on the method token (SM ####, EPA ###.#).
#
# Sample context (lab id, client sample id, sampled date/time) comes from the
# "Laboratory ID  Client Sample ID ..." header; result tables that continue
# onto the next page keep the last header's context until a new one appears.
# Lines that do not match (QC reports, wrapped names) are dropped; the return
# value carries a "diagnostics" attribute counting candidate vs parsed lines.

library(stringr); library(dplyr)

.sgs_row_re <- paste0(
  "^(.+?)\\s+",                                        # parameter
  "((?:SM|EPA|SW|ASTM|USGS)\\s?[0-9][0-9A-Za-z.\\- ]*?)\\s+",  # method
  "([<>]?\\s?[0-9][0-9.,]*(?:E-?[0-9]+)?|ND)\\s+",     # result
  "(pH Units|[A-Za-z/%]+)[.]?\\s+",                    # units
  "(\\S+)\\s+",                                        # PQL (OCR sometimes misreads digits)
  "([A-Za-z]{2,3})\\s+",                               # analyst
  "([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\\s+([0-9]{1,2}:[0-9]{2})",  # analyzed
  "(.*)$")                                             # trailing flag / OCR noise

parse_sgs_ocr_text <- function(slug, root = "data/derived/ndep_prr_ocr", source_file = slug) {
  files <- list.files(file.path(root, slug), "[.]rds$", full.names = TRUE)
  files <- files[order(as.integer(gsub("[^0-9]", "", basename(files))))]
  cur <- list(lab_id = NA, client = NA, sampled = NA, project = NA)
  out <- list(); n_cand <- 0L
  for (f in files) {
    page <- as.integer(gsub("[^0-9]", "", basename(f)))
    txt <- paste(readRDS(f)$text, collapse = "\n")
    if (!grepl("Analytical\\s*Rep", txt) || grepl("Quality Control Report", txt)) next
    lines <- str_trim(str_split(txt, "\n")[[1]])
    for (i in seq_along(lines)) {
      ln <- lines[i]
      if (grepl("^Laboratory ID\\s+Client Sample ID", ln) && i < length(lines)) {
        m <- str_match(lines[i + 1], "^([0-9]{4} ?[0-9]{4}-[0-9A-Za-z]+)\\s+(.+?)\\s+([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\\s+([0-9]{1,2}:[0-9]{2})")
        if (!is.na(m[1, 1])) cur <- list(lab_id = m[1, 2], client = m[1, 3], sampled = paste(m[1, 4], m[1, 5]))
        next
      }
      if (grepl("(SM|EPA)\\s?[0-9]", ln) && grepl("mg/L|ug/L|ppm|umhos|NTU|pH", ln)) n_cand <- n_cand + 1L
      m <- str_match(ln, .sgs_row_re)
      if (is.na(m[1, 1]) || is.na(cur$lab_id)) next
      raw <- str_replace_all(m[1, 4], "\\s", "")
      out[[length(out) + 1]] <- data.frame(
        lab_id = cur$lab_id, client_sample_id = cur$client, date_sampled = cur$sampled,
        parameter = str_trim(m[1, 2]), method = str_trim(m[1, 3]), result_raw = raw,
        value = suppressWarnings(as.numeric(gsub("[<>,]", "", raw))),
        non_detect = grepl("^<", raw) | raw == "ND", units = m[1, 5],
        pql = suppressWarnings(as.numeric(m[1, 6])), analyst = m[1, 7],
        date_analyzed = paste(m[1, 8], m[1, 9]),
        data_flag = { fl <- str_match(m[1, 10], "^\\s*([A-Z]{1,2})\\s*$")[1, 2]; ifelse(is.na(fl), NA_character_, fl) },
        page = page, source_file = source_file, stringsAsFactors = FALSE)
    }
  }
  res <- if (length(out)) bind_rows(out) else data.frame()
  attr(res, "diagnostics") <- list(candidate_lines = n_cand, parsed_rows = nrow(res))
  res
}

# ---- OCR clean-up helpers -------------------------------------------------

# Canonical SGS parameter names seen in these reports. OCR slips such as
# "Catcium", "Aikalinity", "CaCOQ3" are snapped to the nearest name when the
# edit distance is small enough (<= 2), otherwise the text is kept as read.
.sgs_known_params <- c(
  "Alkalinity, Bicarbonate (As CaCO3)", "Alkalinity, Carbonate (As CaCO3)",
  "Alkalinity, Hydroxide (As CaCO3)", "Alkalinity, Total (As CaCO3)",
  "Antimony", "Arsenic", "Boron", "Bromide", "Calcium", "Chloride", "Fluoride",
  "Lithium", "Magnesium", "Potassium", "Silica as SiO2", "Sodium", "Sulfate",
  "Suspended Solids", "Total Dissolved Solids", "Aluminum", "Barium", "Iron",
  "Manganese", "Strontium", "Nitrate as N", "Nitrite as N", "Phosphorus", "pH")

normalize_sgs_parameter <- function(x) {
  x <- str_trim(str_replace(x, "^[^A-Za-z]+", ""))
  vapply(x, function(p) {
    d <- adist(tolower(p), tolower(.sgs_known_params))
    j <- which.min(d)
    if (length(j) && d[j] <= 2) .sgs_known_params[j] else p
  }, character(1), USE.NAMES = FALSE)
}

# Map OCR'd client sample ids to the station names used elsewhere in the NDEP
# PRR staging/location map. Names without "Outlet" in the 2025 reports are the
# in-plant injection sampling points (matches the 2025-09-30 U230 forms).
normalize_prr_station <- function(x) {
  s <- tolower(str_squish(str_replace_all(x, "[^A-Za-z0-9 ]", " ")))
  s <- str_replace(s, "^g[l1i]( outlet)?$", "galena 1\\1")
  s <- str_replace(s, "^g([23])( outlet)?$", "galena \\1\\2")
  s <- str_replace(s, "^galena( outlet)?$", "galena 1\\1")
  s <- str_replace(s, "^sb ([23])", "sb\\1")
  outlet <- grepl("outlet", s)
  base <- dplyr::case_when(
    grepl("^galena 1", s) ~ "Galena 1", grepl("^galena 2", s) ~ "Galena 2",
    grepl("^galena 3", s) ~ "Galena 3", grepl("^sb2", s) ~ "SB2",
    grepl("^sb3", s) ~ "SB3", grepl("^sbhr", s) ~ "SBHR",
    grepl("^jeppson", s) ~ "Jeppson Dom", grepl("^boyd", s) ~ "Boyd Dom",
    grepl("^rogers", s) ~ "Rogers Well", grepl("^eich", s) ~ "Eich Well",
    grepl("^soccer", s) ~ "Soccer Field", grepl("^herz deep", s) ~ "Herz Deep",
    grepl("^herz d", s) ~ "Herz Dom", grepl("^ndot", s) ~ "NDOT",
    TRUE ~ NA_character_)
  plant <- base %in% c("Galena 1", "Galena 2", "Galena 3", "SB2", "SB3", "SBHR")
  dplyr::case_when(
    is.na(base) ~ str_squish(x),
    plant & outlet ~ paste(base, "Outlet"),
    base == "Galena 2" ~ "Galena 2 Injection Composite (TFT)",
    plant ~ paste(base, "Injection Outlet"),
    TRUE ~ base)
}

#' Staging-ready rows (same columns as Staging_NDEP_WQ) from OCR'd SGS reports.
stage_sgs_ocr <- function(slug, source_file, ...) {
  p <- parse_sgs_ocr_text(slug, source_file = source_file, ...)
  if (nrow(p) == 0) return(p)
  p |>
    # OCR garbles "mg/L" ("mg/t", "mo/L", "ma/L", "mog/t", "magi", ...); every result in these SGS
    # reports is in mg/L, and unrecognized units drop the value out of PHREEQC input.
    mutate(units = ifelse(str_detect(units, "^(mg|mo|ma|mog|mag)/?[A-Za-z]$"), "mg/L", units),
           parameter = normalize_sgs_parameter(parameter),
           station_name = normalize_prr_station(client_sample_id)) |>
    filter(!is.na(value) | non_detect) |>
    transmute(station_name, latitude = NA_real_, longitude = NA_real_,
              sample_date = date_sampled, analyte = parameter, value, units, method,
              detection_limit = pql, raw_source_file = source_file) |>
    distinct(station_name, sample_date, analyte, .keep_all = TRUE)
}

#' Hold back OCR-staged values that are far from the station's own history.
#'
#' OCR sometimes drops a decimal point on dilute values (7.4 read as 74) or
#' misreads a digit. For each unpromoted, OCR-sourced Staging_NDEP_WQ row whose
#' value is more than `threshold` times above (or below 1/threshold of) the
#' median for the same station and analyte, set promoted_at to
#' 'HELD_OCR_OUTLIER' (promotion only takes rows with promoted_at NULL) and
#' list it in `out_csv` for a person to check against the scan. Values are not
#' corrected. Rows in a weaker 1.8x-to-threshold band are listed as "watch"
#' but still promoted.
hold_ocr_outliers <- function(con, raw_source_files, threshold = 4, watch = 1.8,
                              out_csv = "data/derived/ndep_prr_ocr/ocr_outlier_review.csv") {
  # newly appended rows have a NULL staging_id until promotion backfills it
  DBI::dbExecute(con, "UPDATE Staging_NDEP_WQ SET staging_id = rowid WHERE staging_id IS NULL")
  st <- DBI::dbGetQuery(con, "SELECT staging_id, station_name, sample_date, analyte, value, units, detection_limit, raw_source_file, promoted_at FROM Staging_NDEP_WQ")
  num <- st[!is.na(st$value) & st$value > 0 & !(!is.na(st$detection_limit) & st$value == st$detection_limit), ]
  key <- paste(num$station_name, num$analyte, num$units)
  med <- tapply(num$value, key, median); n <- tapply(num$value, key, length)
  num$med <- as.numeric(med[key]); num$n <- as.numeric(n[key]); num$ratio <- num$value / num$med
  cand <- num[num$raw_source_file %in% raw_source_files & is.na(num$promoted_at) & num$n >= 4 &
              (num$ratio > watch | num$ratio < 1 / watch), ]
  cand$action <- ifelse(cand$ratio > threshold | cand$ratio < 1 / threshold, "held", "watch")
  held <- cand$staging_id[cand$action == "held"]
  if (length(held)) DBI::dbExecute(con, paste0("UPDATE Staging_NDEP_WQ SET promoted_at = 'HELD_OCR_OUTLIER' WHERE staging_id IN (",
                                              paste(held, collapse = ","), ")"))
  if (nrow(cand)) {
    dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
    prev <- if (file.exists(out_csv)) read.csv(out_csv, stringsAsFactors = FALSE) else NULL
    outd <- cand[, c("staging_id", "station_name", "sample_date", "analyte", "value", "units", "med", "ratio", "action", "raw_source_file")]
    # keep earlier rows (and any review columns a person added) and append only new staging_ids
    if (!is.null(prev)) outd <- dplyr::bind_rows(prev, outd[!(outd$staging_id %in% prev$staging_id), ])
    write.csv(outd, out_csv, row.names = FALSE)
  }
  message("  -> OCR outlier check: ", length(held), " value(s) held, ", sum(cand$action == "watch"), " on watch (see ", out_csv, ")")
  invisible(cand)
}
