# ------------------------------------------------------------
# apply_white_gs_hole_corrections.R
#
# Reconciles the USGS GS drill holes (White 1964, 1968) in Wells with the values stated in
# those papers. Hand-maintained input: data/raw/wells/white_gs_hole_corrections.csv.
#   - total_depth, elevation_m: set to the stated value when different
#   - latitude/longitude: replaced only when overwrite_coordinate is TRUE (the old value is
#     kept in notes), otherwise filled only when empty
#   - split_skalbeck_table3: a Skalbeck (2001) Table 3 well that shares the label (GS-6) is a
#     different, much deeper well; its depth and formation interval move to their own Wells row
# Also fixes two-digit-year NBMG dates that R read as 20xx (1950 stored as 2050).
# Idempotent: a second run changes nothing.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

.append_note <- function(old, new) if (is.na(old) || !nzchar(old)) new else if (grepl(substr(new, 1, 60), old, fixed = TRUE)) old else paste(old, new)

.SK_GS6_NOTE <- paste(
  "Skalbeck (2001) Table 3 row 38 (profile 29020; elevation 1534 m, 30 m to granodiorite, total depth 289 m, reference White et al., 1964).",
  "Labelled GS-6 in Table 3 but GS-8 in the Figure 5 legend. Its plotted position lies about 200 m from White's GS-6 on Plate 1 and about 1.4 km from GS-8,",
  "so it most likely is White's GS-6, but its values do not match that hole (White: 1474 m, granodiorite at 177 ft = 54 m, 212 ft = 65 m deep) and its 289 m",
  "total depth is identical to ST-9's, so the values look mis-keyed. No NDWR log or NBMG well in the area fits 289 m depth with granodiorite at 30 m.",
  "Do not use as GS-6's depth.")

# Skalbeck's own total depth for a Table 3 row (m -> ft); falls back to the given value.
# Reads the row's well_name_raw from the hand-entered Table 3 file; NA when the file or the row is missing.
.skalbeck_total_depth_ft <- function(well, fallback) {
  f <- "data/raw/historical/skalbeck2001_table3_well_control.csv"
  if (!file.exists(f)) return(fallback)
  d <- utils::read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)
  v <- suppressWarnings(as.numeric(d$total_depth_m[d$well_name_raw == well]))
  if (length(v) && !is.na(v[1])) round(v[1] / 0.3048, 4) else fallback
}

