# ============================================================
# 17_formation_unit_schema.R
#
# Purpose: a single, project-wide controlled vocabulary for the four
# Steamboat-area geologic units Skalbeck (2001) uses throughout his
# 2.75-D gravity/aeromagnetic model and depth-point grid -- Qal
# (alluvium), Tv (Tertiary volcanics), AltKgdpKm (altered granodiorite
# + metasedimentary/metavolcanic rock, modeled as one combined unit in
# Table A-2), and Kgd (fresh granodiorite bedrock). Real well-log
# lithology (Well_Lithology) has, until now, used whatever free-text
# description a driller's report or a literature source happened to
# use ("silty sand", "basaltic andesite", "schist/conglomerate/
# quartzite", ...) -- useful for a human reading the source, but not
# directly comparable to Skalbeck's model units, which is exactly what
# Leapfrog needs if real well logs and the Skalbeck depth-point grid
# are ever going to inform the same 3-D geologic model.
#
# This migration is purely additive: `description` (the verbatim
# source text) is never touched or overwritten. `formation_unit` is a
# second, parallel, controlled-vocabulary column that a human or a
# documented mapping function fills in alongside it.
# ============================================================

migrate_well_lithology_formation_unit <- function(con) {
  cols <- dbGetQuery(con, "PRAGMA table_info(Well_Lithology)")$name
  if (!"formation_unit" %in% cols) {
    message("[MIGRATION] Adding Well_Lithology.formation_unit (controlled vocabulary).")
    dbExecute(con, "ALTER TABLE Well_Lithology ADD COLUMN formation_unit TEXT")
  }
  if (!"formation_unit_basis" %in% cols) {
    # How the unit was assigned -- 'source_table_column' (Table 3's own
    # Tv/Kgd/pKm depth columns ARE the unit, no classification needed),
    # 'lithology_text_mapping' (classified from a free-text description,
    # see classify_formation_unit() below), or 'unknown' (genuinely
    # ambiguous, left for human review).
    dbExecute(con, "ALTER TABLE Well_Lithology ADD COLUMN formation_unit_basis TEXT")
  }
  invisible(NULL)
}

#' Classify a free-text lithology description into Skalbeck's
#' Qal/Tv/AltKgdpKm/Kgd scheme. Deliberately conservative: returns
#' "unknown" (never a guessed unit) for anything not matching a
#' documented keyword rule below. Every rule here is written out so a
#' human reviewer can see exactly why a given description was
#' classified the way it was -- this is a real geological judgment
#' call, not a blind keyword hash.
#'
#' Rules (checked in order, first match wins):
#'   - Unconsolidated near-surface material (sand/loam/gravel/clay
#'     without "swelling"/alteration language, "alluvium") -> Qal.
#'   - Volcanic rock (basaltic andesite, volcanic, andesite, tuff) not
#'     otherwise flagged as altered -> Tv.
#'   - "Metamorphosed volcanic" specifically -> Tv (Skalbeck's own
#'     Table A-1 treats metamorphosed/altered volcanics within the Tv
#'     unit's density/magnetic-property range for this project's
#'     purposes, not as a separate Kgd/AltKgdpKm unit).
#'   - Metasedimentary/metamorphic sedimentary rock, schist,
#'     conglomerate, quartzite, gneiss, or explicit "granodiorite" with
#'     alteration language -> AltKgdpKm (matches Skalbeck's own
#'     definition of this unit as "altered granodiorite + pKm
#'     metasediments/metavolcanics combined").
#'   - Fresh/unaltered granodiorite with no alteration language ->
#'     Kgd.
#'   - Anything else (notably: swelling/expansive clay at depth, which
#'     could plausibly be either an alteration product within
#'     AltKgdpKm or a distinct clay zone Skalbeck's model doesn't
#'     resolve) -> "unknown", flagged for human review rather than
#'     guessed.
classify_formation_unit <- function(description) {
  d <- tolower(trimws(description))
  if (d == "" || is.na(d)) return("unknown")

  if (grepl("swelling|expansive", d)) return("unknown")

  if (grepl("sandy loam|black.*loam|fine sand|coarse sand|silty sand|gravel|alluvium|topsoil|loam", d)) {
    return("Qal")
  }
  if (grepl("metamorphosed volcanic", d)) {
    return("Tv")
  }
  if (grepl("basaltic andesite|andesite|^volcanic|volcanic rock|tuff", d)) {
    return("Tv")
  }
  if (grepl("metamorphosed sedimentary|schist|conglomerate|quartzite|gneiss", d)) {
    return("AltKgdpKm")
  }
  if (grepl("altered granodiorite|alter.*granodiorite", d)) {
    return("AltKgdpKm")
  }
  if (grepl("granodiorite", d)) {
    return("Kgd")
  }
  "unknown"
}

#' Apply classify_formation_unit() to every existing Well_Lithology row
#' that has a real description but no formation_unit yet (i.e. rows
#' NOT already filled by a source-table-column mapping like Skalbeck's
#' Table 3, which sets formation_unit_basis='source_table_column'
#' directly and should never be reclassified from free text). Never
#' touches a row that already has formation_unit set -- idempotent.
classify_existing_well_lithology <- function(con) {
  rows <- dbGetQuery(con, "
    SELECT lithology_id, description FROM Well_Lithology
    WHERE formation_unit IS NULL AND description IS NOT NULL
  ")
  if (nrow(rows) == 0) {
    message("[classify_existing_well_lithology] 0 rows need classification.")
    return(invisible(list(classified = 0L)))
  }
  n_unknown <- 0L
  for (i in seq_len(nrow(rows))) {
    unit <- classify_formation_unit(rows$description[i])
    if (unit == "unknown") n_unknown <- n_unknown + 1L
    dbExecute(con, "
      UPDATE Well_Lithology SET formation_unit = ?, formation_unit_basis = 'lithology_text_mapping'
      WHERE lithology_id = ?
    ", params = list(unit, rows$lithology_id[i]))
  }
  message("[classify_existing_well_lithology] Classified ", nrow(rows), " row(s), ",
          n_unknown, " left as 'unknown' (genuinely ambiguous free text, e.g. swelling-clay intervals -- ",
          "flagged for human review, not guessed).")
  invisible(list(classified = nrow(rows), unknown = n_unknown))
}
