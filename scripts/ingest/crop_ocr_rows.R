# Helper for checking OCR values against the scan: render the page behind each
# requested staged value and crop the table row, so a person can read the
# printed value. Used for ocr_outlier_review.csv.

crop_ocr_rows <- function(rows, out_dir = "output/tmp_crop", per_image = 8, dpi = 200) {
  suppressPackageStartupMessages({library(dplyr); library(magick)})
  source("scripts/ingest/helpers/parse_sgs_ocr_text.R")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  prr <- "data/raw/ndep/PRR/PPR_05_26_2026"
  panels <- list(); meta <- list()
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    pdf <- file.path(prr, r$raw_source_file)
    slug <- gsub("[^A-Za-z0-9]+", "_", tools::file_path_sans_ext(r$raw_source_file))
    p <- parse_sgs_ocr_text(slug, source_file = r$raw_source_file)
    p$station <- normalize_prr_station(p$client_sample_id); p$param <- normalize_sgs_parameter(p$parameter)
    hit <- p[p$station == r$station_name & p$date_sampled == r$sample_date & p$param == r$analyte & !is.na(p$value) & p$value == r$value, ]
    if (nrow(hit) == 0) { meta[[i]] <- data.frame(staging_id = r$staging_id, page = NA, note = "page not found"); next }
    pg <- hit$page[1]
    w <- readRDS(file.path("data/derived/ndep_prr_ocr", slug, sprintf("p%04d.rds", pg)))$words
    bb <- do.call(rbind, lapply(strsplit(w$bbox, ","), as.numeric)); w$x1 <- bb[, 1]; w$y1 <- bb[, 2]; w$x2 <- bb[, 3]; w$y2 <- bb[, 4]
    first <- strsplit(hit$param[1], " ")[[1]]; first <- first[nzchar(first)][1]
    cand <- w[startsWith(tolower(w$word), tolower(substr(first, 1, 4))), ]
    yc <- NA
    for (k in seq_len(nrow(cand))) {
      line <- w[abs(w$y1 - cand$y1[k]) < 20, ]
      if (any(grepl(as.character(hit$result_raw[1]), line$word, fixed = TRUE))) { yc <- c(min(line$y1), max(line$y2)); break }
    }
    if (anyNA(yc)) { meta[[i]] <- data.frame(staging_id = r$staging_id, page = pg, note = "row not located on page"); next }
    img_f <- file.path(out_dir, sprintf("pg_%d_%d.png", i, pg))
    pdftools::pdf_convert(pdf, pages = pg, dpi = 300, filenames = img_f, verbose = FALSE)
    im <- image_read(img_f); info <- image_info(im)
    top <- max(0, yc[1] - 90); h <- (yc[2] - yc[1]) + 180
    crop <- image_crop(im, sprintf("%dx%d+0+%d", info$width, h, top))
    crop <- image_resize(crop, "1300x")
    crop <- image_annotate(crop, sprintf("#%d  %s | %s | %s = %s (OCR)  [p%d]", i, r$station_name, r$sample_date, r$analyte, r$value, pg),
                           gravity = "northwest", size = 20, color = "red", boxcolor = "white")
    panels[[length(panels) + 1]] <- crop
    unlink(img_f)
    meta[[i]] <- data.frame(staging_id = r$staging_id, page = pg, note = "ok")
  }
  idx <- split(seq_along(panels), ceiling(seq_along(panels) / per_image))
  files <- character()
  for (g in seq_along(idx)) {
    st <- image_append(do.call(c, panels[idx[[g]]]), stack = TRUE)
    f <- file.path(out_dir, sprintf("review_%02d.png", g)); image_write(st, f, format = "png"); files <- c(files, f)
  }
  list(files = files, meta = bind_rows(meta))
}