apply_white_gs_hole_corrections <- function(con, csv = "data/raw/wells/white_gs_hole_corrections.csv") {
  if (!file.exists(csv)) { message("[white_gs] ", csv, " not found; skipped"); return(invisible(NULL)) }
  x <- utils::read.csv(csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  n <- c(depth = 0, elev = 0, coord = 0, split = 0)
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    w <- dbGetQuery(con, "SELECT * FROM Wells WHERE well_name = ?", params = list(r$well_name))
    if (nrow(w) != 1) { warning("[white_gs] '", r$well_name, "' matched ", nrow(w), " Wells rows; skipped"); next }
    id <- w$well_id
    notes <- w$notes

    # Skalbeck Table 3 well with the same label: its depth and formation interval belong on their own row.
    # Triggers when that interval is attached to this well (a rebuilt database attaches it by name) or the notes carry Skalbeck's text.
    if (isTRUE(as.logical(r$split_skalbeck_table3))) {
      sk_name <- paste0(r$well_name, " (Skalbeck 2001 Table 3)")
      n_sk_lith <- dbGetQuery(con, "SELECT COUNT(*) n FROM Well_Lithology WHERE well_id = ? AND description LIKE '%Skalbeck 2001 Table 3%'", params = list(id))$n
      sk_in_notes <- !is.na(notes) && grepl("Skalbeck (2001) Table 3", notes, fixed = TRUE)
      if ((sk_in_notes || n_sk_lith > 0) && nrow(dbGetQuery(con, "SELECT 1 FROM Wells WHERE well_name = ?", params = list(sk_name))) == 0) {
        dbExecute(con, "INSERT INTO Wells (well_name, total_depth, well_role, notes) VALUES (?, ?, 'unknown', ?)",
                  params = list(sk_name, .skalbeck_total_depth_ft(r$well_name, w$total_depth), .SK_GS6_NOTE))
        new_id <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(sk_name))$well_id
        dbExecute(con, "UPDATE Well_Lithology SET well_id = ? WHERE well_id = ? AND description LIKE '%Skalbeck 2001 Table 3%'", params = list(new_id, id))
        if (sk_in_notes) { dbExecute(con, "UPDATE Wells SET notes = NULL WHERE well_id = ?", params = list(id)); notes <- NA_character_ }
        n["split"] <- n["split"] + 1
      }
    }

    # a rebuilt database can re-attach the Skalbeck formation interval to the USGS hole by name; move it back out
    if (isTRUE(as.logical(r$split_skalbeck_table3))) {
      sk <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(paste0(r$well_name, " (Skalbeck 2001 Table 3)")))
      if (nrow(sk) == 1) n["split"] <- n["split"] + dbExecute(con, "UPDATE Well_Lithology SET well_id = ? WHERE well_id = ? AND description LIKE '%Skalbeck 2001 Table 3%'", params = list(sk$well_id, id))
    }
    # depth and elevation
    if (!is.na(r$total_depth_ft) && (is.na(w$total_depth) || abs(w$total_depth - r$total_depth_ft) > 0.01) || isTRUE(n["split"] > 0 && !is.na(r$total_depth_ft) && r$well_name == "GS-6")) {
      cur <- dbGetQuery(con, "SELECT total_depth FROM Wells WHERE well_id = ?", params = list(id))$total_depth
      if (is.na(cur) || abs(cur - r$total_depth_ft) > 0.01) {
        dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ?", params = list(r$total_depth_ft, id))
        notes <- .append_note(notes, sprintf("[total_depth set to White's stated %.1f ft (was %s).]", r$total_depth_ft, ifelse(is.na(w$total_depth), "empty", sprintf("%.1f", w$total_depth))))
        n["depth"] <- n["depth"] + 1
      }
    }
    if (!is.na(r$elevation_m) && (is.na(w$elevation_m) || abs(w$elevation_m - r$elevation_m) > 0.05)) {
      dbExecute(con, "UPDATE Wells SET elevation_m = ? WHERE well_id = ?", params = list(r$elevation_m, id))
      notes <- .append_note(notes, sprintf("[elevation_m set to the stated surface altitude %.1f m (was %s).]", r$elevation_m, ifelse(is.na(w$elevation_m), "empty", sprintf("%.1f", w$elevation_m))))
      n["elev"] <- n["elev"] + 1
    }

    # coordinate
    if (!is.na(r$latitude) && !is.na(r$longitude)) {
      differs <- is.na(w$latitude) || abs(w$latitude - r$latitude) > 1e-5 || abs(w$longitude - r$longitude) > 1e-5
      if (differs && (is.na(w$latitude) || isTRUE(as.logical(r$overwrite_coordinate)))) {
        dbExecute(con, "UPDATE Wells SET latitude = ?, longitude = ?, coord_key = ?, coordinate_source = ?, coordinate_uncertainty_m = ? WHERE well_id = ?",
                  params = list(r$latitude, r$longitude, paste0(r$latitude, "_", r$longitude), r$coordinate_source, r$coordinate_uncertainty_m, id))
        notes <- .append_note(notes, sprintf("[Coordinate set from %s (was %s, %s).] %s", r$coordinate_source, w$latitude, w$longitude, ifelse(is.na(r$note), "", r$note)))
        n["coord"] <- n["coord"] + 1
      }
    }
    if (!identical(notes, w$notes)) dbExecute(con, "UPDATE Wells SET notes = ? WHERE well_id = ?", params = list(notes, id))
  }

  # record the identity finding on the separate Skalbeck row (also corrects a row created before the finding)
  dbExecute(con, "UPDATE Wells SET notes = ? WHERE well_name = 'GS-6 (Skalbeck 2001 Table 3)' AND (notes IS NULL OR notes NOT LIKE '%Figure 5 legend%')", params = list(.SK_GS6_NOTE))

  # two-digit years read as 20xx by R (1946-1968 -> 2046-2068)
  fixed <- 0
  for (col in c("spud_date", "completion_date")) {
    fixed <- fixed + dbExecute(con, sprintf(
      "UPDATE Wells SET %1$s = printf('%%04d', CAST(substr(%1$s, 1, 4) AS INTEGER) - 100) || substr(%1$s, 5)
       WHERE %1$s GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND %1$s > date('now')", col))
  }
  message(sprintf("[white_gs] depth %d, elevation %d, coordinate %d, Skalbeck split %d, future-dated NBMG dates fixed %d",
                  n["depth"], n["elev"], n["coord"], n["split"], fixed))
  invisible(n)
}
