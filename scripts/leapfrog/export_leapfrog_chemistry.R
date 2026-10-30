# ------------------------------------------------------------
# export_leapfrog_chemistry.R
#
# Leapfrog (Energy/Geo) interval and point tables for chemistry and water
# level, so well logs can be coloured by chloride, temperature, etc.
# Companion to export_leapfrog.R (collar/survey/lithology); HoleID = Wells.well_name.
#
# Outputs (output/leapfrog/):
#   chemistry_intervals_long.csv   HoleID, From, To (m below surface), Analyte,
#                                  Value, Units, SampleDate, Source, IntervalBasis, InCollar
#   chemistry_intervals_latest.csv most recent value per hole and analyte
#   chemistry_unplaced.csv         chemistry for wells with no screen or total depth
#   water_levels.csv               HoleID, Date, DepthToWater_m, Method, Source, InCollar
#
# IntervalBasis:
#   screen                         Wells.top/bottom_perforation known
#   open_to_total_depth_assumed    only total_depth known; the whole hole is used and
#                                  flagged, because the sampled depth is not documented
# A well is linked to chemistry through Wells.location_id. Exact-name links
# that were missing are listed in data/raw/wells/well_location_links.csv and
# applied (fill-only, never overwrite) by apply_well_location_links().
# ------------------------------------------------------------

suppressPackageStartupMessages({library(DBI); library(dplyr); library(readr)})
FT_TO_M_CHEM <- 0.3048

apply_well_location_links <- function(con, csv = "data/raw/wells/well_location_links.csv") {
  if (!file.exists(csv)) return(invisible(0L))
  l <- read.csv(csv, stringsAsFactors = FALSE); n <- 0L
  for (i in seq_len(nrow(l))) {
    taken <- dbGetQuery(con, "SELECT 1 FROM Wells WHERE location_id = ? AND well_id <> ?", params = list(l$location_id[i], l$well_id[i]))
    if (nrow(taken) > 0) next
    n <- n + dbExecute(con, "UPDATE Wells SET location_id = ? WHERE well_id = ? AND location_id IS NULL", params = list(l$location_id[i], l$well_id[i]))
  }
  message("  -> ", n, " Wells.location_id link(s) filled from ", csv)
  invisible(n)
}

.chem_date <- function(x, eid) {
  x <- as.character(x); num <- suppressWarnings(as.numeric(x))
  dnum <- as.Date(ifelse(!is.na(num) & num > 1e8, as.numeric(as.POSIXct(num, origin = "1970-01-01", tz = "UTC")) / 86400,
                         ifelse(!is.na(num), num + as.numeric(as.Date("1970-01-01")), NA)), origin = "1970-01-01")
  d3 <- as.Date(substr(x, 1, 10), format = "%Y-%m-%d"); d2 <- as.Date(sub(" .*", "", x), format = "%m/%d/%Y")
  d4 <- as.Date(sub(".*_(\\d{4}-\\d{2}-\\d{2}).*", "\\1", ifelse(grepl("_\\d{4}-\\d{2}-\\d{2}", eid), eid, NA)), format = "%Y-%m-%d")
  out <- d3; out[is.na(out)] <- d2[is.na(out)]; out[is.na(out)] <- d4[is.na(out)]; out[is.na(out)] <- dnum[is.na(out)]; out
}

