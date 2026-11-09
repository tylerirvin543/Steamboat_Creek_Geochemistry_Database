# ============================================================
# ingest_nvgeowel.R
#
# Cross-references the hand-transcribed NBMG "Nevada Geothermal Well Database List -
# NVGEOWEL - 2009" (data/raw/nbmg/nvgeowel_2009_steamboat_transcription.csv) with what
# the project already holds, registers the source, stages every row, and adds the few
# real wells that are in no other source.
#
#  * Source tracking: Data_Sources rows for this list and for the 2019 NBMG compilation;
#    every row stays in NVGEOWEL_Records with its match and disposition.
#  * Matching: to NBMG_Compilation_Records (the 2019 edition of the same NBMG database)
#    by well name + township/range (+ section, permit, TD); then to Wells by name.
#  * Disagreements (TD, year) are written to `flags`; nothing already in Wells is changed.
#  * New wells only for real, unmatched wells (not expired / not drilled / project areas)
#    in scope. Coordinate = PLSS quarter-quarter centroid from the BLM service
#    (400 m uncertainty; 800 m when only the section is known), no coordinate if the
#    service is unreachable.
#  * Idempotent (unique key on the staged row).
# Review file: data/derived/nvgeowel_cross_reference.csv

# ============================================================
library(DBI); library(dplyr); library(readr); library(digest)
source("scripts/ingest/ingest_nbmg_compilation.R")   # role/use/status helpers and date parser

.nv_register_source <- function(con, name, citation, url, notes) {
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, citation, url, notes) VALUES (?,?,?,?)", params = list(name, citation, url, notes))
  dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ?", params = list(name))$source_id[1]
}

.NV_SRC <- "NBMG Nevada Geothermal Well Database List (NVGEOWEL), 2009"

.NBMG19_SRC <- "NBMG statewide geothermal well/permit compilation (GEOTHERM06102019.csv)"

register_nvgeowel_sources <- function(con) {
  a <- .nv_register_source(con, .NV_SRC,
    "Nevada Bureau of Mines and Geology. Nevada Geothermal Well Database List - NVGEOWEL - 2009 (printed 12/22/2010).",
    "http://www.nbmg.unr.edu/geothermal/mapfiles/nvgeowel.html (copy: https://epubs.nsla.nv.gov)",
    "Hand-transcribed from screenshots (Washoe, T17N-T18N, R19E-R20E) into data/raw/nbmg/nvgeowel_2009_steamboat_transcription.csv; rows staged in NVGEOWEL_Records. List gives PLSS location only, no coordinates.")
  b <- .nv_register_source(con, .NBMG19_SRC,
    "Nevada Bureau of Mines and Geology statewide geothermal well and permit compilation, saved 2019 (later edition of NVGEOWEL).",
    NA_character_, "data/raw/nbmg/GEOTHERM06102019.csv; Steamboat rows staged in NBMG_Compilation_Records and loaded by ingest_nbmg_compilation.R.")
  c(nvgeowel = a, nbmg2019 = b)
}

.nv_strip <- function(x) {
  y <- tolower(x)
  y <- gsub("\\b(industrial|well|wells|no\\.?|domestic)\\b", " ", y)
  gsub("[^a-z0-9]", "", y)
}

.nv_key <- function(well, operator) {
  k <- .nv_strip(well)
  if (!nzchar(k)) k <- paste0("op_", substr(gsub("[^a-z0-9]", "", tolower(operator)), 1, 8))
  k
}

.nv_num <- function(x) suppressWarnings(as.numeric(gsub("[^0-9.]", "", as.character(x))))

.nv_permit <- function(x) { y <- gsub("^DWR-", "", trimws(as.character(x))); y <- sub("^0+", "", y); ifelse(is.na(y) | y == "NA", "", y) }

.nv_year <- function(x) { d <- .parse_nbmg_date(x); if (!is.na(d)) return(as.integer(substr(d, 1, 4))); m <- regmatches(x, regexpr("(19|20)[0-9]{2}", x)); if (length(m)) as.integer(m) else NA_integer_ }

.nv_real_well <- function(status, td, well) {
  s <- tolower(ifelse(is.na(status), "", status)); n <- tolower(well)
  if (grepl("project area", n)) return(FALSE)
  if (grepl("expired|not drilled", s)) return(FALSE)
  !is.na(td) || grepl("drilled|domestic|p&a|abandon|production|injection|observation|thermal|test|industrial|shut", s)
}

