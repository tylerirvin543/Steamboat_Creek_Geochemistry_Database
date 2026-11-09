# ============================================================
# proposal_data_figures.R
#
# Builds two items for the thesis proposal:
#   build_data_sources_table(con)               table of data sources and their resolution
#                                               (data/derived/proposal_tables/data_sources_resolution.csv)
#   build_data_availability_schedule_figure(con) data on file (1950-2026) and the planned field and
#                                               analysis schedule (2025-2027), data_availability_schedule.png
#
# Counts and date ranges are read from the operational database so the table cannot drift from the data.
# ============================================================
library(DBI); library(dplyr); library(ggplot2); library(patchwork)
source("scripts/analysis/data_availability.R")

.pdf_cfg <- list(csv = "data/derived/proposal_tables/data_sources_resolution.csv", fig_dir = "output/figures/manuscript",
                 today = as.Date("2026-11-08"))

.fmt_n <- function(x) format(as.integer(x), big.mark = ",")

build_data_sources_table <- function(con, cfg = .pdf_cfg) {
  q1 <- function(sql) tryCatch(dbGetQuery(con, sql), error = function(e) data.frame())
  yr <- function(x) format(as.Date(x), "%Y")
  # continuous records
  ec <- q1("SELECT COUNT(*) n, MIN(timestamp) mn, MAX(timestamp) mx FROM Conductivity_Observations")
  tt <- q1("SELECT COUNT(*) n, COUNT(DISTINCT logger_id) k, MIN(CAST(timestamp AS INTEGER)) mn, MAX(CAST(timestamp AS INTEGER)) mx FROM Temperature_Observations")
  tmin <- as.Date(as.POSIXct(tt$mn, origin = "1970-01-01", tz = "UTC")); tmax <- as.Date(as.POSIXct(tt$mx, origin = "1970-01-01", tz = "UTC"))
  us <- q1("SELECT COUNT(*) n, MIN(datetime) mn, MAX(datetime) mx FROM USGS_Timeseries WHERE parameter_code = '60'")
  # chemistry by source group (event dates parsed with the mixed-format helper)
  sm <- q1("SELECT s.data_source, s.external_event_id, e.date FROM Samples s JOIN Sampling_Events e ON e.event_id = s.event_id")
  sm$d <- .parse_mixed_event_date(sm$date, sm$external_event_id)
  grp <- function(pat) { z <- sm[grepl(pat, sm$data_source) & !is.na(sm$d), ]; c(n = nrow(z), a = yr(min(z$d)), b = yr(max(z$d))) }
  ndep <- grp("^NDEP"); fld <- grp("^FIELD$"); lit <- grp("Mariner|Skalbeck|Sorey|White|Klein|Collar")
  iso <- q1("SELECT COUNT(*) n, COUNT(DISTINCT sample_id) s FROM Isotope_Analyses")
  wl <- q1("SELECT COUNT(*) n, MIN(timestamp) mn, MAX(timestamp) mx FROM Water_Level_Observations")
  cnt <- q1("SELECT (SELECT COUNT(*) FROM Locations) loc, (SELECT COUNT(*) FROM Wells) wells, (SELECT COUNT(*) FROM Well_Log_Documents) logs,
                    (SELECT COUNT(*) FROM Fissure_Traces) fiss, (SELECT COUNT(*) FROM Fault_Traces) flt, (SELECT COUNT(*) FROM NDOM_Well_Records) ndom,
                    (SELECT COUNT(*) FROM Spring_Observations) spr, (SELECT COUNT(*) FROM Gas_Analyses) gas, (SELECT COUNT(*) FROM Thermal_Areas) ta")
  wx <- q1("SELECT parameter, COUNT(*) n, MIN(date) mn, MAX(date) mx FROM Weather_Observations GROUP BY parameter")
  eq <- q1("SELECT COUNT(*) n, MIN(event_time) mn, MAX(event_time) mx FROM Earthquake_Events")
  prcp <- wx[wx$parameter == "PRCP", ]; mslp <- wx[wx$parameter == "MSLP", ]

  tab <- data.frame(
    Source = c("Specific-conductance loggers (HOBO U24-002-C), SBRR and SBGG",
               "Temperature loggers (Elitech), springs, fumaroles, wells and the resort tank",
               "USGS stream gauges on Steamboat Creek",
               "NDEP monitoring chemistry and public-records forms",
               "Project field samples, spring and well chemistry",
               "Stable isotopes (delta-18-O, delta-D)",
               "Fissure gas (Fischer and Ruprecht, UCSB)",
               "Literature chemistry (White, Sorey and Colvard, Mariner and Janik, Skalbeck, Collar)",
               "Water levels (NDWR, STMGID, field gauging)",
               "Wells, springs and permit records (NDWR, NBMG, NDOM, Collar well logs)",
               "Drone thermal-infrared surveys (NBMG)",
               "Thermal map used here (georeferenced layout export)",
               "Mapped fissures, faults and sinter outlines",
               "Digital elevation model (USGS 3DEP)",
               "Weather, barometric pressure and earthquakes (NOAA, USGS)"),
    `What is measured` = c("Conductivity and water temperature; specific conductance at 25 C computed",
               "Temperature of discharge and ground",
               "Discharge, 15-minute record",
               "Major ions, trace elements, field pH, temperature, conductance, water levels",
               "Major ions, trace elements, alkalinity, field parameters",
               "Oxygen and hydrogen isotope ratios",
               "Gas composition, helium and carbon isotopes",
               "Historical chemistry, discharge and well data compiled from the reports",
               "Depth to water, transducer and manual",
               "Location, depth, construction, lithology, status",
               "Surface temperature, calibrated to ground-control targets (July and October 2025)",
               "Surface temperature as a color ramp, 7 to 44 C, mapped to polygons at or above 30 C",
               "Fissure traces, fault traces, sinter-terrace outline, annotation outlines",
               "Ground surface elevation",
               "Daily precipitation, hourly sea-level pressure, earthquake catalog"),
    Resolution = c("5 minutes; 3% of reading or 50 uS/cm", "5 minutes; 0.3 C", "15 minutes", "Per sample", "Per sample",
                   "Per sample", "Per sample", "Per sample or monthly", "Daily to monthly", "Per well",
                   "7 cm thermal and 2 cm visible pixels; within 1.3 C of targets", "0.17 by 0.10 m pixels; ceiling 44 C",
                   "Digitized traces", "1 m cells", "Daily, hourly, per event"),
    Period = c(sprintf("%s to %s", format(as.Date(ec$mn), "%b %Y"), format(as.Date(ec$mx), "%b %Y")),
               sprintf("%s to %s", format(tmin, "%b %Y"), format(tmax, "%b %Y")),
               sprintf("%s to %s", format(as.Date(us$mn), "%b %Y"), format(as.Date(us$mx), "%b %Y")),
               sprintf("%s to %s", ndep["a"], ndep["b"]), sprintf("%s", fld["a"]), "1991 to 2026", "April 2026",
               sprintf("%s to %s", "1950", lit["b"]), sprintf("%s to %s", yr(wl$mn), yr(wl$mx)), "1946 to 2026",
               "July and October 2025", "2025 survey", "Digitized 2026 from published maps and imagery", "Current USGS release", sprintf("%s to 2026", yr(prcp$mn))),
    Amount = c(sprintf("%s readings, 2 sites", .fmt_n(ec$n)),
               sprintf("%s readings, %d sites", .fmt_n(tt$n), tt$k),
               sprintf("%s readings, 2 stations", .fmt_n(us$n)),
               sprintf("%s samples", .fmt_n(as.integer(ndep["n"]))),
               sprintf("%s samples", fld["n"]),
               sprintf("%d analyses, %d samples", iso$n, iso$s),
               sprintf("%d samples", cnt$gas),
               sprintf("%s samples", .fmt_n(as.integer(lit["n"]))),
               sprintf("%s observations", .fmt_n(wl$n)),
               sprintf("%d wells, %d locations, %d well logs, %d permits", cnt$wells, cnt$loc, cnt$logs, cnt$ndom),
               "About 67 acres, two flights",
               sprintf("%d polygons", cnt$ta),
               sprintf("%d fissure traces, %d faults", cnt$fiss, cnt$flt),
               "Six 1 m tiles",
               sprintf("%s daily precipitation, %s pressure readings, %d earthquakes", .fmt_n(prcp$n), .fmt_n(mslp$n), eq$n)),
    check.names = FALSE, stringsAsFactors = FALSE)
  tab$Role <- c("Chloride proxy, Monte Carlo test", "Thermal behavior of discharge points", "Discharge for the chloride balance",
                "Monitoring-network chemistry and baseline", "End-member characterization, PHREEQC", "Source and mixing tests",
                "Gas geothermometry, air-corrected", "Historical baselines and comparisons", "Hydraulic context",
                "Well identity, Leapfrog inputs", "Surface heat, calibration check", "Thermal areas, source attribution",
                "Alignment and 3-D model inputs", "Elevation of wells and points", "Context for water levels and temperature")
  dir.create(dirname(cfg$csv), recursive = TRUE, showWarnings = FALSE)
  write.csv(tab, cfg$csv, row.names = FALSE)
  invisible(tab)
}

# Markdown pipe table with chosen relative column widths (dash counts), for use in results = "asis" chunks
pipe_table <- function(df, widths, caption = NULL, id = NULL) {
  esc <- function(x) gsub("\\|", "/", as.character(x))
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(vapply(widths, function(w) strrep("-", w), ""), collapse = "|"), "|")
  rows <- apply(df, 1, function(r) paste0("| ", paste(esc(r), collapse = " | "), " |"))
  out <- c(hdr, sep, rows)
  if (!is.null(caption)) out <- c(out, "", sprintf(": %s%s", caption, if (is.null(id)) "" else sprintf(" {#%s}", id)))
  paste(out, collapse = "\n")
}

