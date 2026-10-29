# ============================================================
# historical_comparison_collar1990.R
#
# Old-vs-recent comparison built from Collar (1990, M.S. thesis, San
# Diego State University, "Causes for the decline of hot spring and
# geyser activity, Steamboat Springs, Nevada") and the sources it
# compiles. Everything quoted from the thesis was read from the page
# images (Table 3 = thesis p. 152; Table 4 = pp. 322-323), not just the
# OCR text layer, which scrambles both tables.
#
#   build_collar_discharge_table(con)      -> table + CSV
#   build_collar_creek_chloride_figure(con) -> figure
#   build_collar_cl_flux_check()            -> re-runs the chloride flux
#       arithmetic on Collar's own Table 4 stations (same-date S10 vs S77)
#
# Reach caveat that must travel with every number: Collar's totals split
# Steamboat Creek into (a) "geothermal area", upstream of Virginia City
# Highway (Geiger Grade), and (b) "South Truckee Meadows", downstream of
# it to Huffaker Hills. Our SBRR -> SBBV flux difference spans Rhodes
# Road to Bella Vista (lat 39.466); Collar's reach ends at Huffaker Hills
# (stations S80/S90, Plate 4). The two are close in extent but not
# identical, so the series is a comparison of method, not an exact
# like-for-like time series.
# ============================================================

suppressPackageStartupMessages({
  library(DBI); library(dplyr); library(ggplot2)
})
source("scripts/analysis/plot_theme.R")

.GPM_TO_LS <- 0.0630902

.parse_any_date_cmp <- function(x) {
  x <- as.character(x)
  out <- rep(NA_character_, length(x))
  iso <- grepl("^\\d{4}-\\d{2}-\\d{2}", x); out[iso] <- substr(x[iso], 1, 10)
  n <- suppressWarnings(as.numeric(x))
  ed <- !iso & !is.na(n) & n < 40000
  out[ed] <- as.character(as.Date(n[ed], origin = "1970-01-01"))
  us <- is.na(out) & grepl("^\\d{1,2}/\\d{1,2}/\\d{4}", x)
  out[us] <- as.character(as.Date(sub(" .*$", "", x[us]), format = "%m/%d/%Y"))
  as.Date(out)
}