cross_reference_nvgeowel <- function(con, csv = "data/raw/nbmg/nvgeowel_2009_steamboat_transcription.csv") {
  x <- read_csv(csv, col_types = cols(.default = col_character(), td_ft = col_double()), na = c("", "NA"), show_col_types = FALSE)
  st <- dbGetQuery(con, "SELECT record_id, src_well, src_operator, src_s, src_t, src_r, src_td, src_permit, src_spud_date, src_compl_date,
                                disposition, loaded_well_id, matched_well_id FROM NBMG_Compilation_Records")
  st$key <- mapply(.nv_key, st$src_well, st$src_operator); st$td <- .nv_num(st$src_td); st$sec <- suppressWarnings(as.integer(st$src_s)); st$pm <- .nv_permit(st$src_permit)
  wl <- dbGetQuery(con, "SELECT well_id, well_name, total_depth FROM Wells"); wl$key <- vapply(wl$well_name, .nv_key, character(1), operator = "")
  x$key <- mapply(.nv_key, x$well_name, x$operator); x$secn <- suppressWarnings(as.integer(x$sec)); x$pm <- .nv_permit(x$permit)
  x$match_method <- "none"; x$nbmg_record_id <- NA_integer_; x$matched_well_id <- NA_integer_; x$disposition <- NA_character_; x$flags <- ""
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    cand <- st[st$src_t == r$twn & st$src_r == r$rng, , drop = FALSE]
    if (nrow(cand)) {
      name_ok <- mapply(function(k) nzchar(k) && (k == r$key || (nchar(k) >= 3 && nchar(r$key) >= 3 && (grepl(r$key, k, fixed = TRUE) || grepl(k, r$key, fixed = TRUE)))), cand$key)
      sec_ok <- !is.na(cand$sec) & !is.na(r$secn) & cand$sec == r$secn
      td_ok <- is.na(cand$td) | is.na(r$td_ft) | abs(cand$td - r$td_ft) <= pmax(15, 0.05 * pmax(cand$td, r$td_ft, na.rm = TRUE))
      td_both <- !is.na(cand$td) & !is.na(r$td_ft) & td_ok
      pm_ok <- nzchar(r$pm) & cand$pm == r$pm
      pm_conflict <- nzchar(r$pm) & nzchar(cand$pm) & cand$pm != r$pm & !grepl("^DWR", r$permit) & !grepl("^DWR", cand$src_permit)
      score <- 3 * name_ok + 2 * pm_ok + sec_ok + td_ok + td_both
      acc <- (name_ok & sec_ok & td_ok) | (pm_ok & sec_ok & td_ok) | (name_ok & td_both & (is.na(r$secn) | is.na(cand$sec))) | (name_ok & sec_ok & pm_ok) | (name_ok & pm_ok & (is.na(r$secn) | is.na(cand$sec))) | (name_ok & sec_ok & nchar(r$key) >= 6 & nchar(cand$key) >= 6) ; acc <- acc & !pm_conflict
      if (any(acc)) {
        j <- which(acc)[which.max(score[acc])]; c1 <- cand[j, ]
        x$nbmg_record_id[i] <- c1$record_id; x$matched_well_id[i] <- ifelse(is.na(c1$loaded_well_id), c1$matched_well_id, c1$loaded_well_id)
        x$match_method[i] <- paste0("name", if (sec_ok[j]) "_sec", if (td_both[j]) "_td", if (pm_ok[j]) "_permit")
        x$disposition[i] <- switch(c1$disposition, created_well = "in_db_matched", filled_existing = "in_db_matched", held_probable = "in_nbmg2019_held",
                                   staging_only_permit = "in_nbmg2019_permit_only", staging_only_context = "in_nbmg2019_context_only", "in_nbmg2019_other")
        fl <- character()
        if (!is.na(c1$td) && !is.na(r$td_ft) && abs(c1$td - r$td_ft) > max(15, 0.05 * max(c1$td, r$td_ft))) fl <- c(fl, sprintf("TD %g vs 2019 %g", r$td_ft, c1$td))
        y1 <- .nv_year(r$date_text); y2 <- suppressWarnings(max(.nv_year(c1$src_spud_date), .nv_year(c1$src_compl_date), na.rm = TRUE))
        if (!is.na(y1) && is.finite(y2) && abs(y1 - y2) > 1) fl <- c(fl, sprintf("year %d vs 2019 %d", y1, y2))
        x$flags[i] <- paste(fl, collapse = "; ")
        next
      }
    }
    w <- wl[wl$key == r$key & nzchar(r$key), , drop = FALSE]
    if (nrow(w) == 1 && (is.na(r$td_ft) || is.na(w$total_depth) || abs(w$total_depth - r$td_ft) <= max(15, 0.05 * r$td_ft))) {
      x$matched_well_id[i] <- w$well_id; x$match_method[i] <- "wells_name"; x$disposition[i] <- "matched_in_wells_only"
    } else {
      x$disposition[i] <- if (!.nv_real_well(r$status_class, r$td_ft, r$well_name)) "permit_only_not_loaded" else if (is.na(r$secn)) "not_loaded_no_location" else "candidate_new"
    }
  }
  x
}