build_data_availability_schedule_figure <- function(con, cfg = .pdf_cfg) {
  av <- compute_data_availability(con) |> mutate(start = as.Date(start_date), end = as.Date(end_date))
  nm <- c("NOAA Weather Observations" = "NOAA weather and pressure", "Chemistry Sampling Events" = "Chemistry samples, all sources",
          "Water Level Observations" = "Water levels", "USGS Historic Specific Conductance (grab samples)" = "USGS historic conductance grab samples",
          "USGS Discharge (live, param 60)" = "USGS discharge, 15-minute record", "Temperature Logger Observations" = "Temperature loggers (11 sites)",
          "Conductivity Logger Observations" = "Conductivity loggers (SBRR, SBGG)")
  av$lane <- ifelse(av$source %in% names(nm), nm[av$source], av$source)
  past <- av |> mutate(group = case_when(category == "Continuous Logger" ~ "Continuous record", category == "Discrete / Event" ~ "Discrete samples and readings",
                                         TRUE ~ "External time series"))
  d <- as.Date
  plan <- data.frame(
    lane = c("Intensive calibration sampling (daily)", "Monthly chloride sampling, full annual cycle", "Storm and snowmelt event sampling",
             "Lower Terrace source sampling (quarterly)", "Repeat thermal surveys (if NBMG can fly)", "Resistivity lines (if access allows)",
             "Leapfrog model build", "Calibration fitting and seasonal residuals", "PHREEQC conservativeness and end-member analyses", "Thesis writing and defense"),
    start = d(c("2026-11-09", "2026-12-01", "2027-03-01", "2027-01-01", "2027-07-01", "2027-05-01", "2027-01-01", "2027-07-01", "2027-10-01", "2027-11-01")),
    end = d(c("2026-11-30", "2027-09-30", "2027-06-30", "2027-10-31", "2027-10-31", "2027-08-31", "2027-06-30", "2027-09-30", "2027-10-31", "2027-12-31")),
    group = c(rep("Planned field work", 5), "Planned, conditional", rep("Planned analysis", 4)), stringsAsFactors = FALSE)
  plan$group[5] <- "Planned, conditional"
  cols <- c("Continuous record" = "#0072B2", "Discrete samples and readings" = "#E69F00", "External time series" = "#009E73",
            "Planned field work" = "#CC79A7", "Planned analysis" = "#D55E00", "Planned, conditional" = "#999999")
  # Panel A: everything on file
  pa <- past |> arrange(start) |> mutate(lane = factor(lane, levels = rev(unique(lane))))
  gA <- ggplot(pa, aes(y = lane, colour = group)) +
    geom_segment(aes(x = start, xend = pmax(end, start + 200)), linewidth = 4, lineend = "butt") +
    geom_vline(xintercept = cfg$today, linetype = "dotted") +
    scale_colour_manual(values = cols, name = NULL, guide = "none") + scale_x_date(limits = c(d("1938-01-01"), d("2028-01-01")), breaks = seq(d("1940-01-01"), by = "10 years", length.out = 9), date_labels = "%Y") +
    labs(x = NULL, y = NULL, title = "A. Data on file, 1938 to 2026") + theme_minimal(base_size = 10)
  # Panel B: 2025-2027, data on file plus plan
  pb_data <- past |> filter(end >= d("2025-01-01")) |> mutate(start = pmax(start, d("2025-01-01")))
  pb <- bind_rows(pb_data |> select(lane, start, end, group), plan |> select(lane, start, end, group))
  pb$lane <- factor(pb$lane, levels = rev(unique(pb$lane)))
  gB <- ggplot(pb, aes(y = lane, colour = group)) +
    geom_segment(aes(x = start, xend = end, linetype = ifelse(group == "Planned, conditional", "dashed", "solid")), linewidth = 4, lineend = "butt") +
    scale_linetype_identity() +
    geom_vline(xintercept = cfg$today, linetype = "dotted") +
    annotate("text", x = cfg$today, y = Inf, label = " today", hjust = 0, vjust = 1.5, size = 3) +
    scale_colour_manual(values = cols, name = NULL) +
    scale_x_date(limits = c(d("2025-01-01"), d("2028-01-01")), date_breaks = "3 months", date_labels = "%b\n%Y") +
    labs(x = NULL, y = NULL, title = "B. Data on file and the planned schedule, 2025 to 2027") + theme_minimal(base_size = 10) + theme(legend.position = "bottom")
  p <- gA / gB + plot_layout(heights = c(1, 1.25))
  dir.create(cfg$fig_dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(file.path(cfg$fig_dir, "data_availability_schedule.png"), p, width = 10, height = 9.5, dpi = 140)
  invisible(list(past = past, plan = plan))
}
