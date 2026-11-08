# ------------------------------------------------------------
# register_sbw0003_and_boyd_fix.R   (2026-11-07)
#
# 1. SBW_0001 is the unmarked, discharging abandoned well across the creek (east
#    bank, agricultural field, lower Cl); it is NOT the pipe that erupted next to
#    the fissure. Its note is corrected.
# 2. SBW_0003 is registered for the shallow pipe that erupted next to the Lower
#    Sinter Terrace fissure (June 2025). Its position is provisional (placed at the
#    SBF_0001 fissure point, +/-100 m) and its identity is open; candidate records
#    go into Well_Identity_Leads from data/raw/wells/sbw0003_identity_leads.csv.
# 3. Boyd:
#    - the 1955 Boyd well (NDWR log 2959) was placed at the centre of Sec 4 of the
#      wrong township (about 8 km north). Moved to the Collar Plate 3 Boyd points.
#    - the 1962 Boyd well (log 8188) is confirmed from the NDWR Well Log Details page
#      as SW1/4 NE1/4 Sec 33 T18N R20E, 56 ft, 6 in casing, perforated 32-52 ft,
#      static 19 ft, pumping 20 ft, 25 gpm, seal to 20 ft; its fields are filled. Its
#      link to the NDEP Boyd samples is flagged as doubtful.
# Fill-only where a value exists; notes carry a marker so a re-run changes nothing.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

.hav_m <- function(a, b, c, d) { p <- pi/180; x <- sin((c-a)*p/2)^2 + cos(a*p)*cos(c*p)*sin((d-b)*p/2)^2; 6371000*2*asin(sqrt(x)) }
.add_note <- function(con, table, id_col, id, marker, text) {
  n <- dbGetQuery(con, sprintf("SELECT notes FROM %s WHERE %s = ?", table, id_col), params = list(id))$notes
  if (length(n) == 1 && !grepl(marker, ifelse(is.na(n), "", n), fixed = TRUE))
    dbExecute(con, sprintf("UPDATE %s SET notes = TRIM(COALESCE(notes,'') || ?) WHERE %s = ?", table, id_col), params = list(paste0(" ", marker, " ", text), id))
}

