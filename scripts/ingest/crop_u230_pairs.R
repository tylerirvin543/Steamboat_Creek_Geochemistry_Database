# Render U230 form page pairs (facility page + sampling page) from the scanned
# NDEP PRR PDFs as cropped bands, so handwritten date/time/location, field
# measurements and water level can be read by a person.
# Facility page (Page 1 of 2): well name, last gauged date, measured water level.
# Sampling page (Page 2 of 2): date, time, location, pH, conductivity, temperature.

u230_pairs <- function(doc_slug, pages_index = "data/derived/ndep_prr_ocr/_page_index.rds") {
  pg <- readRDS(pages_index); pg <- pg[pg$doc == doc_slug & pg$is_u230, ]
  pg <- pg[order(pg$page), ]
  fac <- grepl("FACILITY AND PERMIT", pg$text); smp <- grepl("SAMPLING INFORMATION", pg$text)
  out <- list()
  for (i in which(fac)) {
    nxt <- pg$page[smp & pg$page > pg$page[i]]
    out[[length(out) + 1]] <- data.frame(doc = doc_slug, fac_page = pg$page[i], smp_page = if (length(nxt)) min(nxt) else NA)
  }
  do.call(rbind, out)
}

crop_u230_pair <- function(pdf, fac_page, smp_page, label, dpi = 130, width = 1000) {
  suppressPackageStartupMessages(library(magick))
  tmp <- tempfile(fileext = ".png")
  rd <- function(p) { f <- sub("[.]png$", sprintf("_%d.png", p), tmp); pdftools::pdf_convert(pdf, pages = p, dpi = dpi, filenames = f, verbose = FALSE); image_read(f) }
  band <- function(im, lo, hi) { i <- image_info(im); image_crop(im, sprintf("%dx%d+0+%d", i$width, round(i$height * (hi - lo)), round(i$height * lo))) }
  fa <- rd(fac_page); sm <- if (!is.na(smp_page)) rd(smp_page) else NULL
  parts <- list(band(fa, 0.19, 0.31), band(fa, 0.74, 0.86))
  if (!is.null(sm)) parts <- c(parts, list(band(sm, 0.19, 0.30), band(sm, 0.46, 0.56)))
  parts <- lapply(parts, image_resize, paste0(width, "x"))
  st <- image_append(do.call(c, parts), stack = TRUE)
  image_annotate(st, label, gravity = "northeast", size = 22, color = "blue", boxcolor = "white")
}
