# ============================================================
# register_trans_sierra_leads.R
#
# Records the NDWR Trans Sierra Water logs in Section 27 as candidate identities for the
# well Collar (1990) Plate 3 labels "Bianco (Trans Sierra 4)" (Wells 'Bianco'), in
# Well_Identity_Leads. Nothing asserts an identity (status stays 'unconfirmed').
#   - log 11246 (108 ft, 1970, permit 25499; log 17309 repeats it): close to the 110 ft
#     depth of Collar's own log for Bianco
#   - log 10947 (188 ft, permit 25891, no date): another Trans Sierra Water well
# What would confirm: a surveyed coordinate or the driller's log for the Bianco well.
# Needs NDWR_WellLog_Index (ingest_ndwr_sec27_index.R). Idempotent.
# ============================================================
suppressPackageStartupMessages(library(DBI))

register_trans_sierra_leads <- function(con) {
  message("---- Trans Sierra identity leads ----")
  if (!"NDWR_WellLog_Index" %in% dbListTables(con) || !"Well_Identity_Leads" %in% dbListTables(con)) { message("  -> tables missing; skipped"); return(invisible(0L)) }
  tgt <- dbGetQuery(con, "SELECT well_id, latitude, longitude, total_depth FROM Wells WHERE well_name = 'Bianco'")
  if (nrow(tgt) != 1) { message("  -> target well 'Bianco' not found (", nrow(tgt), " rows); skipped"); return(invisible(0L)) }
  ts <- dbGetQuery(con, "SELECT * FROM NDWR_WellLog_Index WHERE owner LIKE 'TRANS SIERRA%' AND disposition NOT LIKE 'duplicate_of%' ORDER BY log_number")
  hav <- function(la1, lo1, la2, lo2) { r <- 6371000; p <- pi / 180; a <- sin((la2 - la1) * p / 2)^2 + cos(la1 * p) * cos(la2 * p) * sin((lo2 - lo1) * p / 2)^2; 2 * r * asin(sqrt(a)) }
  n <- 0L
  for (i in seq_len(nrow(ts))) {
    r <- ts[i, ]
    why <- if (isTRUE(abs(r$drill_depth_ft - tgt$total_depth) <= 5))
      sprintf("Trans Sierra Water well, %s ft; close to the %s ft depth of Collar (1990)'s log for 'Bianco (Trans Sierra 4)'. The same entry appears again under another log number with the same permit.", r$drill_depth_ft, tgt$total_depth)
    else if (is.na(tgt$total_depth)) sprintf("Trans Sierra Water well, %s ft; the depth of the Bianco well is not on file in this database, so it cannot be compared (Collar 1990 gives 110 ft).", r$drill_depth_ft)
    else sprintf("Trans Sierra Water well, %s ft; does not match the %s ft depth of the Bianco log, so it is a candidate for another Trans Sierra well (Klein 2007 'Trans Sierra #3'), not for Bianco.", r$drill_depth_ft, tgt$total_depth)
    n <- n + dbExecute(con, "INSERT OR IGNORE INTO Well_Identity_Leads (well_id, lead_source, lead_ref, lead_name, owner, completion_date, depth_ft, static_water_level_ft, diameter_in, location_basis, latitude, longitude, distance_m, rationale, status)
                              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,'unconfirmed')",
      params = list(tgt$well_id, "ndwr_log", r$log_number, paste0("Trans Sierra Water well, NDWR log ", r$log_number), r$owner, r$comp_date, r$drill_depth_ft, r$static_water_level_ft, r$casing_diameter_in,
                    "NDWR-assigned PLSS/parcel lat/lon (about 800 m)", r$latitude, r$longitude, round(hav(tgt$latitude, tgt$longitude, r$latitude, r$longitude)), why))
  }
  message("  -> ", n, " new lead(s) for well 'Bianco' (", nrow(ts), " Trans Sierra Water well(s) in Section 27)")
  invisible(n)
}