register_sbw0003_and_boyd_fix <- function(con, leads_csv = "data/raw/wells/sbw0003_identity_leads.csv") {
  message("---- SBW_0003, SBW_0001 note, Boyd corrections ----")
  mk <- "[2026-11-07]"

  # 1. SBW_0001
  for (t in list(c("Wells", "well_name"), c("Locations", "name")))
    .add_note(con, t[1], t[2], "SBW_0001", mk, "Identity clarified: unmarked, discharging abandoned well across the creek (east bank, agricultural field), lower Cl than the fissure. It is not the pipe that erupted next to the fissure (see SBW_0003).")
  if (nrow(dbGetQuery(con, "SELECT 1 FROM Wells WHERE well_name='SBW_0001'")))
    dbExecute(con, "UPDATE Wells SET notes = REPLACE(notes, 'once the well identity (Busick property pipe / resort tank source well) is confirmed', 'once the well identity is confirmed') WHERE well_name='SBW_0001'")

  # 2. SBW_0003
  f <- dbGetQuery(con, "SELECT latitude, longitude FROM Locations WHERE name = 'SBF_0001'")
  if (nrow(f) == 1) {
    if (!nrow(dbGetQuery(con, "SELECT 1 FROM Locations WHERE name = 'SBW_0003'")))
      dbExecute(con, "INSERT INTO Locations (external_station_code, name, latitude, longitude, crs, site_type, coordinate_source, coordinate_uncertainty_m, notes) VALUES ('SBW_0003','SBW_0003',?,?,'EPSG:4326','well','assumed_adjacent_to_SBF_0001',100,?)",
                params = list(f$latitude, f$longitude, "Shallow pipe (about 15-20 m) that erupted next to the Lower Sinter Terrace fissure in June 2025; capped afterwards. Position provisional: placed at the SBF_0001 fissure point until the pipe is surveyed. Candidate identities are in Well_Identity_Leads."))
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = 'SBW_0003'")$location_id
    if (!nrow(dbGetQuery(con, "SELECT 1 FROM Wells WHERE well_name = 'SBW_0003'")))
      dbExecute(con, "INSERT INTO Wells (well_name, location_id, well_role, latitude, longitude, coordinate_source, coordinate_uncertainty_m, notes) VALUES ('SBW_0003',?,'unknown',?,?,'assumed_adjacent_to_SBF_0001',100,?)",
                params = list(loc, f$latitude, f$longitude, "Eruption pipe next to the fissure (June 2025). No log, depth or construction confirmed; see Well_Identity_Leads."))
    wid <- dbGetQuery(con, "SELECT well_id, latitude, longitude FROM Wells WHERE well_name='SBW_0003'")
    if (file.exists(leads_csv)) {
      L <- read.csv(leads_csv, stringsAsFactors = FALSE, na.strings = c("", "NA")); n_new <- 0L
      for (i in seq_len(nrow(L))) {
        d <- if (is.na(L$latitude[i])) NA_real_ else round(.hav_m(wid$latitude, wid$longitude, L$latitude[i], L$longitude[i]))
        n_new <- n_new + dbExecute(con, "INSERT OR IGNORE INTO Well_Identity_Leads (well_id, lead_source, lead_ref, lead_name, owner, completion_date, depth_ft, static_water_level_ft, diameter_in, location_basis, latitude, longitude, distance_m, rationale) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
          params = list(wid$well_id, L$lead_source[i], as.character(L$lead_ref[i]), L$lead_name[i], L$owner[i], as.character(L$completion_date[i]), L$depth_ft[i], L$static_water_level_ft[i], L$diameter_in[i], L$location_basis[i], L$latitude[i], L$longitude[i], d, L$rationale[i]))
      }
      message("  -> SBW_0003 registered; ", n_new, " new lead(s) in Well_Identity_Leads")
    }
  }

  # 3a. Boyd 1955 well (log 2959)
  p <- dbGetQuery(con, "SELECT AVG(latitude) la, AVG(longitude) lo FROM Locations WHERE name IN ('Boyd (plate 3 point 1)','Boyd (plate 3 point 2)')")
  b55 <- dbGetQuery(con, "SELECT well_id, latitude FROM Wells WHERE well_name LIKE 'Boyd Well 1955%'")
  if (nrow(b55) == 1 && !is.na(p$la) && !is.na(b55$latitude) && b55$latitude > 39.40) {
    dbExecute(con, "UPDATE Wells SET latitude=?, longitude=?, elevation_m=NULL, coordinate_source='collar1990_plate3_georeferenced', coordinate_uncertainty_m=60 WHERE well_id=?", params = list(p$la, p$lo, b55$well_id))
    dbExecute(con, "UPDATE Well_Log_Documents SET latitude=?, longitude=?, flags = COALESCE(flags,'') || ' | [2026-11-07] coordinate moved from the Sec 4 T18N centre (about 8 km north) to the Collar Plate 3 Boyd points' WHERE log_number = '2959'", params = list(p$la, p$lo))
    .add_note(con, "Wells", "well_id", b55$well_id, mk, "Coordinate corrected: NDWR lists T18N Sec 4 (39.46 N, about 8 km north), but Collar Plate 3, NBMG and the Rogers/Jeppson neighbours put the Boyd wells in Sec 4 of T17N (about 39.373 N), so the township is probably a typo. Position is the mean of the two Plate 3 Boyd points; elevation to be refreshed from 3DEP.")
  }

  # 3b. Boyd 1962 well (log 8188), from the NDWR Well Log Details page
  b62 <- dbGetQuery(con, "SELECT well_id, total_depth, top_perforation, bottom_perforation, diameter_in FROM Wells WHERE well_name = 'Boyd Domestic Well'")
  if (nrow(b62) == 1) {
    wid <- b62$well_id
    dbExecute(con, "UPDATE Wells SET total_depth = COALESCE(total_depth, 56), top_perforation = COALESCE(top_perforation, 32), bottom_perforation = COALESCE(bottom_perforation, 52), diameter_in = COALESCE(diameter_in, 6) WHERE well_id = ?", params = list(wid))
    dbExecute(con, "UPDATE Well_Log_Documents SET section = '33', cased_depth_ft = COALESCE(cased_depth_ft, 56), slot_from_ft = COALESCE(slot_from_ft, 32), slot_to_ft = COALESCE(slot_to_ft, 52), hole_diameter_in = COALESCE(hole_diameter_in, 6), flags = COALESCE(flags,'') || CASE WHEN COALESCE(flags,'') LIKE '%[2026-11-07]%' THEN '' ELSE ' | [2026-11-07] section confirmed as 33 (SW1/4 NE1/4) from the NDWR Well Log Details page' END WHERE log_number = '8188'")
    dbExecute(con, "INSERT OR IGNORE INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes) VALUES (?, '1962-03-01', 20, 'driller_report_pumping', 'driller_report', 'Pumping water level (bucket test, 25 gpm) from the NDWR Well Log Details page for log 8188.')", params = list(wid))
    .add_note(con, "Wells", "well_id", wid, mk, "NDWR Well Log Details (log 8188): SW1/4 NE1/4 Sec 33 T18N R20E, address STEAMBOAT NV, driller Reno Pump & Supply, started 1962-02-27, completed 1962-03-01 (received 1964-11-13), 56 ft, 6 in casing to 56 ft, perforated 32-52 ft, seal to 20 ft, static 19 ft, pumping 20 ft, 25 gpm. NDWR lat/lon (39.38325, -119.74) is a quarter-quarter point, not a surveyed well. LINK TO THE NDEP BOYD SAMPLES IS DOUBTFUL: those samples are cold and dilute (Cl 32-45 mg/L), unlike wells next to the fissure, and NBMG and Collar Plate 3 put the sampled Boyd wells about 1 km southwest.")
    .add_note(con, "Locations", "location_id", 151, mk, "Position is the NDWR quarter-quarter point for the 1962 Boyd well; whether the NDEP-sampled Boyd well is this well is doubtful (see Wells note).")
  }
  invisible(TRUE)
}
