# ------------------------------------------------------------
# parse_collar_appendix_a.R
#
# Parses Collar (1990) M.S. thesis, Appendix A "Hot spring observations" (thesis
# pp. 223-266; PDF pages 240-283) from the OCR text layer into one row per spring
# per dated visit. Observations come from Nehring (NN), GOSA, Hudson (DH), BLM and
# NDEP, Jun 1977 - Apr 1988. The wording is kept verbatim in raw_text; the parsed
# fields (status, temperature, depth to water, flow) are conveniences extracted
# with regular expressions and can be wrong where the OCR is bad.
#
#   parse_collar_appendix_a(pdf_path)  -> data.frame
#   write: data/raw/historical/collar1990_appendixA_spring_observations.csv
# ------------------------------------------------------------

.APPA_SOURCES <- c(NN = "Nehring (1980)", GOSA = "Geyser Observation and Study Association", DH = "Donald Hudson",
                   BLM = "Bureau of Land Management", NDEP = "Nevada Division of Environmental Protection")
.MONTHS <- c(JAN = 1, FEB = 2, MAR = 3, APR = 4, MAY = 5, JUN = 6, JUNE = 6, JUL = 7, JULY = 7, AUG = 8, SEP = 9, SEPT = 9, OCT = 10, NOV = 11, DEC = 12)

.fix_digits <- function(x) chartr("lIO", "110", x)

# OCR splits decimals ('0 . 33ft', 'o .. 83'); rejoin them for field extraction only (raw_text stays as read)
.clean_nums <- function(x) {
  x <- gsub("([0-9])\\s*\\.+\\s*([0-9])", "\\1.\\2", x)
  x <- gsub("\\b[oOa]\\s*\\.+\\s*([0-9])", "0.\\1", x)
  x <- gsub("([0-9]\\.[0-9]+)\\s+([0-9])\\s*ft", "\\1\\2ft", x)                 # '1.1 7 ft' -> '1.17ft'
  x <- gsub("([0-9])[oO](?=\\s*\\.\\s*[cC])", "\\10", x, perl = TRUE)          # '7o . c' -> '70 . c'
  x
}

.fix_spring_id <- function(id) {
  id <- tolower(trimws(id)); id <- gsub("\\s+", "", id)
  id <- sub("^a(?=[nsew])", "8", id, perl = TRUE)   # 'anw' -> '8nw'
  gsub("l", "1", id)                                # 'l' is never a real suffix: '4ls' -> '41s'
}

.parse_header <- function(line) {
  m <- regmatches(line, regexec("^[\\f\\s]*([0-9lIO]{1,2}(?:\\s*,\\s*[0-9lIO]{1,2})?)\\s*([A-Z]{3,5})\\.?\\s*(19[78][0-9])\\s*[\\(\\{\\[]\\s*([A-Za-z, ]*?)\\s*[\\)\\}\\]]", line, perl = TRUE))[[1]]
  if (!length(m)) return(NULL)
  mon <- .MONTHS[m[3]]; if (is.na(mon)) return(NULL)
  days <- as.integer(strsplit(.fix_digits(gsub("\\s", "", m[2])), ",")[[1]])
  src <- toupper(trimws(strsplit(gsub("\\s+", "", m[5]), ",")[[1]]))
  list(date = as.Date(sprintf("%s-%02d-%02d", m[4], mon, days[1])), day_note = if (length(days) > 1) paste("also", paste(days[-1], collapse = ",")) else NA_character_,
       source_code = paste(src[nzchar(src)], collapse = "+"))
}

.expand_ids <- function(idtxt) {
  idtxt <- trimws(idtxt)
  if (grepl("^[0-9a-z]+\\s*-\\s*[0-9a-z]+$", idtxt, ignore.case = TRUE)) {            # range such as 16-16se
    p <- trimws(strsplit(idtxt, "-")[[1]]); return(data.frame(id = .fix_spring_id(p[1]), range_end = .fix_spring_id(p[2]), stringsAsFactors = FALSE))
  }
  p <- trimws(strsplit(idtxt, ",")[[1]]); p <- p[nzchar(p)]
  data.frame(id = .fix_spring_id(p), range_end = NA_character_, stringsAsFactors = FALSE)
}