#' Thermal-water discharge to Steamboat Creek, 1955-2026, with the
#' definition and comparability caveat of each value.
build_collar_discharge_table <- function(con,
    out_csv = "data/derived/historical_comparison/thermal_discharge_1955_2026.csv") {
  source("scripts/analysis/chloride_mass_balance.R", local = TRUE)
  cmb <- compute_chloride_mass_balance(con)
  live_ls <- cmb$mean_Q_TW_Ls

  # `basis`: "creek inflow only" (thermal water entering Steamboat Creek, wells
  # excluded) vs "total incl. wells". Only creek-inflow rows are comparable
  # with the SBRR-SBBV mass balance; White 1955 creek-only = 325 + 485 = 810 gpm.
  tbl <- tibble::tribble(
    ~source, ~date, ~basis, ~gpm_low, ~gpm_high, ~method, ~definition_and_caveat,
    "White (1968), via Collar Table 3", "1955-04", "creek inflow only", 810, 810, "Cl mass balance (820 / 4 mg/L)",
      "325 (main/low terrace area, upstream of Geiger Grade) + 485 (downstream to Huffaker Hills). With wells (315) the total is 1125 (thesis text: 1130).",
    "White (1968), via Collar Table 3", "1964-04", "total incl. wells", 1385, 1385, "Cl mass balance",
      "Total only; Table 3 gives no breakdown, so not comparable with creek-inflow rows.",
    "Shump (1985), via Collar", "1981-82", "creek inflow only", 1300, 1300, "Specific conductivity",
      "SC-based. Collar states a revised SC estimate using nonthermal SC consistent with White's nonthermal Cl is much greater, because SC and Cl are not directly related in the carbonate/bicarbonate nonthermal groundwater.",
    "Collar (1990) Table 3", "1988-06", "creek inflow only", 490, 530, "Cl mass balance (820 / 4 mg/L), reach sums",
      "160-190 (geothermal area) + 330-340 (South Truckee Meadows). Wells (210-405 gpm at 20 C) excluded; thesis total with wells 700-935. Irrigation diversions complicate this survey.",
    "Collar (1990) Table 3", "1988-08", "creek inflow only", 150, 150, "Cl mass balance",
      "Geothermal-area reach only; no downstream value reported (partial, not a total).",
    "Collar (1990) Table 3", "1989-03", "creek inflow only", 660, 660, "Cl mass balance, reach sums",
      "230 + 430; irrigation had ceased (cleanest survey). Total with wells 870-1065.",
    "Sorey and Spielman (2008)", "2007-08", "creek inflow only", 730, 1214, "Cl mass balance at SBRR and SBBV",
      "Range as reported.",
    "Sorey and Spielman (2017)", "2008-2016", "creek inflow only", 45 / .GPM_TO_LS, 90 / .GPM_TO_LS, "Cl mass balance at SBRR and SBBV",
      "Reported as 60 L/s average, 45-90 L/s range across 24 events (converted here).",
    "Irvin and Lindsey (2026 poster)", "post-eruption", "creek inflow only", 27 / .GPM_TO_LS, 27 / .GPM_TO_LS, "Cl mass balance at SBRR and SBBV",
      "Multi-date average on the poster.",
    "This project (database)", "2026-05-01", "creek inflow only", live_ls / .GPM_TO_LS, live_ls / .GPM_TO_LS, "Cl flux difference SBBV - SBRR / 820 mg/L",
      "Single paired date; no nonthermal Cl term and no tributary/diversion correction. In Collar's cleanest survey (3/89) the same two-station arithmetic gives about 23 percent less than his reach-sum, so this method likely reads low."
  ) |>
    mutate(Ls_low = gpm_low * .GPM_TO_LS, Ls_high = gpm_high * .GPM_TO_LS,
           gpm_low = round(gpm_low), gpm_high = round(gpm_high),
           Ls_low = round(Ls_low, 1), Ls_high = round(Ls_high, 1))

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(tbl, out_csv, row.names = FALSE)
  message("  -> Wrote ", out_csv)
  tbl
}

#' Re-run the chloride-flux arithmetic on Collar's own data, same date:
#' S10 (Rhodes Road, upstream of the Steamboat Ditch inflow) vs S77 (the
#' downstream-most main-creek station sampled 3/4/89). Both a
#' flux-difference version (our poster formula) and Collar's two-end-member
#' version, for comparison.
build_collar_cl_flux_check <- function(
    csv = "data/raw/historical/collar1990_table4_stream_chemistry.csv") {
  d <- read.csv(csv, stringsAsFactors = FALSE)
  a <- d[d$station == "S10" & d$date == "1989-03-04", ]
  b <- d[d$station == "S77" & d$date == "1989-03-04", ]
  Cth <- 820; Cnt <- 4
  flux_diff_cfs <- (b$discharge_cfs * b$chloride_mg_l - a$discharge_cfs * a$chloride_mg_l) / Cth
  two_em_cfs <- (b$discharge_cfs - a$discharge_cfs) * 0 +
    (b$discharge_cfs * (b$chloride_mg_l - Cnt) - a$discharge_cfs * (a$chloride_mg_l - Cnt)) / (Cth - Cnt)
  data.frame(
    date = "1989-03-04", upstream = "S10", downstream = "S77",
    Q_up_cfs = a$discharge_cfs, Cl_up = a$chloride_mg_l,
    Q_down_cfs = b$discharge_cfs, Cl_down = b$chloride_mg_l,
    thermal_flux_diff_Ls = round(flux_diff_cfs * 28.3168, 1),
    thermal_flux_diff_gpm = round(flux_diff_cfs * 448.831),
    thermal_two_endmember_Ls = round(two_em_cfs * 28.3168, 1),
    thermal_two_endmember_gpm = round(two_em_cfs * 448.831)
  )
}

