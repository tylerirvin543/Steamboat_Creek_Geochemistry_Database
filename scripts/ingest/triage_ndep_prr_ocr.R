# Triage of the cached OCR text for the scanned NDEP PRR PDFs.
# Writes data/derived/ndep_prr_ocr/_page_index.csv (one row per page, with a
# coarse page type and keyword flags) and data/derived/ndep_prr_audit.csv
# (one row per PDF: pages, text layer, staged rows, page-type counts).

triage_ndep_prr_ocr <- function(root = "data/derived/ndep_prr_ocr",
                                prr_dir = "data/raw/ndep/PRR/PPR_05_26_2026",
                                db = "database/geochem_operational.sqlite") {
  rows <- list()
  for (d in list.dirs(root, recursive = FALSE)) {
    for (f in list.files(d, "[.]rds$", full.names = TRUE)) {
      x <- paste(readRDS(f)$text, collapse = " ")
      rows[[length(rows) + 1]] <- data.frame(
        doc = basename(d), page = as.integer(gsub("[^0-9]", "", basename(f))),
        text = x, stringsAsFactors = FALSE)
    }
  }
  pg <- do.call(rbind, rows)
  g <- function(p) grepl(p, pg$text, ignore.case = TRUE)
  pg$is_u230 <- g("Field Sampling . Monitoring Summary|SAMPLING INFORMATION")
  pg$is_sgs <- g("SGS|Definitions . Qualifiers|Laboratory ID|Analytical Report")
  pg$has_chloride <- g("chloride")
  pg$has_waterlevel <- g("water level|depth to water|static water|water elevation")
  pg$has_injection <- g("injection (rate|pressure)|psig|gpm")
  pg$type <- with(pg, ifelse(is_u230, "U230_form",
                      ifelse(is_sgs & has_chloride, "lab_report_with_Cl",
                      ifelse(is_sgs, "lab_report_other",
                      ifelse(has_waterlevel, "water_level_text",
                      ifelse(has_injection, "injection_ops_text", "other"))))))
  pg$chars <- nchar(pg$text)
  write.csv(pg[, setdiff(names(pg), "text")][order(pg$doc, pg$page), ],
            file.path(root, "_page_index.csv"), row.names = FALSE)
  saveRDS(pg, file.path(root, "_page_index.rds"))

  pdfs <- list.files(prr_dir, "[.]pdf$", full.names = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), db, flags = RSQLite::SQLITE_RO); on.exit(DBI::dbDisconnect(con))
  dp <- DBI::dbGetQuery(con, "select file_name, file_hash, rows_staged from Documents_Processed")
  aud <- do.call(rbind, lapply(pdfs, function(f) {
    sl <- gsub("[^A-Za-z0-9]+", "_", tools::file_path_sans_ext(basename(f)))
    h <- unname(tools::md5sum(f))
    sub <- pg[pg$doc == sl, ]
    tt <- table(factor(sub$type, levels = c("U230_form", "lab_report_with_Cl", "lab_report_other", "water_level_text", "injection_ops_text", "other")))
    data.frame(file = basename(f), pages = pdftools::pdf_info(f)$pages,
               text_layer_chars = sum(nchar(pdftools::pdf_text(f))),
               ocr_pages_cached = nrow(sub),
               rows_staged = dp$rows_staged[match(basename(f), dp$file_name)],
               as.list(tt), check.names = FALSE, stringsAsFactors = FALSE)
  }))
  write.csv(aud, "data/derived/ndep_prr_audit.csv", row.names = FALSE)
  aud
}
