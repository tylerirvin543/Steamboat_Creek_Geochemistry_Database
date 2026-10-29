# Resumable per-page OCR cache for the scanned NDEP PRR report PDFs.
#
# Usage (one worker of k):  Rscript scripts/ingest/ocr_ndep_prr_scans.R <worker> <n_workers>
# Output: data/derived/ndep_prr_ocr/<doc_slug>/p<NNNN>.rds, each a list with
#   $text (page text) and $words (tesseract::ocr_data word table with bboxes).
# Pages already cached are skipped, so the script can be restarted any time.
# Only PDFs with no text layer are OCR'd.

args <- commandArgs(trailingOnly = TRUE)
worker <- if (length(args) >= 1) as.integer(args[1]) else 1L
n_workers <- if (length(args) >= 2) as.integer(args[2]) else 1L

source("scripts/ingest/helpers/parse_well_log_pdf.R")  # .ensure_tesseract()
.ensure_tesseract()
suppressPackageStartupMessages(library(tesseract))
eng <- tesseract("eng")

prr_dir <- "data/raw/ndep/PRR/PPR_05_26_2026"
out_root <- "data/derived/ndep_prr_ocr"
pdfs <- list.files(prr_dir, "\\.pdf$", full.names = TRUE)
slug <- function(p) gsub("[^A-Za-z0-9]+", "_", tools::file_path_sans_ext(basename(p)))

for (f in pdfs) {
  info <- pdftools::pdf_info(f)
  if (sum(nchar(pdftools::pdf_text(f))) > 0) next
  od <- file.path(out_root, slug(f)); dir.create(od, recursive = TRUE, showWarnings = FALSE)
  pages <- seq_len(info$pages)
  pages <- pages[(pages - 1L) %% n_workers == (worker - 1L)]
  for (p in pages) {
    rds <- file.path(od, sprintf("p%04d.rds", p))
    if (file.exists(rds)) next
    png <- file.path(od, sprintf("tmp_w%d_%04d.png", worker, p))
    ok <- tryCatch({
      pdftools::pdf_convert(f, dpi = 300, pages = p, filenames = png, verbose = FALSE)
      w <- ocr_data(png, engine = eng)
      txt <- ocr(png, engine = eng)
      saveRDS(list(text = txt, words = w), rds)
      TRUE
    }, error = function(e) { message("FAILED ", basename(f), " p", p, ": ", conditionMessage(e)); FALSE })
    unlink(png)
    if (p %% 25 == 0) message(format(Sys.time(), "%H:%M:%S"), " worker ", worker, ": ", basename(f), " p", p, "/", info$pages)
  }
}
message("worker ", worker, " done")