export_leapfrog_chemistry_intervals <- function(con, out_dir = "output/leapfrog",
                                                 analytes = c("Cl", "Na", "SO4", "B")) {
  message("---- Exporting Leapfrog chemistry intervals and water levels ----")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  apply_well_location_links(con)

  wells <- dbGetQuery(con, "SELECT well_id, well_name, location_id, latitude, longitude, elevation_m, total_depth, top_perforation, bottom_perforation FROM Wells WHERE location_id IS NOT NULL")
  in_collar <- with(wells, !is.na(latitude) & !is.na(longitude) & !is.na(elevation_m) & !is.na(total_depth))
  wells$InCollar <- in_collar
  wells$basis <- ifelse(!is.na(wells$top_perforation) & !is.na(wells$bottom_perforation), "screen",
                 ifelse(!is.na(wells$total_depth), "open_to_total_depth_assumed", NA_character_))
  wells$From <- ifelse(wells$basis == "screen", pmin(wells$top_perforation, wells$bottom_perforation) * FT_TO_M_CHEM, ifelse(!is.na(wells$basis), 0, NA))
  wells$To <- ifelse(wells$basis == "screen", pmax(wells$top_perforation, wells$bottom_perforation) * FT_TO_M_CHEM, ifelse(!is.na(wells$basis), wells$total_depth * FT_TO_M_CHEM, NA))

  lab <- dbGetQuery(con, sprintf("SELECT s.location_id, s.collection_time ct, s.data_source ds, e.external_event_id eid, a.analyte, a.value, a.units
     FROM Lab_Analyses a JOIN Samples s USING(sample_id) LEFT JOIN Sampling_Events e ON e.event_id = s.event_id
     WHERE a.value IS NOT NULL AND (a.analyte IN (%s) OR a.analyte = 'temperature')", paste0("'", analytes, "'", collapse = ",")))
  fld <- dbGetQuery(con, "SELECT s.location_id, s.collection_time ct, s.data_source ds, e.external_event_id eid, f.parameter analyte, f.value, f.units
     FROM Field_Measurements f JOIN Samples s USING(sample_id) LEFT JOIN Sampling_Events e ON e.event_id = s.event_id WHERE f.parameter = 'temperature' AND f.value IS NOT NULL")
  chem <- bind_rows(lab, fld)
  chem$analyte[chem$analyte == "temperature"] <- "Temperature"
  chem$SampleDate <- .chem_date(chem$ct, chem$eid)
  chem <- chem[!is.na(chem$SampleDate), ]

  j <- inner_join(chem, wells, by = "location_id", relationship = "many-to-many")
  placed <- j[!is.na(j$basis), ]
  long <- placed |> transmute(HoleID = well_name, From = round(From, 2), To = round(To, 2), Analyte = analyte, Value = value, Units = units,
                              SampleDate = SampleDate, Source = ds, IntervalBasis = basis, InCollar = InCollar) |>
    distinct() |> arrange(HoleID, Analyte, SampleDate)
  write_csv(long, file.path(out_dir, "chemistry_intervals_long.csv"))
  latest <- long |> group_by(HoleID, Analyte) |> slice_max(SampleDate, n = 1, with_ties = FALSE) |> ungroup()
  write_csv(latest, file.path(out_dir, "chemistry_intervals_latest.csv"))
  unpl <- j[is.na(j$basis), ] |> transmute(HoleID = well_name, Analyte = analyte, Value = value, SampleDate = SampleDate, Source = ds) |> distinct()
  write_csv(unpl, file.path(out_dir, "chemistry_unplaced.csv"))

  wlv <- dbGetQuery(con, "SELECT x.well_name HoleID, w.timestamp, w.depth_to_water, w.method, w.notes, x.latitude, x.longitude, x.elevation_m, x.total_depth FROM Water_Level_Observations w JOIN Wells x USING(well_id) WHERE w.depth_to_water IS NOT NULL")
  wlv$Date <- .chem_date(wlv$timestamp, rep(NA, nrow(wlv)))
  wlv$DepthToWater_m <- round(ifelse(grepl("meters", wlv$notes), wlv$depth_to_water, wlv$depth_to_water * FT_TO_M_CHEM), 2)
  wlv$InCollar <- with(wlv, !is.na(latitude) & !is.na(longitude) & !is.na(elevation_m) & !is.na(total_depth))
  # Steamboat-area wells only; dense transducer/logger series (more than 366 readings per well) are reduced to monthly means
  wlv <- wlv[!is.na(wlv$Date) & wlv$InCollar & wlv$latitude > 39.30 & wlv$latitude < 39.50 & wlv$longitude > -119.85 & wlv$longitude < -119.65, ]
  wlv$Aggregation <- 'as_reported'
  dense <- names(which(table(wlv$HoleID) > 366))
  if (length(dense)) {
    agg <- wlv[wlv$HoleID %in% dense, ] |> mutate(Date = as.Date(format(Date, '%Y-%m-01'))) |> group_by(HoleID, Date, method) |>
      summarise(DepthToWater_m = round(mean(DepthToWater_m), 2), InCollar = first(InCollar), .groups = 'drop') |> mutate(Aggregation = 'monthly_mean')
    wlv <- bind_rows(wlv[!(wlv$HoleID %in% dense), c('HoleID','Date','DepthToWater_m','method','InCollar','Aggregation')], agg)
  }
  write_csv(wlv |> transmute(HoleID, Date, DepthToWater_m, Method = method, Aggregation, InCollar) |> arrange(HoleID, Date), file.path(out_dir, "water_levels.csv"))

  message("  -> chemistry_intervals_long.csv: ", nrow(long), " values at ", n_distinct(long$HoleID), " hole(s) (",
          n_distinct(long$HoleID[long$IntervalBasis == "screen"]), " with a screen interval; ",
          n_distinct(long$HoleID[long$InCollar]), " are also in collar.csv)")
  message("  -> chemistry_unplaced.csv: ", n_distinct(unpl$HoleID), " well(s) with chemistry but no screen or total depth")
  message("  -> water_levels.csv: ", nrow(wlv), " reading(s) at ", n_distinct(wlv$HoleID), " collar-ready hole(s)")
  invisible(list(long = long, latest = latest, unplaced = unpl, water_levels = wlv))
}