.status_of <- function(x) {
  t <- tolower(x)
  if (grepl("erupt|geyser|surg", t)) "erupting"
  else if (grepl("almost dry|nearly dry|damp", t)) "almost_dry"
  else if (grepl("\\bdry\\b|\\bdcy\\b", t)) "dry"
  else if (grepl("discharg|flowing|overflow|spilling|outflow|\bflow\b", t)) "flowing"
  else if (grepl("steaming|steam", t)) "steaming"
  else if (grepl("boiling", t)) "boiling"
  else if (grepl("marsh|seep", t)) "seep"
  else if (grepl("stagnant", t)) "stagnant"
  else if (grepl("active|bubbling|splashing", t)) "active"
  else if (grepl("water level|depth to water|standing water|full|below rim|pool|water at", t)) "water_in_vent"
  else "other"
}

.temp_of <- function(x) {
  x <- .clean_nums(x)
  m <- regmatches(x, gregexpr("([0-9]{2,3}(?:\\.[0-9])?)\\s*[^0-9A-Za-z\\s]?\\s*[oO]?\\s*[cC](?![A-Za-z])", x, perl = TRUE))[[1]]
  if (!length(m)) return(NA_real_)
  v <- suppressWarnings(as.numeric(sub("^([0-9.]+).*", "\\1", m))); v <- v[!is.na(v) & v >= 15 & v <= 105]
  if (length(v)) v[1] else NA_real_
}

.flow_of <- function(x) {
  m <- regmatches(x, regexec("([0-9]+(?:\\.[0-9]+)?)\\s*lpm", x, perl = TRUE))[[1]]
  if (length(m)) as.numeric(m[2]) else NA_real_
}

# Depth to water in feet. Returns first value, its basis, whether estimated, and a second reading with its source tag.
.depth_of <- function(x) {
  t <- gsub("\\s+", " ", .clean_nums(x))
  # m with ft in parentheses: 'about 4.5m (15ft.) depth' -> use the ft figure
  paren <- regmatches(t, regexec("([0-9.]+)\\s*m\\s*\\(\\s*([0-9.]+)\\s*ft", t, perl = TRUE))[[1]]
  toks <- gregexpr("([0-9]+(?:\\.[0-9]+)?)\\s*(ft|in|cm|m)\\b\\.?(?:\\s*\\((?:NDEP|BLM)\\))?", t, perl = TRUE)
  tl0 <- tolower(t)
  ok_ctx <- grepl("water level|depth to water|below rim|\\bdown\\b|depth|deep|visible", tl0)
  st <- as.integer(toks[[1]]); ln <- attr(toks[[1]], "match.length")
  keep <- if (st[1] > 0 && ok_ctx) vapply(seq_along(st), function(k) {
    after <- substr(tl0, st[k] + ln[k], st[k] + ln[k] + 14); before <- substr(tl0, max(1, st[k] - 40), st[k] - 1)
    !grepl("^\\.?\\s*(north|south|east|west|sw|se|nw|ne)", after) && !grepl("landing|great as", before)
  }, NA) else rep(FALSE, length(st))
  raw <- if (st[1] > 0) regmatches(t, toks)[[1]][keep] else character()
  vals <- numeric(); src <- character()
  for (r in raw) {
    n <- as.numeric(sub("^([0-9.]+).*", "\\1", r)); u <- sub("^[0-9.]+\\s*(ft|in|cm|m).*", "\\1", r)
    s <- if (grepl("NDEP", r)) "NDEP" else if (grepl("BLM", r)) "BLM" else NA_character_
    ft <- switch(u, ft = n, `in` = n / 12, cm = n / 30.48, m = n * 3.2808)
    vals <- c(vals, round(ft, 2)); src <- c(src, s)
  }
  if (length(paren) && length(vals)) { vals[1] <- as.numeric(paren[3]); }
  if (!length(vals)) return(list(d = NA_real_, basis = NA_character_, est = NA, alt = NA_real_, alt_src = NA_character_))
  tl <- tolower(t)
  basis <- if (grepl("below rim", tl)) "below_rim" else if (grepl("depth to water|water level", tl)) "depth_to_water" else "unspecified"
  list(d = vals[1], basis = basis, est = grepl("est\\.|about|approx", tl), alt = if (length(vals) > 1) vals[2] else NA_real_, alt_src = if (length(vals) > 1) src[2] else NA_character_)
}

