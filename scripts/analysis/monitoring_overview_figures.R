# Monitoring-well overview figures: chloride through time (literature vs new
# data), depth to water, and seasonal water-level pattern. Saves PNGs to
# output/figures/monitoring_overview/ and returns the plots.

suppressPackageStartupMessages({library(DBI); library(dplyr); library(ggplot2)})

.parse_any_date <- function(x, eid) {
  x <- as.character(x); num <- suppressWarnings(as.numeric(x))
  dnum <- as.Date(ifelse(!is.na(num) & num > 1e8, as.numeric(as.POSIXct(num, origin = "1970-01-01", tz = "UTC")) / 86400,
                         ifelse(!is.na(num), num + as.numeric(as.Date("1970-01-01")), NA)), origin = "1970-01-01")
  d3 <- as.Date(substr(x, 1, 10), format = "%Y-%m-%d"); d2 <- as.Date(sub(" .*", "", x), format = "%m/%d/%Y")
  d4 <- as.Date(sub(".*_(\\d{4}-\\d{2}-\\d{2}).*", "\\1", ifelse(grepl("_\\d{4}-\\d{2}-\\d{2}", eid), eid, NA)), format = "%Y-%m-%d")
  out <- d3; out[is.na(out)] <- d2[is.na(out)]; out[is.na(out)] <- d4[is.na(out)]; out[is.na(out)] <- dnum[is.na(out)]; out
}