#' Chloride at the two logger-site reaches: Collar's 1988-89 stations
#' vs NDEP and this project. Station-to-site matching is from Plate 4
#' (S10 = Rhodes Road, immediately upstream of the Steamboat Ditch inflow
#' at S20; S70 = nearest main-creek station to the Virginia City Highway
#' crossing / Geiger Grade). The S70 match is provisional until Plate 4
#' is georeferenced.
build_collar_creek_chloride_figure <- function(con,
    csv = "data/raw/historical/collar1990_table4_stream_chemistry.csv",
    out_png = "output/figures/manuscript/collar_creek_chloride_comparison.png") {

  ndep <- dbGetQuery(con, "
    SELECT l.name, s.data_source, COALESCE(se.date, s.collection_time) AS d, la.value AS cl
    FROM Lab_Analyses la
    JOIN Samples s ON la.sample_id = s.sample_id
    LEFT JOIN Sampling_Events se ON s.event_id = se.event_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE la.analyte = 'Cl' AND l.name IN
      ('Steamboat Creek @ Rhodes Road', 'Steamboat Creek @ Geiger Grade', 'SBRR')")
  ndep$date <- .parse_any_date_cmp(ndep$d)
  ndep$reach <- ifelse(grepl("Geiger", ndep$name), "Geiger Grade reach", "Rhodes Road reach")
  ndep$source <- ifelse(ndep$data_source == "FIELD", "This project (SBRR, 2026)", "NDEP")
  ndep <- ndep[!is.na(ndep$date) & !is.na(ndep$cl), c("reach", "source", "date", "cl")]

  col <- read.csv(csv, stringsAsFactors = FALSE)
  col <- col[col$station %in% c("S10", "S70") & !is.na(col$chloride_mg_l), ]
  col$date <- as.Date(col$date)
  col$reach <- ifelse(col$station == "S10", "Rhodes Road reach", "Geiger Grade reach")
  col$source <- paste0("Collar (1990), station ", col$station)
  col <- col[, c("reach", "source", "date", "chloride_mg_l")]; names(col)[4] <- "cl"

  all <- rbind(ndep, col)
  all$source <- factor(all$source, levels = c(
    "Collar (1990), station S10", "Collar (1990), station S70", "NDEP", "This project (SBRR, 2026)"))

  p <- ggplot(all, aes(date, cl, color = source, shape = source)) +
    geom_point(data = subset(all, source == "NDEP"), size = 1.2, alpha = 0.55) +
    geom_point(data = subset(all, source != "NDEP"), size = 3) +
    facet_wrap(~ reach, scales = "free_y", ncol = 1) +
    scale_color_manual(values = c("Collar (1990), station S10" = "#D55E00",
                                   "Collar (1990), station S70" = "#D55E00",
                                   "NDEP" = "grey35",
                                   "This project (SBRR, 2026)" = "#0072B2"), drop = TRUE) +
    scale_shape_manual(values = c("Collar (1990), station S10" = 17,
                                   "Collar (1990), station S70" = 18,
                                   "NDEP" = 16, "This project (SBRR, 2026)" = 15), drop = TRUE) +
    labs(x = NULL, y = "Chloride (mg/L)", color = NULL, shape = NULL,
         title = "Steamboat Creek chloride at the two logger reaches, 1988 to 2026",
         subtitle = "Collar's S10 (Rhodes Road) and S70 (nearest to Geiger Grade, provisional) against NDEP and this project",
         caption = paste0("Collar (1990) Table 4: S10 17.2 and 23.8 mg/L (8/88, 3/89); S70 139, 418, 130 mg/L (6/88, 8/88, 3/89).\n",
                          "S70 discharge was only 0.1-3.7 cfs, so it may sit on a thermal side channel; matching to Geiger Grade awaits Plate 4 georeferencing.")) +
    theme_steamboat() + theme(legend.position = "bottom")

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 8.5, height = 7, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}