parse_collar_appendix_a <- function(pdf_path, pages = 240:283, lines = NULL) {
  if (is.null(lines)) {
    txt <- pdftools::pdf_text(pdf_path)[pages]
    lines <- unlist(strsplit(txt, "\n", fixed = TRUE))
  }
  lines <- iconv(lines, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "?")
  lines[is.na(lines)] <- ""
  start <- grep("7 JUNE 1977", lines, fixed = TRUE)[1]
  lines <- lines[start:length(lines)]
  rows <- list(); hdr <- NULL; terrace <- "Main Terrace"; last <- 0L; notes <- character()
  bad_headers <- character()
  for (ln in lines) {
    s <- gsub("\f", "", ln, fixed = TRUE)
    if (!nzchar(trimws(s)) || grepl("^\\s*[0-9]{3}\\s*$", s)) next                      # blank or page number
    h <- .parse_header(ln)
    if (!is.null(h)) { hdr <- h; terrace <- "Main Terrace"; last <- 0L; next }
    if (grepl("^\\s*[0-9lIO]{1,2}\\s*[A-Z]{3,5}\\.?\\s*19[78][0-9]", s)) { bad_headers <- c(bad_headers, trimws(s)); next }
    if (grepl("^\\s*(Main|Low) Terrace\\s*$", s)) { terrace <- trimws(s); last <- 0L; next }
    if (is.null(hdr)) next
    if (grepl("^\\s*NOTE:", s)) { notes <- c(notes, trimws(s)); last <- -1L; next }
    m <- regmatches(s, regexec("^\\s*([0-9lIOa][0-9a-zA-Z]{0,3}(?:\\s*[,-]\\s*[0-9lIOa]?[0-9a-zA-Z]{0,3})*)\\s*:\\s*(.*)$", s, perl = TRUE))[[1]]
    if (length(m) && grepl("[0-9lI]", substr(m[2], 1, 4))) {
      ids <- .expand_ids(m[2])
      for (k in seq_len(nrow(ids))) {
        rows[[length(rows) + 1]] <- data.frame(obs_date = as.character(hdr$date), date_note = hdr$day_note, source_code = hdr$source_code,
          terrace = terrace, spring_id_raw = trimws(m[2]), spring_id = ids$id[k], id_range_end = ids$range_end[k], raw_text = trimws(m[3]), stringsAsFactors = FALSE)
      }
      last <- length(rows); nk <- nrow(ids)
      attr(rows, "last_n") <- nk
      next
    }
    # continuation of the previous entry (or trailing header text, which is dropped)
    if (last > 0L) { nk <- attr(rows, "last_n"); for (j in seq(last - nk + 1L, last)) rows[[j]]$raw_text <- paste(rows[[j]]$raw_text, trimws(s)) }
  }
  out <- do.call(rbind, rows)
  out$raw_text <- gsub("\\s+", " ", out$raw_text)
  out$status <- vapply(out$raw_text, .status_of, "")
  out$temperature_c <- vapply(out$raw_text, .temp_of, 0)
  out$flow_lpm <- vapply(out$raw_text, .flow_of, 0)
  dd <- lapply(out$raw_text, .depth_of)
  out$depth_to_water_ft <- vapply(dd, function(z) z$d, 0); out$depth_basis <- vapply(dd, function(z) z$basis, "")
  out$depth_estimated <- vapply(dd, function(z) z$est, NA); out$depth_alt_ft <- vapply(dd, function(z) z$alt, 0); out$depth_alt_source <- vapply(dd, function(z) z$alt_src, "")
  out$source_name <- unname(vapply(strsplit(out$source_code, "\\+"), function(p) paste(.APPA_SOURCES[p], collapse = "; "), ""))
  out <- out[order(out$obs_date, out$source_code), ]
  rownames(out) <- NULL
  attr(out, "notes") <- notes; attr(out, "bad_headers") <- bad_headers
  out
}
