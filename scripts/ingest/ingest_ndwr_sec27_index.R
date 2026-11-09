# ============================================================
# ingest_ndwr_sec27_index.R
#
# Stages the NDWR well logs of Washoe T18N R20E Section 27 (east of the Main and Low
# Terraces) from the Truckee Meadows basin table already on disk
# (data/raw/ndwr/TM_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm) in
# NDWR_WellLog_Index, and adds index-only wells, static water levels and work events.
#
# Rules
#  * Source: Data_Sources row for the NDWR Well Log Query; every log is staged verbatim.
#  * NDWR latitude/longitude are assigned from PLSS/parcel, not surveyed: many logs share
#    one coordinate. New wells carry coordinate_uncertainty_m = 800 and say so in notes.
#  * Logs that already have a Well_Log_Documents row (a PDF was ingested) are linked, not
#    duplicated.
#  * A repeated entry (same non-blank permit, same depth) is one well; a deepening (work
#    type D) by the same owner at the same coordinate as an earlier log is a work event on
#    that earlier log's well, with the deeper depth. Both are written to the note column.
#  * Static water level (ft below land surface at completion) goes to Water_Level_Observations
#    as method 'driller_report'; it is a single reading at drilling, not a head.
#  * Use and work-type codes are decoded from the NDWR Well Log Query legend.
#  * Idempotent (unique on log number).
# ============================================================
suppressPackageStartupMessages({library(DBI); library(rvest)})

.NDWR_USE <- c(A = "air_conditioning", Q = "aquaculture", B = "bottling", C = "commercial", Y = "desalination", D = "dewater", H = "domestic",
               F = "fire", N = "industrial", J = "industrial_cooling", T = "institution", I = "irrigation", M = "medicinal", K = "mining",
               G = "monitoring_well", Z = "other_see_remarks", E = "power", P = "municipal_public_supply", R = "recreation", S = "stock", X = "test_well", U = "unused")
.NDWR_WORK <- c(D = "deepen", G = "geothermal", N = "new", O = "other", P = "plug_or_abandonment", R = "recondition", S = "replacement_well", T = "test")
.NDWR_EVENT <- c(D = "deepening", G = "new", N = "new", O = "other", P = "abandonment", R = "reconstruction", S = "new", T = "other")

read_ndwr_welllog_table <- function(f) {
  t <- html_table(html_element(read_html(f), "table"), header = FALSE, fill = TRUE)
  hr <- which(apply(t, 1, function(r) any(grepl("Owner", r))))[1]
  h <- gsub("\\s+", " ", trimws(unlist(t[hr, ]))); d <- t[-(1:hr), ]
  names(d) <- make.unique(ifelse(h == "", "x", h)); d
}