build_monitoring_overview_figures <- function(con, out_dir = "output/figures/monitoring_overview") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  srcpal <- c("Skalbeck 2001" = "#0072B2", "Mariner & Janik 1995" = "#009E73", "Sorey & Colvard 1992" = "#CC79A7",
              "Nehring 1980 / White 1964-68" = "#999999", "Collar 1990" = "#E69F00",
              "NDEP (public records + portal)" = "#D55E00", "This project (FIELD)" = "#000000")
  cl <- dbGetQuery(con, "select l.name loc, s.collection_time ct, s.data_source ds, e.external_event_id eid, a.value cl
     from Lab_Analyses a join Samples s using(sample_id) join Locations l using(location_id)
     left join Sampling_Events e on e.event_id = s.event_id where a.analyte = 'Cl' and a.value is not null")
  cl$date <- .parse_any_date(cl$ct, cl$eid)
  cl$src <- dplyr::case_when(grepl("Skalbeck", cl$ds) ~ "Skalbeck 2001", grepl("Sorey", cl$ds) ~ "Sorey & Colvard 1992",
    grepl("Mariner", cl$ds) ~ "Mariner & Janik 1995", grepl("Nehring|White", cl$ds) ~ "Nehring 1980 / White 1964-68",
    grepl("Collar", cl$ds) ~ "Collar 1990", grepl("NDEP", cl$ds) ~ "NDEP (public records + portal)",
    cl$ds == "FIELD" ~ "This project (FIELD)", TRUE ~ cl$ds)
  grp <- function(l) dplyr::case_when(
    grepl("Herz Domestic", l) ~ "Herz Domestic Well", grepl("^Herz Geothermal$|^Herz [12]$", l) ~ "Herz geothermal wells (Herz 1/2)",
    l == "Herz Deep" ~ "Herz Deep (NDEP)", grepl("^Peigh", l) ~ "Peigh", grepl("^Brown", l) ~ "Brown School", grepl("^Steinhardt", l) ~ "Steinhardt",
    grepl("^Curti Domestic", l) ~ "Curti Domestic", grepl("^Curti Barn", l) ~ "Curti Barn (geothermal)", grepl("^Flame", l) ~ "Flame",
    grepl("^Pine Tree", l) ~ "Pine Tree Ranch #1",
    l %in% c("Boyd Domestic Well", "Jeppson Geothermal Well", "Rogers Domestic Well", "Soccer Field Monitoring Well", "Eich Well", "NDOT") ~ l,
    l %in% c("Steamboat Creek @ Rhodes Road", "SBRR") ~ "Steamboat Creek at Rhodes Road (SBRR)", TRUE ~ NA_character_)
  lv <- c("Steamboat Creek at Rhodes Road (SBRR)", "Herz Domestic Well", "Herz geothermal wells (Herz 1/2)", "Herz Deep (NDEP)", "Curti Domestic",
          "Curti Barn (geothermal)", "Peigh", "Brown School", "Steinhardt", "Flame", "Pine Tree Ranch #1", "Boyd Domestic Well",
          "Jeppson Geothermal Well", "Rogers Domestic Well", "Soccer Field Monitoring Well", "Eich Well", "NDOT")
  cl$grp <- factor(grp(cl$loc), lv); pc <- cl[!is.na(cl$grp), ]; pc$src <- factor(pc$src, names(srcpal))
  pA <- ggplot(pc, aes(date, cl, color = src)) + geom_point(size = 1.1, alpha = 0.8) +
    geom_vline(xintercept = as.Date("2025-06-03"), linetype = "dashed", color = "grey40", linewidth = 0.3) +
    facet_wrap(~grp, scales = "free_y", ncol = 3, labeller = label_wrap_gen(28)) + scale_color_manual(NULL, values = srcpal, drop = TRUE) +
    labs(x = NULL, y = "Chloride (mg/L)", title = "Chloride through time at monitoring locations",
         subtitle = "Published values vs new data. Dashed line = June 2025 eruption.\nHerz Deep and the Herz geothermal wells are different wells (lead only).") +
    theme_minimal(base_size = 8) + theme(legend.position = "bottom")
  ggsave(file.path(out_dir, "chloride_through_time_by_well.png"), pA, width = 11, height = 11, dpi = 170)

  wl <- dbGetQuery(con, "select x.well_name, w.timestamp, w.depth_to_water, w.method, w.notes from Water_Level_Observations w join Wells x using(well_id)")
  wl$d <- as.Date(substr(wl$timestamp, 1, 10), format = "%Y-%m-%d"); nn <- suppressWarnings(as.numeric(wl$timestamp))
  wl$d[is.na(wl$d)] <- as.Date(as.POSIXct(nn[is.na(wl$d)], origin = "1970-01-01", tz = "UTC"))
  wl$ft <- ifelse(grepl("meters", wl$notes), wl$depth_to_water * 3.28084, wl$depth_to_water)
  wl <- wl[!is.na(wl$ft), ]
  wl$kind <- dplyr::case_when(grepl("Skalbeck", wl$method) ~ "Skalbeck 2001 (converted from m)", wl$method == "sounding_tape" ~ "NDEP U230 sounding tape",
    wl$method == "driller_report" ~ "Driller report (NDWR / Collar 1990 App. B)", wl$method == "F" ~ "STMGID transducer (daily)", wl$method == "digitized_figure" ~ "Digitized from Sorey & Colvard 1992 figure", TRUE ~ "other")
  gw <- function(n) dplyr::case_when(grepl("^Herz Domestic", n) ~ "Herz Domestic Well", n == "Herz Geothermal" ~ "Herz Geothermal (Skalbeck)", n == "Herz Deep" ~ "Herz Deep (NDEP)",
    n == "NDOT" ~ "NDOT", grepl("^Boyd well [(]Sorey", n) ~ "Boyd well (Sorey & Colvard 1992)", grepl("^Pine Tree", n) ~ "Pine Tree Ranch #1", grepl("^Steinhardt", n) ~ "Steinhardt", n %in% c("STMGID MW3", "STMGID MW10") ~ n, TRUE ~ NA_character_)
  w <- wl; w$grp <- gw(w$well_name); w <- w[!is.na(w$grp) & (w$kind != "other"), ]
  w$grp <- factor(w$grp, c("Herz Domestic Well", "Herz Geothermal (Skalbeck)", "Pine Tree Ranch #1", "Steinhardt", "Herz Deep (NDEP)", "NDOT", "Boyd well (Sorey & Colvard 1992)", "STMGID MW3", "STMGID MW10"))
  kp <- c("Skalbeck 2001 (converted from m)" = "#0072B2", "NDEP U230 sounding tape" = "#D55E00", "STMGID transducer (daily)" = "#009E73", "Driller report (NDWR / Collar 1990 App. B)" = "#E69F00", "Digitized from Sorey & Colvard 1992 figure" = "#CC79A7")
  pB <- ggplot(w, aes(d, ft, color = kind)) + geom_line(data = subset(w, kind != "Driller report (NDWR / Collar 1990 App. B)"), aes(group = interaction(grp, kind)), linewidth = 0.3, alpha = 0.6) + geom_point(size = 1) +
    facet_wrap(~grp, scales = "free", ncol = 2, labeller = label_wrap_gen(30)) + scale_y_reverse() + scale_color_manual(NULL, values = kp) +
    labs(x = NULL, y = "Depth to water (ft below ground; deeper downward)", title = "Depth to water at the monitoring wells",
         subtitle = "Free axes. Skalbeck values converted from meters. Amber = drilling-time level from a well log.") +
    theme_minimal(base_size = 8) + theme(legend.position = "bottom")
  ggsave(file.path(out_dir, "water_level_by_well.png"), pB, width = 10, height = 10, dpi = 170)

  # one panel for wells that only have a drilling-time level (mostly Collar 1990 App. B logs)
  dr <- wl[wl$kind == "Driller report (NDWR / Collar 1990 App. B)" & grepl("NDWR Log|Domestic|Geothermal|Bianco|Cox|Strat|Peigh|Curti|Boyd|Herz|Steinhardt", wl$well_name), ]
  pD <- ggplot(dr, aes(d, reorder(well_name, d))) + geom_point(aes(size = ft), color = "#E69F00", alpha = 0.8) +
    labs(x = "Year drilled", y = NULL, size = "Depth to water (ft)", title = "Drilling-time water levels from well logs (one per well)", subtitle = "Point size = depth to water; includes the Collar (1990) Appendix B logs") +
    theme_minimal(base_size = 7)
  ggsave(file.path(out_dir, "water_level_drilling_time.png"), pD, width = 9, height = 9, dpi = 170)

  sz <- w[w$grp %in% c("STMGID MW3", "STMGID MW10", "Herz Geothermal (Skalbeck)", "Pine Tree Ranch #1") & w$kind != "Driller report (NDWR / Collar 1990 App. B)", ]
  sz$mon <- as.integer(format(sz$d, "%m")); sz$yr <- as.integer(format(sz$d, "%Y"))
  sz <- sz |> group_by(grp, yr, mon) |> summarise(ft = mean(ft), .groups = "drop") |> group_by(grp) |> mutate(anom = ft - mean(ft))
  pC <- ggplot(sz, aes(mon, anom, group = yr, color = factor(yr))) + geom_line(linewidth = 0.5) + geom_point(size = 1) + scale_y_reverse() + scale_x_continuous(breaks = 1:12) +
    facet_wrap(~grp, scales = "free_y", ncol = 2) + labs(x = "Month", y = "Depth-to-water anomaly (ft; deeper downward)", color = "Year", title = "Seasonal pattern in depth to water",
      subtitle = "Monthly mean minus each well's own mean. Only wells with 2+ years of data.") + theme_minimal(base_size = 8) + theme(legend.position = "bottom")
  ggsave(file.path(out_dir, "water_level_seasonal.png"), pC, width = 9, height = 6, dpi = 170)
  invisible(list(chloride = pA, water_level = pB, drilling_time = pD, seasonal = pC))
}
