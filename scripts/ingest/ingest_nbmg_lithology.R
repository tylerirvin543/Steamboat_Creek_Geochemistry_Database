# ============================================================
# ingest_nbmg_lithology.R
#
# Parses the TOPS column of NBMG_Compilation_Records
# ("Surface Sinter, clay; 125' Andesite; 320' Granodiorite") into depth
# intervals and stores them in Well_Lithology.
#
# Reading rule: the number before each unit is the TOP depth of that unit in
# feet ("Surface" = 0); a unit runs to the next top, and the last unit to total
# depth. A string that does not start with "Surface" has no described interval
# above its first top (that gap is not invented).
#
# Policy:
#  * Only wells with a loaded/matched identity (disposition created_well or
#    filled_existing). Held rows and permit-only rows are not used.
#  * Fill-only: a well that already has any Well_Lithology rows is skipped
#    (logged), so logs read from the driller's report are never overridden.
#  * formation_unit comes from classify_formation_unit() (17_formation_unit_schema.R);
#    the verbatim description is always kept.
#  * Idempotent: a well that already has rows tagged 'NBMG TOPS' is skipped.
# Review file: data/derived/nbmg_tops_lithology_parsed.csv (every parsed interval).
# ============================================================
library(DBI); library(dplyr); library(readr); library(stringr)
source("database/schema/17_formation_unit_schema.R")

parse_nbmg_tops <- function(tops, td_ft) {
  if (is.na(tops) || !nzchar(trimws(tops))) return(NULL)
  parts <- trimws(strsplit(sub("\\.$", "", trimws(tops)), ";")[[1]])
  parts <- parts[nzchar(parts)]
  top <- numeric(0); desc <- character(0)
  for (p in parts) {
    if (grepl("^Surface\\b", p, ignore.case = TRUE)) { top <- c(top, 0); desc <- c(desc, trimws(sub("^Surface\\s*", "", p, ignore.case = TRUE))) }
    else if (grepl("^[0-9,]+'", p)) { top <- c(top, as.numeric(gsub(",", "", sub("'.*$", "", p)))); desc <- c(desc, trimws(sub("^[0-9,]+'\\s*", "", p))) }
    else return(NULL)  # unrecognised layout: do not guess
  }
  td <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", td_ft)))
  bottoms <- c(top[-1], td)
  d <- tibble(depth_from_ft = top, depth_to_ft = bottoms, description = desc)
  d <- d[!is.na(d$depth_to_ft) & d$depth_to_ft > d$depth_from_ft & nzchar(d$description), ]
  if (nrow(d) == 0) NULL else d
}

ingest_nbmg_lithology <- function(con, review_csv = "data/derived/nbmg_tops_lithology_parsed.csv") {
  message("---- Parsing NBMG TOPS lithology ----")
  migrate_well_lithology_formation_unit(con)
  rec <- dbGetQuery(con, "SELECT record_id, src_api, src_well, src_td, src_tops, disposition, loaded_well_id, matched_well_id
                          FROM NBMG_Compilation_Records
                          WHERE disposition IN ('created_well','filled_existing') AND src_tops IS NOT NULL AND trim(src_tops) <> ''")
  out <- list(); n_ins <- 0L; skipped <- character(0)
  for (i in seq_len(nrow(rec))) {
    r <- rec[i, ]
    wid <- r$loaded_well_id
    d <- parse_nbmg_tops(r$src_tops, r$src_td)
    if (is.null(d)) { skipped <- c(skipped, paste0(r$src_well, " (unparsed/no interval)")); next }
    d$well_id <- wid; d$source <- r$src_api; d$well_name <- r$src_well
    d$formation_unit <- vapply(d$description, classify_formation_unit, character(1))
    d$basis <- "lithology_text_mapping"
    fb <- d$formation_unit == "unknown" & grepl("clay|sand|silt|cobble|soil|gravel|sinter|opal|alluvi|cinder|pebbl", tolower(d$description)) & !grepl("swelling|shale|rock", tolower(d$description))
    d$formation_unit[fb] <- "Qal"; d$basis[fb] <- "lithology_text_mapping_permit_fallback_unconsolidated_or_sinter"
    fg <- d$formation_unit == "unknown" & grepl("granite", tolower(d$description))
    d$formation_unit[fg] <- "Kgd"; d$basis[fg] <- "lithology_text_mapping_permit_fallback_granite"
    d$status <- "inserted"
    have_nbmg <- dbGetQuery(con, "SELECT COUNT(*) n FROM Well_Lithology WHERE well_id = ? AND notes LIKE 'NBMG TOPS%'", params = list(wid))$n
    have_any <- dbGetQuery(con, "SELECT COUNT(*) n FROM Well_Lithology WHERE well_id = ?", params = list(wid))$n
    if (have_nbmg > 0) { d$status <- "already_loaded" }
    else if (have_any > 0) { d$status <- "skipped_existing_lithology"; skipped <- c(skipped, paste0(r$src_well, " (has other lithology)")) }
    else {
      for (k in seq_len(nrow(d))) {
        dbExecute(con, "INSERT INTO Well_Lithology (well_id, depth_from_ft, depth_to_ft, description, units, notes, formation_unit, formation_unit_basis)
                        VALUES (?,?,?,?, 'ft', ?, ?, ?)",
                  params = list(wid, d$depth_from_ft[k], d$depth_to_ft[k], d$description[k],
                                paste0("NBMG TOPS (compilation API ", r$src_api, "); confidence=permit_summary, depths are unit tops from the permit file"),
                                d$formation_unit[k], d$basis[k]))
        n_ins <- n_ins + 1L
      }
    }
    out[[length(out) + 1]] <- d
  }
  rev_df <- bind_rows(out)
  dir.create(dirname(review_csv), recursive = TRUE, showWarnings = FALSE)
  write_csv(rev_df, review_csv)
  message("  -> ", n_ins, " interval(s) inserted; ", length(skipped), " well(s) skipped: ", paste(skipped, collapse = "; "))
  invisible(list(inserted = n_ins, skipped = skipped, parsed = rev_df))
}