ingest_ndwr_sec27_index <- function(con, table_html = "data/raw/ndwr/TM_NDWR_WellLogQuery_all_2026_05_31_files/sheet001.htm",
                                    twn = "18N", rng = "20E", sec = "27", review_csv = "data/derived/ndwr_sec27_cross_reference.csv") {
  message("---- NDWR well log index: T", twn, " R", rng, " Sec ", sec, " ----")
  if (!file.exists(table_html)) { message("  -> ", table_html, " not found; skipped"); return(invisible(NULL)) }
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, citation, url, notes) VALUES (?,?,?,?)",
            params = list(sprintf("NDWR Well Log Query (tools.water.nv.gov), Washoe T%s R%s Sec %s", twn, rng, sec),
                          "Nevada Division of Water Resources, Well Log Query (Well Driller's Reports index).", "https://tools.water.nv.gov/WellLogQuery.aspx",
                          "Rows come from the Truckee Meadows basin table saved 2026-05-31 and confirmed against a 2026-11-08 Section 27 query (34 logs). Latitude/longitude are assigned by NDWR from PLSS/parcel and are not surveyed."))
  sid <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ?", params = list(sprintf("NDWR Well Log Query (tools.water.nv.gov), Washoe T%s R%s Sec %s", twn, rng, sec)))$source_id
  d <- read_ndwr_welllog_table(table_html)
  d <- d[trimws(d$Twn) == twn & trimws(d$Rng) == rng & suppressWarnings(as.integer(d$Sec)) == as.integer(sec), ]
  num <- function(x) suppressWarnings(as.numeric(x))
  x <- data.frame(basin = d$Basin, log = trimws(d$Log), county = d$County, twn = twn, rng = rng, sec = sec, qq = trimws(d$`Qtr Qtr`),
                  owner = gsub("\\s+", " ", trimws(d$Owner)), comp = as.Date(d$`Comp Date`, format = "%m/%d/%Y"), lic = d$`Driller License No.`,
                  drill = trimws(d$`Driller Name`), depth = num(d$`Drill Depth`), swl = num(d$`Static Water Level`), cas = num(d$`Casing Diameter`),
                  wt = trimws(d$`Work Type`), use = trimws(d$`Prpsd Use`), permit = trimws(d$Permit), lat = num(d$latitude), lon = num(d$Longitude), stringsAsFactors = FALSE)
  x <- x[order(x$comp, as.numeric(x$log)), ]
  x$lat5 <- round(x$lat, 5); x$lon5 <- round(x$lon, 5)   # NDWR coordinates for one well can differ in the sixth decimal
  message("  -> ", nrow(x), " log(s) in the table for this section (the 2026-11-08 query showed 34)")
  x$cs <- ave(seq_len(nrow(x)), paste(x$lat5, x$lon5), FUN = length)
  docs <- dbGetQuery(con, "SELECT log_number, well_id FROM Well_Log_Documents WHERE well_id IS NOT NULL")
  existing <- dbGetQuery(con, "SELECT well_name FROM Wells")$well_name
  stat <- c(created = 0L, document = 0L, dup = 0L, deepen = 0L, wl = 0L, ev = 0L)
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    if (nrow(dbGetQuery(con, "SELECT 1 FROM NDWR_WellLog_Index WHERE log_number = ?", params = list(r$log)))) next
    disp <- NA_character_; wid <- NA_integer_; note <- NA_character_
    dd <- docs$well_id[docs$log_number == r$log]
    prior <- x[seq_len(i - 1), ]
    dupe <- prior[nzchar(r$permit) & prior$permit == r$permit & prior$depth == r$depth & prior$lat5 == r$lat5 & prior$lon5 == r$lon5, ]
    deep <- prior[identical(r$wt, "D") & prior$owner == r$owner & prior$lat5 == r$lat5 & prior$lon5 == r$lon5 & !is.na(prior$depth) & !is.na(r$depth) & prior$depth < r$depth, ]
    ref <- function(lg) dbGetQuery(con, "SELECT loaded_well_id w FROM NDWR_WellLog_Index WHERE log_number = ?", params = list(lg))$w[1]
    if (length(dd)) { disp <- "already_has_document_well"; wid <- dd[1]; stat["document"] <- stat["document"] + 1L
    } else if (nrow(dupe)) { wid <- ref(dupe$log[nrow(dupe)]); disp <- paste0("duplicate_of_log_", dupe$log[nrow(dupe)]); note <- "same permit, depth and coordinate as the earlier log: one well entered twice"; stat["dup"] <- stat["dup"] + 1L
    } else if (nrow(deep)) { wid <- ref(deep$log[nrow(deep)]); disp <- paste0("deepening_of_log_", deep$log[nrow(deep)]); note <- "work type D by the same owner at the same coordinate as the earlier log (probable same well, deepened)"; stat["deepen"] <- stat["deepen"] + 1L
      if (!is.na(wid)) dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ? AND (total_depth IS NULL OR total_depth < ?)", params = list(r$depth, wid, r$depth))
    } else {
      nm <- sprintf("NDWR Log %s (%s)", r$log, substr(r$owner, 1, 40)); if (nm %in% existing) nm <- paste0(nm, " [", r$log, "]")
      u <- unname(.NDWR_USE[r$use]); role <- if (identical(r$use, "H")) "domestic" else if (r$use %in% c("G", "X")) "monitor" else "unknown"
      wnote <- sprintf("[NDWR Well Log Query (Data_Sources %d): log %s, owner %s, completed %s, driller %s, drilled %s ft, static water level %s ft, casing %s in, work type %s, use %s, permit %s. Latitude/longitude assigned by NDWR from PLSS/parcel (shared by %d logs), not surveyed; stored with 800 m uncertainty.]",
                       sid, r$log, r$owner, ifelse(is.na(r$comp), "date not given", format(r$comp)), ifelse(nzchar(r$drill), r$drill, "not given"), ifelse(is.na(r$depth), "?", r$depth),
                       ifelse(is.na(r$swl), "not given", r$swl), ifelse(is.na(r$cas), "?", r$cas), ifelse(is.na(.NDWR_WORK[r$wt]), r$wt, .NDWR_WORK[r$wt]), ifelse(is.na(u), r$use, u), ifelse(nzchar(r$permit), r$permit, "none"), r$cs)
      has <- !is.na(r$lat) && !is.na(r$lon)
      dbExecute(con, "INSERT INTO Wells (well_name, well_role, latitude, longitude, coord_key, total_depth, coordinate_source, coordinate_uncertainty_m, notes, well_use, diameter_in) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                params = list(nm, role, if (has) r$lat else NA_real_, if (has) r$lon else NA_real_, if (has) paste0(r$lat, "_", r$lon) else NA_character_, r$depth,
                              if (has) "ndwr_welllog_query_assigned_latlon" else NA_character_, if (has) 800 else NA_real_, wnote, if (is.na(u)) "unknown" else u, r$cas))
      wid <- dbGetQuery(con, "SELECT last_insert_rowid() id")$id; existing <- c(existing, nm); disp <- "created_well"; stat["created"] <- stat["created"] + 1L
    }
    if (!is.na(wid) && !identical(disp, "already_has_document_well")) {
      if (!is.na(r$swl) && !is.na(r$comp)) {
        ts <- format(r$comp)
        if (!nrow(dbGetQuery(con, "SELECT 1 FROM Water_Level_Observations WHERE well_id = ? AND timestamp = ? AND method = 'driller_report'", params = list(wid, ts)))) {
          dbExecute(con, "INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes) VALUES (?,?,?,'driller_report','driller_report',?)",
                    params = list(wid, ts, r$swl, sprintf("Static water level (ft below land surface) at completion, NDWR well log #%s. Single reading at drilling, not a head.", r$log)))
          stat["wl"] <- stat["wl"] + 1L
        }
      }
      ev <- unname(.NDWR_EVENT[r$wt]); if (is.na(ev)) ev <- "other"
      dbExecute(con, "INSERT INTO Well_Work_Events (well_id, source_document_id, work_type, proposed_use, event_date, casing_diameter_in, notes) VALUES (?,NULL,?,?,?,?,?)",
                params = list(wid, ev, unname(.NDWR_USE[r$use]), if (is.na(r$comp)) NA_character_ else format(r$comp), r$cas, sprintf("NDWR well log #%s (index only, no PDF); work type %s", r$log, r$wt)))
      stat["ev"] <- stat["ev"] + 1L
    }
    dbExecute(con, "INSERT INTO NDWR_WellLog_Index (source_id, basin, log_number, county, twn, rng, sec, qtrqtr, owner, comp_date, driller_license, driller_name, drill_depth_ft, static_water_level_ft, casing_diameter_in,
                    work_type_code, work_type, proposed_use_code, proposed_use, permit, latitude, longitude, coord_shared_by, disposition, loaded_well_id, note) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
              params = list(sid, r$basin, r$log, r$county, r$twn, r$rng, r$sec, r$qq, r$owner, if (is.na(r$comp)) NA_character_ else format(r$comp), r$lic, r$drill, r$depth, r$swl, r$cas,
                            r$wt, unname(.NDWR_WORK[r$wt]), r$use, unname(.NDWR_USE[r$use]), r$permit, r$lat, r$lon, r$cs, disp, wid, note))
  }
  out <- dbGetQuery(con, "SELECT log_number, owner, comp_date, drill_depth_ft, static_water_level_ft, proposed_use, latitude, longitude, coord_shared_by, disposition, loaded_well_id FROM NDWR_WellLog_Index ORDER BY comp_date, log_number")
  dir.create(dirname(review_csv), showWarnings = FALSE, recursive = TRUE); utils::write.csv(out, review_csv, row.names = FALSE)
  message(sprintf("  -> created %d well(s); linked to existing document wells %d; duplicates %d; deepenings %d; water levels %d; work events %d",
                  stat["created"], stat["document"], stat["dup"], stat["deepen"], stat["wl"], stat["ev"]))
  invisible(out)
}
