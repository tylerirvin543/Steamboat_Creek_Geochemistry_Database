# Register the staged-only private wells from Collar (1990) Appendix B as
# named, provisional Wells rows located at their PLSS section centroid.
#
# Input: data/raw/wells/collar_private_wells.csv (doc_log, well_name,
# section/township/range, cached centroid latitude/longitude, notes).
# The centroid comes from BLM's PLSS service (.convert_plss_to_latlon());
# it is cached in the CSV so a rebuild does not need the network.
#
# What it does (idempotent, never overwrites):
#   1. creates a Wells row per well_name (coordinate_source =
#      'plss_section_centroid', 800 m uncertainty);
#   2. fills Well_Log_Documents.section/township/range when NULL;
#   3. appends a log_number -> well_name row to well_log_document_map.csv
#      so promote_well_log_documents() fills depth, perforations, lithology,
#      work event and static water level.
# It does NOT merge with same-surname wells already on file from NDEP/NBMG
# (different vintage and depth); cross-references belong in the notes.
# Must run before promote_well_log_documents().

library(DBI); library(dplyr)

register_collar_private_wells <- function(
    con,
    csv = "data/raw/wells/collar_private_wells.csv",
    map_csv = "data/raw/ndwr/well_log_document_map.csv") {
  message("---- Registering Collar (1990) private wells (PLSS centroid) ----")
  if (!file.exists(csv)) { message("  -> ", csv, " not found; skipping."); return(invisible(NULL)) }
  cw <- read.csv(csv, stringsAsFactors = FALSE, colClasses = c(doc_log = "character"))
  has_coord <- !is.na(cw$latitude) & !is.na(cw$longitude)
  if (any(!has_coord)) {
    # Fall back to a live lookup only for rows missing a cached centroid
    if (!exists(".convert_plss_to_latlon")) source("scripts/ingest/helpers/parse_well_log_pdf.R")
    for (i in which(!has_coord)) {
      r <- cw[i, ]
      x <- .convert_plss_to_latlon(as.integer(r$section), as.integer(sub("[NS]", "", r$township)),
                                   sub("\\d+", "", r$township), as.integer(sub("[EW]", "", r$range)),
                                   sub("\\d+", "", r$range))
      cw$latitude[i] <- x$latitude; cw$longitude[i] <- x$longitude
    }
  }
  map <- if (file.exists(map_csv)) read.csv(map_csv, stringsAsFactors = FALSE, colClasses = "character") else
    data.frame(log_number = character(), well_name = character(), notes = character())
  n_new <- 0L; n_map <- 0L; no_doc <- character(0)
  for (i in seq_len(nrow(cw))) {
    r <- cw[i, ]
    doc <- dbGetQuery(con, "SELECT document_id, well_id, proposed_use, section FROM Well_Log_Documents WHERE log_number = ?",
                      params = list(r$doc_log))
    if (nrow(doc) == 0) { no_doc <- c(no_doc, r$doc_log); next }
    doc <- doc[1, ]
    if (!is.na(doc$well_id)) next  # already linked to some well
    if (is.na(doc$section)) {
      dbExecute(con, "UPDATE Well_Log_Documents SET section = ?, township = ?, range = ? WHERE document_id = ?",
                params = list(as.character(r$section), r$township, r$range, doc$document_id))
    }
    if (nrow(dbGetQuery(con, "SELECT 1 FROM Wells WHERE well_name = ?", params = list(r$well_name))) == 0) {
      role <- if ("well_role" %in% names(r) && !is.na(r$well_role) && nzchar(r$well_role)) r$well_role else if (identical(doc$proposed_use, "domestic")) "domestic" else "unknown"
      dbExecute(con, "
        INSERT INTO Wells (well_name, owner, latitude, longitude, well_role, coordinate_source, coordinate_uncertainty_m, notes)
        VALUES (?, ?, ?, ?, ?, 'plss_section_centroid', 800, ?)",
        params = list(r$well_name, r$owner_ndwr, r$latitude, r$longitude, role,
                      paste0("Provisional. ", r$notes, " Location is the centre of Sec ", r$section, " ", r$township,
                             " ", r$range, " (about 800 m uncertainty); NDWR quarter-quarter point is ",
                             r$dist_to_ndwr_m, " m away.")))
      n_new <- n_new + 1L
    }
    if (!(r$doc_log %in% map$log_number)) {
      map <- rbind(map[, c("log_number", "well_name", "notes")],
                   data.frame(log_number = r$doc_log, well_name = r$well_name,
                              notes = "Registered 2026-10-29 as a provisional Collar (1990) App. B private well; identity is the owner/log, not a match to another well on file.",
                              stringsAsFactors = FALSE))
      n_map <- n_map + 1L
    }
  }
  if (n_map > 0) write.csv(map, map_csv, row.names = FALSE)
  if (length(no_doc) > 0) warning("[register_collar_private_wells] no Well_Log_Documents row for: ", paste(no_doc, collapse = ", "))
  message("  -> ", n_new, " Wells row(s) created; ", n_map, " map row(s) appended.")
  invisible(list(created = n_new, mapped = n_map))
}
