# Crosswalk between today's monitoring locations and the same or nearby sites
# in earlier work (Collar 1990, Sorey & Colvard 1992, White 1964/1968, Klein
# 2007, Skalbeck 2001, Mariner & Janik 1995).
#
# The matches are curated by hand (name, owner, depth, chemistry, literature
# statements); this script adds the on-file coordinates and the distance
# between the two records and writes two CSVs. It never merges ids or writes
# to the database.
#   data/raw/wells/historical_name_crosswalk.csv        (the curated table + distances)
#   data/derived/historical_crosswalk_report.csv        (same, ranked, for review)
#
# confidence: high = same name AND independent corroboration (position within
# the larger coordinate uncertainty, matching depth/chemistry, or an explicit
# statement in the literature); medium = name/owner match but position only
# to section level or farther than the stated uncertainty; lead = plausible,
# not established.

library(DBI); library(dplyr)

.xw_rows <- function() {
  tibble::tribble(
    ~cur_tbl, ~cur_id, ~hist_tbl, ~hist_id, ~historical_source, ~historical_name, ~relationship, ~confidence, ~evidence,
    "L", 78L, NA, NA, "Collar 1990 Table 4 / Plate 4", "S10 (Steamboat Creek at Rhodes Road)", "same point", "high",
      "Collar's S10 Cl 17.2 and 23.8 mg/L matches SBRR 17.1 mg/L; Plate 4 label is Rhodes Road, above the Steamboat Ditch inflow.",
    "L", 78L, "L", 10L, "NDEP StationData / Sorey & Spielman 2008", "Steamboat Creek @ Rhodes Road (SB5, SB6, STBT02Steamboat-2a)", "same point", "high",
      "Already grouped in Location_Aliases; all within about 150 m of SBRR and the USGS gage.",
    "L", 1L, "L", 12L, "NDEP SB7 / Sorey & Spielman 2008", "Steamboat Creek @ Geiger Grade", "same reach", "medium",
      "Sorey & Spielman call this reach 'Geiger Grade'; the NDEP SB7 point is a few hundred metres from the logger.",
    "L", 156L, NA, NA, "Collar 1990 Plate 3; Klein 2007; Skalbeck 2001; NDWR log 4061", "Herz Domestic Well", "same well", "high",
      "Same Location row already carries Klein, Skalbeck, Mariner & Janik and NDEP/U230 data; depth 110-112 ft matches the 1962 log.",
    "L", 252L, "L", 229L, "Collar 1990 Plate 3 (HERZ 1/2); White/Geyser Society digitization", "Herz 1", "possible same well", "lead",
      "Herz Deep (552 ft) has no coordinate; Herz 1 and 2 are the geothermal Herz wells about 380 m from the domestic well. Not established.",
    "L", 252L, "L", 230L, "Collar 1990 Plate 3 (HERZ 1/2); White/Geyser Society digitization", "Herz 2", "possible same well", "lead",
      "Same reasoning as Herz 1.",
    "L", 151L, NA, NA, "Collar 1990 Plate 3 (BOYD); Sorey & Colvard 1992 Table 3", "Boyd well", "same well", "medium",
      "Plate label BOYD; the 1962 domestic log 8188 sits at the same coordinate.",
    "L", 151L, "W", 284L, "Collar 1990 Appendix B log 2959", "Boyd Well 1955 (Sec 4)", "different well", "high",
      "A V D Boyd well drilled 1955 in Sec 4, several km north; not the same well as the 1962 Boyd domestic well.",
    "L", 152L, "W", 281L, "Collar 1990 Appendix B log 17004", "Jeppson Well (1977, Sec 8)", "possible same well", "medium",
      "Surname and area match; Wells row is a section centroid (800 m).",
    "L", 152L, "W", 282L, "Collar 1990 Appendix B log 8023", "Jeppson Well (1964, Sec 7)", "possible same well", "lead",
      "Older Jeppson log in the adjacent section.",
    "L", 153L, "W", 283L, "Collar 1990 Appendix B log 20142", "Rogers Well 1979 (Sec 7)", "possible same well", "lead",
      "Surname match; the NBMG point for the NDEP Rogers well is farther from the section centroid than the stated uncertainty.",
    "L", 150L, "W", 278L, "Collar 1990 Plate 3 (STMGID / OTTEN); Appendix B log 22455", "STMGID Well, Otten", "different well likely", "lead",
      "Collar's Otten well is 812 ft deep in Sec 30; STMGID MW3 (186-286 ft) is about 1 km away. Plate 3 would settle it.",
    "L", 148L, "W", 278L, "Collar 1990 Plate 3 (STMGID / OTTEN); Appendix B log 22455", "STMGID Well, Otten", "possible same well", "lead",
      "STMGID MW10 is deep (screened 220-700 ft); depth is comparable to the 812-ft Otten well but the location is about 1.5 km off.",
    "L", 76L, "W", 172L, "Collar 1990 Appendix B log 26097; White 1964/1968 'Steamboat well 4'", "Steamboat Spa production well", "possible same well", "lead",
      "Spa well (260 ft, 240 F, 1985) is about 145 m from the resort-tank sample; White's well 4 (225 ft) matches NBMG 'Steamboat No. 4' within 25 m of SBW_0002.",
    "W", 96L, NA, NA, "Collar 1990 Appendix B (strat 13); NDWR log 61248", "23-5 / Strat 13 next to 23-5", "same well", "high",
      "Log 61248 promoted to 23-5 (depth and owner match); Collar states strat 13 sits next to 23-5.",
    "W", 190L, NA, NA, "Collar 1990 Plate 3 (COX I-1); Sorey & Colvard 1992; NDWR log 22781", "Cox I-1 / Cox 1-1 / COX-1", "same well", "high",
      "Aliases already registered; NBMG name match plus Collar log.",
    "W", 192L, NA, NA, "Collar 1990 Plate 3; Sorey & Colvard 1992 Table 3; NDWR log 20363", "Steinhardt", "same well", "high",
      "Exact NBMG name match and the log is on file.",
    "W", 193L, NA, NA, "Collar 1990 Plate 3; Sorey & Colvard 1992 Table 3", "Brown School", "same well", "high",
      "Exact NBMG name match (Brown Elementary School).",
    "W", 194L, NA, NA, "Collar 1990 Plate 3 (BIANCO / TRANS SIERRA 4); NDWR log 5916", "Bianco", "same well", "medium",
      "Surname match only; depth in Collar's log (110 ft) does not match Sorey & Colvard Table 3 (400 ft).",
    "W", 274L, NA, NA, "Collar 1990 Plate 3 (MACKAY); Klein 2007 (Mackay Geoth/Dom)", "MacKay wells", "same site", "medium",
      "Two MacKay logs (1973, 303 ft; 1978, 110 ft) in Sec 29; position is the section centroid.",
    "W", 285L, "L", 159L, "Collar 1990 Appendix B log 13252; Plate 3 (CURTI)", "Curti Domestic Well (95 ft)", "different well", "medium",
      "A 77-ft Curti well (1973), not the 95-ft Curti domestic well on file; the section centroid is only a rough position.",
    "W", 285L, "L", 160L, "Collar 1990 Appendix B log 13252; Plate 3 (CURTI)", "Curti Barn Well (geothermal)", "different well", "medium",
      "The 77-ft domestic-use Curti log is not the 260-ft geothermal Curti barn well.",
    "L", 220L, NA, NA, "Sorey & Colvard 1992 Fig. 26 (Herz-2 geothermal well)", "Herz-2 (geothermal)", "same well", "high",
      "Fig. 26 shows chloride 325-375 mg/L and depth to water 49-53 ft from 1984-1990; Skalbeck Table B-2 Herz Geothermal has chloride 325-380 mg/L (n=48) and median depth about 51 ft over 1985-1989. Series match, not a row-by-row comparison.",
    "L", 151L, "W", 287L, "Sorey & Colvard 1992 Table 3 / Fig. 23 (Boyd well)", "Boyd well, 110 ft (digitized water levels)", "different or unconfirmed", "lead",
      "Sorey's Boyd well is 110 ft deep with water at 38-43 ft; the NDEP Boyd Domestic Well (NDWR log 8188) is 56 ft deep, and the 1955 Boyd well is 68 ft. Identity not established.")
}