# BLM PLSS service: quarter-quarter centroid from the section polygon's bounding box.

.nv_plss_cache <- new.env()

.nv_plss_bbox <- function(sec, twn, rng) {
  key <- paste(sec, twn, rng); if (!is.null(.nv_plss_cache[[key]])) return(.nv_plss_cache[[key]])
  base <- "https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer"
  tw <- sprintf("%03d", as.integer(sub("[NS]", "", twn))); rg <- sprintf("%03d", as.integer(sub("[EW]", "", rng)))
  tq <- utils::URLencode(sprintf("STATEABBR='NV' AND TWNSHPNO='%s' AND TWNSHPDIR='%s' AND RANGENO='%s' AND RANGEDIR='%s'", tw, substr(twn, nchar(twn), nchar(twn)), rg, substr(rng, nchar(rng), nchar(rng))), reserved = TRUE)
  id <- tryCatch(jsonlite::fromJSON(paste0(base, "/1/query?where=", tq, "&outFields=PLSSID&returnGeometry=false&f=json"))$features$attributes$PLSSID[1], error = function(e) NA)
  out <- NULL
  if (!is.null(id) && !is.na(id)) {
    sq <- utils::URLencode(sprintf("PLSSID='%s' AND FRSTDIVNO='%02d'", id, as.integer(sec)), reserved = TRUE)
    rr <- tryCatch(jsonlite::fromJSON(paste0(base, "/2/query?where=", sq, "&outFields=FRSTDIVNO&outSR=4326&returnGeometry=true&f=json"))$features$geometry$rings[[1]], error = function(e) NULL)
    if (!is.null(rr)) { ring <- if (length(dim(rr)) == 3) rr[1, , ] else rr; out <- c(xmin = min(ring[, 1]), xmax = max(ring[, 1]), ymin = min(ring[, 2]), ymax = max(ring[, 2])) }
  }
  .nv_plss_cache[[key]] <- out; out
}

nvgeowel_qq_latlon <- function(sec, twn, rng, qtr) {
  bb <- .nv_plss_bbox(sec, twn, rng); if (is.null(bb)) return(list(lat = NA_real_, lon = NA_real_, unc = NA_real_))
  qs <- if (is.na(qtr) || !nzchar(qtr)) character() else toupper(trimws(sub("/4", "", strsplit(qtr, "[,;]")[[1]])))
  x0 <- 0; x1 <- 1; y0 <- 0; y1 <- 1
  for (q in rev(qs)) {
    if (grepl("N", q)) y0 <- (y0 + y1) / 2 else if (grepl("S", q)) y1 <- (y0 + y1) / 2
    if (grepl("E", q)) x0 <- (x0 + x1) / 2 else if (grepl("W", q)) x1 <- (x0 + x1) / 2
  }
  list(lat = unname(bb["ymin"] + (y0 + y1) / 2 * (bb["ymax"] - bb["ymin"])), lon = unname(bb["xmin"] + (x0 + x1) / 2 * (bb["xmax"] - bb["xmin"])),
       unc = if (length(qs) >= 2) 400 else 800)
}

