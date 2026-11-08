# ------------------------------------------------------------
# cl_b_mixing_monitoring_wells.R
#
# Cl-B mixing plots for the current monitoring wells against older data from
# the same wells and nearby wells (Skalbeck 2001 Table B-2, Mariner & Janik
# 1995, NDEP PRR 2024-25), in the style of Skalbeck (2001) Fig. 6.
# Skalbeck read B falling below the thermal/dilute mixing line as B adsorption
# on alluvial clays; the index below (observed B / B on the mixing line at the
# same Cl) is 1 for conservative mixing, <1 for B retarded relative to Cl.
# Rows with a "<" qualifier or B <= 0 are excluded; suspect Cl values are listed
# in the returned object, not silently dropped.
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(dplyr); library(ggplot2)})
source("scripts/leapfrog/export_leapfrog_chemistry.R")  # .chem_date()

build_cl_b_mixing_figures <- function(con, out_dir = "output/figures/cl_b_mixing", suspect_cl = 1100) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  raw <- dbGetQuery(con, "SELECT l.name, s.data_source ds, s.collection_time ct, e.external_event_id eid, a.analyte, a.value, a.units, a.qualifier
    FROM Lab_Analyses a JOIN Samples s USING(sample_id) JOIN Locations l USING(location_id) LEFT JOIN Sampling_Events e ON e.event_id = s.event_id
    WHERE a.analyte IN ('Cl','B') AND a.value IS NOT NULL")
  # NDEP main export stores B (and some others) in ug/L; everything here is plotted in mg/L
  raw$value <- ifelse(grepl("^ug", raw$units, ignore.case = TRUE), raw$value / 1000, raw$value)
  raw <- raw[is.na(raw$qualifier) | raw$qualifier == "", ]
  raw$date <- .chem_date(raw$ct, raw$eid)
  wide <- raw |> filter(!is.na(date)) |> group_by(name, ds, date, analyte) |> summarise(v = mean(value), .groups = "drop") |>
    tidyr::pivot_wider(names_from = analyte, values_from = v) |> filter(!is.na(Cl), !is.na(B), B > 0)
  suspect <- wide |> filter(Cl > suspect_cl)
  wide <- wide |> filter(Cl <= suspect_cl)
  wide$well <- sub(" \\(Mariner.*$", "", wide$name)
  wide$well <- dplyr::recode(wide$well, "Herz Geothermal" = "Herz Geothermal (Skalbeck)", "Curti Barn Well (geothermal)" = "Curti Barn (geothermal)",
                             "Soccer Field Monitoring Well" = "Soccer Field", "Pine Tree Ranch-1" = "Pine Tree Ranch #1", "Peigh" = "Peigh Domestic",
                             "Herz Domestic Well" = "Herz Domestic", "Curti Domestic Well" = "Curti Domestic", "Boyd Domestic Well" = "Boyd",
                             "Jeppson Geothermal Well" = "Jeppson", "Rogers Domestic Well" = "Rogers", "Eich Well" = "Eich", "Herz Deep" = "Herz Deep")
  wide$era <- case_when(grepl("Skalbeck", wide$ds) ~ "Skalbeck 1985-98", grepl("Mariner", wide$ds) ~ "Mariner & Janik 1991-94",
                        grepl("NDEP", wide$ds) ~ "NDEP 2024-25", TRUE ~ "Other")
  wide$year <- as.numeric(format(wide$date, "%Y"))

  th <- wide |> filter(grepl("Mariner", ds), grepl("^(23-5|Cox|83A-6|PW|IW|GS-5)", well), Cl > 800)
  th_cl <- median(th$Cl); th_b <- median(th$B)
  dil_cl <- 7; dil_b <- 0.08
  line_b <- function(cl) dil_b + (th_b - dil_b) * (cl - dil_cl) / (th_cl - dil_cl)
  # The index is unstable where the mixing line is near zero, so only Cl >= 50 mg/L is scored
  wide$B_index <- ifelse(wide$Cl >= 50, wide$B / line_b(wide$Cl), NA_real_)

  panels <- list(
    "Herz Domestic: same well, 1985-2025" = c("Herz Domestic"),
    "Brown School and Curti Barn (thermal-mixed, near faults)" = c("Brown's School", "Curti Barn (geothermal)"),
    "Herz Geothermal (1985-89) and Herz Deep (2024-25)" = c("Herz Geothermal (Skalbeck)", "Herz Deep"),
    "Current thermal-influenced monitoring wells" = c("Eich", "NDOT", "Soccer Field"),
    "Dilute wells: current (Boyd, Jeppson, Rogers) and old (Peigh, Curti, Pine Tree, Flame)" =
      c("Boyd", "Jeppson", "Rogers", "Peigh Domestic", "Curti Domestic", "Pine Tree Ranch #1", "Flame"))
  pl <- bind_rows(lapply(names(panels), function(pn) { ids <- panels[[pn]]; wide[wide$well %in% ids, ] |> mutate(panel = pn) }))
  pl$panel <- factor(pl$panel, levels = names(panels))
  ctx <- wide |> select(Cl, B)

  g <- ggplot() +
    geom_point(data = ctx, aes(Cl, B), colour = "grey85", size = 0.8) +
    geom_segment(data = data.frame(x = dil_cl, y = dil_b, xend = th_cl, yend = th_b), aes(x = x, y = y, xend = xend, yend = yend), linetype = "dashed", colour = "grey35") +
    geom_point(data = data.frame(x = th_cl, y = th_b), aes(x, y), shape = 4, size = 3, stroke = 1.1) +
    geom_path(data = pl |> arrange(date), aes(Cl, B, colour = well, group = well), alpha = 0.35, linewidth = 0.3) +
    geom_point(data = pl, aes(Cl, B, colour = well, shape = era), size = 1.9, alpha = 0.85) +
    facet_wrap(~panel, ncol = 2, scales = "free") +
    labs(x = "Chloride (mg/L)", y = "Boron (mg/L)", colour = "Well", shape = "Source",
         title = "Chloride versus boron at monitoring wells, then and now",
         subtitle = sprintf("Dashed line: dilute water (Cl %g, B %g) to thermal reservoir median (Cl %.0f, B %.0f, X). Points below it: B retarded relative to Cl.", dil_cl, dil_b, th_cl, th_b),
         caption = "Grey: all other wells. Sources: Skalbeck (2001) Table B-2, Mariner & Janik (1995), NDEP public records request. Rows with a '<' qualifier and Cl above 1100 mg/L (possible OCR error) are excluded.") +
    theme_bw(base_size = 10) + theme(legend.position = "bottom", strip.text = element_text(face = "bold", size = 8))
  ggsave(file.path(out_dir, "cl_b_mixing_monitoring_wells.png"), g, width = 12, height = 11, dpi = 200)

  summ <- pl |> group_by(well, era) |> summarise(n = n(), years = paste(range(year), collapse = "-"), Cl_range = paste(round(range(Cl)), collapse = "-"),
                                                 B_range = paste(signif(range(B), 2), collapse = "-"), median_B_index = round(median(B_index, na.rm = TRUE), 2), .groups = "drop")
  write.csv(summ, file.path(out_dir, "cl_b_mixing_summary.csv"), row.names = FALSE)
  message("  -> ", file.path(out_dir, "cl_b_mixing_monitoring_wells.png"))
  invisible(list(summary = summ, suspect = suspect, thermal = c(Cl = th_cl, B = th_b), data = pl))
}