build_historical_name_crosswalk <- function(con,
    out_raw = "data/raw/wells/historical_name_crosswalk.csv",
    out_report = "data/derived/historical_crosswalk_report.csv") {
  loc <- dbGetQuery(con, "SELECT 'L' tbl, location_id id, name, latitude, longitude, coordinate_uncertainty_m unc FROM Locations")
  wel <- dbGetQuery(con, "SELECT 'W' tbl, well_id id, well_name name, latitude, longitude, coordinate_uncertainty_m unc FROM Wells")
  pts <- bind_rows(loc, wel)
  hav <- function(la1, lo1, la2, lo2) 2 * 6371000 * asin(sqrt(sin((la2 - la1) * pi / 360)^2 + cos(la1 * pi / 180) * cos(la2 * pi / 180) * sin((lo2 - lo1) * pi / 360)^2))
  x <- .xw_rows() |>
    left_join(rename(pts, cur_tbl = tbl, cur_id = id, cur_name = name, cur_lat = latitude, cur_lon = longitude, cur_unc = unc), by = c("cur_tbl", "cur_id")) |>
    left_join(rename(pts, hist_tbl = tbl, hist_id = id, hist_db_name = name, hist_lat = latitude, hist_lon = longitude, hist_unc = unc), by = c("hist_tbl", "hist_id")) |>
    mutate(distance_m = round(hav(cur_lat, cur_lon, hist_lat, hist_lon)),
           uncertainty_m = pmax(cur_unc, hist_unc, na.rm = TRUE),
           position_check = case_when(
             is.na(distance_m) ~ "no second coordinate",
             distance_m <= pmax(uncertainty_m, 150, na.rm = TRUE) ~ "within uncertainty",
             TRUE ~ "farther than stated uncertainty"))
  out <- x |> select(confidence, relationship, cur_tbl, cur_id, cur_name, historical_source, historical_name,
                     hist_tbl, hist_id, hist_db_name, distance_m, uncertainty_m, position_check, evidence)
  dir.create(dirname(out_raw), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_report), showWarnings = FALSE, recursive = TRUE)
  write.csv(out, out_raw, row.names = FALSE)
  write.csv(out[order(factor(out$confidence, c("high", "medium", "lead")), out$cur_name), ], out_report, row.names = FALSE)
  message("  -> ", nrow(out), " crosswalk rows (", paste(names(table(out$confidence)), table(out$confidence), collapse = ", "), ")")
  invisible(out)
}