ingest_nvgeowel <- function(con, csv = "data/raw/nbmg/nvgeowel_2009_steamboat_transcription.csv", create_wells = TRUE,
                            review_csv = "data/derived/nvgeowel_cross_reference.csv") {
  message("---- NVGEOWEL 2009 list: cross-reference and ingest ----")
  if (!file.exists(csv)) { message("  -> ", csv, " not found; skipped"); return(invisible(NULL)) }
  src <- register_nvgeowel_sources(con)
  x <- cross_reference_nvgeowel(con, csv)
  existing_names <- dbGetQuery(con, "SELECT well_name FROM Wells")$well_name
  n_new <- 0L; n_stage <- 0L; n_created <- 0L; n_updated <- 0L
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    h <- digest(paste(unlist(r[c("twn","rng","sec","qtrqtr","permit","operator","well_name","date_text","status_class","td_ft","remarks")]), collapse = "|"))
    exists <- dbGetQuery(con, "SELECT record_id FROM NVGEOWEL_Records WHERE COALESCE(twn,'')=? AND COALESCE(rng,'')=? AND COALESCE(sec,'')=? AND COALESCE(permit,'')=? AND COALESCE(well_name,'')=? AND COALESCE(date_text,'')=? AND COALESCE(td_ft,-1)=?",
                         params = list(r$twn, r$rng, ifelse(is.na(r$sec), "", r$sec), ifelse(is.na(r$permit), "", r$permit), r$well_name, ifelse(is.na(r$date_text), "", r$date_text), ifelse(is.na(r$td_ft), -1, r$td_ft)))
    if (nrow(exists)) {
      # a later change in the 2019 staging (e.g. a held row resolved) updates the match, never a created well
      cur <- dbGetQuery(con, "SELECT disposition FROM NVGEOWEL_Records WHERE record_id = ?", params = list(exists$record_id[1]))$disposition
      if (grepl("^in_nbmg2019|^in_db_matched", cur) && !is.na(r$disposition) && !identical(cur, r$disposition) && grepl("^in_nbmg2019|^in_db_matched", r$disposition)) {
        dbExecute(con, "UPDATE NVGEOWEL_Records SET disposition = ?, matched_well_id = ?, nbmg_record_id = ?, match_method = ?, flags = ? WHERE record_id = ?",
                  params = list(r$disposition, r$matched_well_id, r$nbmg_record_id, r$match_method, r$flags, exists$record_id[1]))
        n_updated <- n_updated + 1L
      }
      next
    }
    loaded <- NA_integer_; disp <- r$disposition
    if (identical(disp, "candidate_new")) {
      if (!create_wells) { disp <- "candidate_new" } else {
        nm <- r$well_name; if (tolower(nm) %in% c("domestic", "domestic well") || nm %in% existing_names) nm <- paste0(nm, " (NVGEOWEL ", ifelse(is.na(r$permit), r$screenshot, r$permit), ", ", r$operator, ")")
        ll <- tryCatch(nvgeowel_qq_latlon(r$sec, r$twn, r$rng, r$qtrqtr), error = function(e) list(lat = NA_real_, lon = NA_real_, unc = NA_real_))
        has <- !is.na(ll$lat)
        role <- .role_from_class(r$status_class, r$status_class, nm); use <- .use_from_row("", r$status_class, r$status_class, nm, role)
        note <- sprintf("[NVGEOWEL 2009 list (Data_Sources %d), screenshot %s: operator %s; permit %s; status/class %s; TD %s ft; date %s; remarks %s. Location T%s R%s sec %s %s%s.]",
                        src["nvgeowel"], r$screenshot, r$operator, ifelse(is.na(r$permit), "none", r$permit), ifelse(is.na(r$status_class), "not given", r$status_class),
                        ifelse(is.na(r$td_ft), "not given", r$td_ft), ifelse(is.na(r$date_text), "not given", r$date_text), ifelse(is.na(r$remarks), "none", r$remarks),
                        r$twn, r$rng, ifelse(is.na(r$sec), "?", r$sec), ifelse(is.na(r$qtrqtr), "", r$qtrqtr),
                        if (has) paste0("; coordinate is the PLSS ", if (ll$unc == 400) "quarter-quarter" else "section", " centroid (about ", ll$unc, " m)") else "; no coordinate (BLM PLSS service not reachable)")
        dbExecute(con, "INSERT INTO Wells (well_name, well_role, latitude, longitude, coord_key, total_depth, coordinate_source, coordinate_uncertainty_m, notes, field_name, well_use, well_status_std) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                  params = list(nm, role, if (has) ll$lat else NA_real_, if (has) ll$lon else NA_real_, if (has) paste0(ll$lat, "_", ll$lon) else NA_character_, r$td_ft,
                                if (has) "plss_quarter_quarter_centroid_nvgeowel2009" else NA_character_, if (has) ll$unc else NA_real_, note, "Steamboat Springs", use, .status_std(r$status_class)))
        loaded <- dbGetQuery(con, "SELECT last_insert_rowid() id")$id; existing_names <- c(existing_names, nm)
        disp <- "created_well"; n_created <- n_created + 1L
      }
    }
    dbExecute(con, "INSERT INTO NVGEOWEL_Records (source_id, screenshot, twn, rng, sec, qtrqtr, county, permit, operator, well_name, date_text, status_class, td_ft, remarks,
                    match_method, nbmg_record_id, matched_well_id, disposition, loaded_well_id, flags, row_hash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
              params = list(src["nvgeowel"], r$screenshot, r$twn, r$rng, ifelse(is.na(r$sec), "", r$sec), r$qtrqtr, r$county, ifelse(is.na(r$permit), "", r$permit), r$operator, r$well_name,
                            ifelse(is.na(r$date_text), "", r$date_text), r$status_class, r$td_ft, r$remarks, r$match_method, r$nbmg_record_id, r$matched_well_id, disp, loaded, r$flags, h))
    n_stage <- n_stage + 1L
  }
  out <- x[, c("screenshot","twn","rng","sec","qtrqtr","permit","operator","well_name","date_text","status_class","td_ft","match_method","nbmg_record_id","matched_well_id","disposition","flags")]
  dir.create(dirname(review_csv), showWarnings = FALSE, recursive = TRUE); write_csv(out, review_csv)
  message(sprintf("  -> %d row(s) staged this run; %d well(s) created; %d existing row(s) re-matched", n_stage, n_created, n_updated))
  print(table(out$disposition))
  invisible(out)
}
