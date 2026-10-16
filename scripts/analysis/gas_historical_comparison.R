# ============================================================
# gas_historical_comparison.R
#
# Purpose:
# Compares the new, real April 2026 Fischer/Ruprecht fissure gas
# samples (NV26-1/2/3, Gas_Analyses) against the only prior Steamboat-
# specific gas-chemistry numbers on file in this project's literature:
# Mariner & Janik (1995) Table 2, well 23-5, 4 dates 1991-1994
# (data/raw/historical/mariner_janik_1995_gas_table2.csv -- real,
# transcribed values, not estimated), and Nehring (1980) Table 6
# (data/raw/historical/nehring1980_gas_table6.csv -- real values, but
# only 2 of ~15 rows: most of that table is badly column-shifted/
# missing in the scanned source and was deliberately not transcribed
# rather than guessed at; see that CSV's own notes column). Neither
# source has He-isotope (R/Ra) data. Arehart, Coolbaugh & Poulson
# (2003) argue for a magmatic/mantle heat-source component at
# Steamboat from trace elements and gas geochemistry, but (checked
# directly against the PDF) report no numeric gas-composition or
# He-isotope table of their own -- it is cited here as interpretive
# context, not a quantitative comparison point.
#
# Also builds a direct same-point gas-vs-water comparison: NV26-1 is
# co-located (per ingest_fischer_gas_data.R's Location_Aliases link)
# with SBF_0001, which has a real, already-ingested water/isotope
# sample (sample_id 816, 2026-05-01, Cl=815 mg/L, d18O=-12.26 permil,
# dD=-113.7 permil).
#
# Neither Mariner & Janik nor Nehring report a He-isotope (R/Ra)
# value. The real, primary historical baseline for Steamboat He
# isotopes is Torgersen & Jenkins (1982, Geochimica et Cosmochimica
# Acta 46:739-748) -- Steamboat-specific, not just regional, and 25
# years earlier than the next source found (Kennedy & van Soest 2007,
# Science 318:1433-1436, a regional B&R study that names Steamboat as
# one of a handful of sites with R/Ra > 3 but gives no Steamboat-
# specific table value). Torgersen & Jenkins report real Rc/Ra for 4
# springs, water and gas phases (data/raw/historical/
# torgersen_jenkins_1982_he_isotopes.csv): 3.9-4.5 for water, 6.0 for
# the two gas samples the authors themselves call more reliable
# (Springs 6 and 10), and two low outliers (Spring 4 gas, no corrected
# value computed; Spring 24 gas, 1.1) that their own text flags as
# 'viewed with some scepticism' (possible air mixing/vent self-
# contamination). The new NV26 R/Ra values (5.6-6.0) land almost
# exactly on the two trusted 1982 gas values (6.0, 6.0) -- a real,
# specific ~44-year stability result for the gas-phase signature
# specifically, not just a vague regional consistency check.
# ============================================================

library(dplyr)
library(ggplot2)

source("scripts/analysis/plot_theme.R")
source("scripts/analysis/gas_air_correction.R")

#' Build the air-corrected-vs-historical gas-ratio comparison (CO2/N2,
#' H2S/CO2, N2/Ar, CH4/CO2) and write a figure + CSV. Includes both
#' historical comparison sources this project has real numbers for:
#' Mariner & Janik (1995, well 23-5) and Nehring (1980, two clean rows
#' from Table 6 -- see that CSV's own notes for why only two).
build_gas_historical_comparison <- function(
    con,
    historical_csv = "data/raw/historical/mariner_janik_1995_gas_table2.csv",
    nehring_csv = "data/raw/historical/nehring1980_gas_table6.csv",
    out_csv = "data/derived/gas_analysis/gas_ratio_historical_comparison.csv",
    out_png = "output/figures/gas_analysis/gas_ratio_historical_comparison.png") {

  new_raw <- DBI::dbGetQuery(con, "
    SELECT sample_label AS sample, collection_date AS date,
           co2_mol_pct AS CO2, h2s_mol_pct AS H2S, h2_mol_pct AS H2,
           ch4_mol_pct AS CH4, n2_mol_pct AS N2, ar_mol_pct AS Ar,
           data_quality_flag
    FROM Gas_Analyses
  ")
  if (nrow(new_raw) == 0) {
    message("[gas_historical_comparison] No Gas_Analyses rows found -- nothing to compare.")
    return(invisible(NULL))
  }
  new_raw$group <- "This project (Fischer/Ruprecht, Apr 2026)"
  new_raw$site <- new_raw$sample

  mj <- if (file.exists(historical_csv)) {
    h <- readr::read_csv(historical_csv, show_col_types = FALSE,
                          col_types = readr::cols(date = readr::col_character()))
    h$group <- "Mariner & Janik (1995), well 23-5"
    h$site <- "23-5"
    h$sample <- paste0("23-5_", h$date)
    h$data_quality_flag <- "ok"
    h
  } else {
    NULL
  }

  neh <- if (file.exists(nehring_csv)) {
    n <- readr::read_csv(nehring_csv, show_col_types = FALSE,
                          col_types = readr::cols(date = readr::col_character()))
    n$group <- "Nehring (1980), springs"
    n$sample <- paste0(n$site, "_", n$date)
    n$data_quality_flag <- "ok"
    n
  } else {
    NULL
  }

  combined <- bind_rows(
    new_raw |> select(sample, site, date, CO2, H2S, H2, CH4, N2, Ar, group, data_quality_flag),
    if (!is.null(mj)) mj |> select(sample, site, date, CO2, H2S, H2, CH4, N2, Ar, group, data_quality_flag) else NULL,
    if (!is.null(neh)) neh |> select(sample, site, date, CO2, H2S, H2, CH4, N2, Ar, group, data_quality_flag) else NULL
  ) |>
    mutate(
      `CO2/N2` = CO2 / N2,
      `H2S/CO2` = H2S / CO2,
      `N2/Ar` = N2 / Ar,
      `CH4/CO2` = CH4 / CO2
    )

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(combined, out_csv)
  message("[gas_historical_comparison] Wrote ", nrow(combined), " row(s) to ", out_csv)

  long <- combined |>
    tidyr::pivot_longer(cols = c(`CO2/N2`, `H2S/CO2`, `N2/Ar`, `CH4/CO2`),
                         names_to = "ratio", values_to = "value")

  p <- ggplot(long, aes(x = group, y = value, color = data_quality_flag)) +
    geom_jitter(width = 0.1, size = 2.5, alpha = 0.85) +
    facet_wrap(~ratio, scales = "free_y") +
    scale_y_log10() +
    scale_color_manual(values = c("ok" = "#0072B2", "air_contaminated_suspect" = "#D55E00"),
                        name = "Sample quality") +
    labs(x = NULL, y = "Ratio (log scale)",
         title = "Fissure gas ratios vs. Mariner & Janik (1995) and Nehring (1980)",
         subtitle = "NV26-2 flagged air-contaminated/possible-leak -- shown, not excluded") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.x = element_text(angle = 20, hjust = 1))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 6, dpi = 300)
  message("[gas_historical_comparison] Wrote ", out_png)

  invisible(list(data = combined, plot = p))
}

#' Direct same-point comparison: NV26-1 (gas) vs. SBF_0001 (real water/
#' isotope sample, sample_id 816, 2026-05-01). Different phases/units,
#' so this returns a small side-by-side tibble rather than a figure.
build_gas_water_fissure_comparison <- function(
    con,
    out_csv = "data/derived/gas_analysis/nv26_1_vs_sbf_0001_water.csv") {

  gas <- DBI::dbGetQuery(con, "SELECT * FROM Gas_Analyses WHERE sample_label = 'NV26-1'")
  water <- DBI::dbGetQuery(con, "
    SELECT s.sample_id, se.date, la.analyte, la.value, la.units
    FROM Samples s
    JOIN Sampling_Events se ON s.event_id = se.event_id
    LEFT JOIN Lab_Analyses la ON la.sample_id = s.sample_id
    WHERE s.external_sample_id LIKE 'SBF_0001%'
  ")
  iso <- DBI::dbGetQuery(con, "
    SELECT s.sample_id, ia.analyte, ia.value, ia.units
    FROM Samples s
    JOIN Isotope_Analyses ia ON ia.sample_id = s.sample_id
    WHERE s.external_sample_id LIKE 'SBF_0001%'
  ")

  if (nrow(gas) == 0) {
    message("[gas_historical_comparison] NV26-1 not found in Gas_Analyses -- nothing to compare.")
    return(invisible(NULL))
  }

  summary_tbl <- tibble::tibble(
    point = "Fissure (NV26-1 gas / SBF_0001 water, co-located)",
    gas_field_temp_C = gas$field_temp_c[1],
    gas_CO2_mol_pct = gas$co2_mol_pct[1],
    gas_H2S_mol_pct = gas$h2s_mol_pct[1],
    gas_d13C_permil = gas$d13c_permil[1],
    gas_He3_He4_R_Ra = gas$he3_he4_r_ra[1],
    water_Cl_mgL = if (nrow(water) > 0) water$value[which(water$analyte == "Cl")[1]] else NA_real_,
    water_d18O_permil = if (nrow(iso) > 0) iso$value[iso$analyte == "d18O"][1] else NA_real_,
    water_dD_permil = if (nrow(iso) > 0) iso$value[iso$analyte == "d2H"][1] else NA_real_
  )

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(summary_tbl, out_csv)
  message("[gas_historical_comparison] Wrote NV26-1-vs-SBF_0001 comparison to ", out_csv)
  invisible(summary_tbl)
}
#' Full gas (mol%) and water (mg/L) composition for the co-located
#' fissure point (NV26-1 / SBF_0001), as two tidy tibbles rather than
#' one wide row -- meant for direct display (e.g. knitr::kable()) in a
#' report or the Ruprecht outreach document, not for further
#' computation (see build_gas_water_fissure_comparison() for that).
get_gas_vs_water_tables <- function(con) {
  gas <- DBI::dbGetQuery(con, "
    SELECT co2_mol_pct AS CO2, n2_mol_pct AS N2, o2_mol_pct AS O2,
           h2s_mol_pct AS H2S, h2_mol_pct AS H2, ch4_mol_pct AS CH4,
           ar_mol_pct AS Ar, he_mol_pct AS He, co_mol_pct AS CO
    FROM Gas_Analyses WHERE sample_label = 'NV26-1'
  ")
  water <- DBI::dbGetQuery(con, "
    SELECT la.analyte, la.value, la.units
    FROM Samples s
    JOIN Lab_Analyses la ON la.sample_id = s.sample_id
    WHERE s.external_sample_id LIKE 'SBF_0001%' AND la.value IS NOT NULL
    ORDER BY la.value DESC
  ")

  gas_tbl <- if (nrow(gas) > 0) {
    tidyr::pivot_longer(gas, cols = everything(), names_to = "species", values_to = "mol_pct") |>
      dplyr::arrange(dplyr::desc(mol_pct))
  } else {
    tibble::tibble(species = character(), mol_pct = numeric())
  }

  water_tbl <- water |>
    dplyr::rename(analyte_mgL = value) |>
    dplyr::select(analyte, analyte_mgL, units)

  list(gas = gas_tbl, water = water_tbl)
}

#' Two-panel bar chart: gas composition (mol%, NV26-1) next to water
#' major-ion chemistry (mg/L, log scale, SBF_0001) for the same,
#' co-located fissure point -- a simple visual pairing of the two
#' phases sampled at (within GPS noise of) the same spot, not a
#' quantitative mixing calculation.
build_gas_vs_water_composition_figure <- function(
    con,
    out_png = "output/figures/gas_analysis/gas_vs_water_composition.png") {

  tbls <- get_gas_vs_water_tables(con)
  if (nrow(tbls$gas) == 0 || nrow(tbls$water) == 0) {
    message("[gas_historical_comparison] Missing gas or water data for NV26-1/SBF_0001 -- skipping composition figure.")
    return(invisible(NULL))
  }

  p_gas <- ggplot(tbls$gas, aes(x = reorder(species, mol_pct), y = mol_pct)) +
    geom_col(fill = "#D55E00") +
    coord_flip() +
    labs(x = NULL, y = "mol %", title = "A. Gas (NV26-1)") +
    theme_steamboat(base_size = 11)

  p_water <- ggplot(tbls$water, aes(x = reorder(analyte, analyte_mgL), y = analyte_mgL)) +
    geom_col(fill = "#0072B2") +
    coord_flip() +
    scale_y_log10() +
    labs(x = NULL, y = "mg/L (log scale)", title = "B. Water (SBF_0001)") +
    theme_steamboat(base_size = 11)

  p <- patchwork::wrap_plots(p_gas, p_water, ncol = 2) +
    patchwork::plot_annotation(
      title = "Gas and water composition at the same fissure point",
      caption = "Two different phases, two different sampling dates (Apr 29 and May 1, 2026) at the same general location -- shown side by side, not combined into one scale."
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 5, dpi = 300)
  message("[gas_historical_comparison] Wrote ", out_png)
  invisible(p)
}
#' Convert ternary (3-part, sum-to-100) proportions to 2D Cartesian
#' coordinates for plotting with plain ggplot2 (no ggtern dependency).
#' Corner order: a = bottom-left, b = bottom-right, c = top.
.ternary_xy <- function(a, b, c) {
  total <- a + b + c
  x <- 0.5 * (2 * b + c) / total
  y <- (sqrt(3) / 2) * c / total
  tibble::tibble(x = x, y = y)
}

#' N2-He-Ar ternary (Giggenbach-style) diagram, the classic air/
#' crustal/mantle gas-discrimination plot used in Mariner & Janik's own
#' Figure 9 -- built here with the real data this project has (NV26-1/
#' 2/3, raw/uncorrected composition since the point of this diagram is
#' to show the air-mixing trend itself; Mariner & Janik 1995 well 23-5;
#' Nehring 1980's two clean rows), plus a real dry-air reference point.
#' Axes follow the common convention of scaling He by 100x and Ar by
#' 10x before normalizing, since He and Ar are both minor relative to
#' N2 -- this is a standard presentation choice, not a claim about
#' these specific gases' reactivity. The exact corner/field
#' conventions (where "air," "crustal," and "mantle" fields actually
#' sit) are not redrawn here since this project has not independently
#' verified them against a primary Giggenbach reference -- see the
#' note in the Ruprecht outreach document asking for a check on this.
build_gas_ternary_diagram <- function(
    con,
    historical_csv = "data/raw/historical/mariner_janik_1995_gas_table2.csv",
    nehring_csv = "data/raw/historical/nehring1980_gas_table6.csv",
    out_png = "output/figures/gas_analysis/gas_ternary_n2_he_ar.png") {

  new_raw <- DBI::dbGetQuery(con, "
    SELECT sample_label AS sample, he_mol_pct AS He, n2_mol_pct AS N2,
           ar_mol_pct AS Ar, data_quality_flag
    FROM Gas_Analyses
  ")
  if (nrow(new_raw) == 0) {
    message("[gas_historical_comparison] No Gas_Analyses rows found -- nothing to plot.")
    return(invisible(NULL))
  }
  new_raw$group <- "This project (Fischer/Ruprecht, Apr 2026)"

  mj <- if (file.exists(historical_csv)) {
    h <- readr::read_csv(historical_csv, show_col_types = FALSE,
                          col_types = readr::cols(date = readr::col_character()))
    h$sample <- paste0("23-5_", h$date)
    h$group <- "Mariner & Janik (1995), well 23-5"
    h$data_quality_flag <- "ok"
    h |> select(sample, He, N2, Ar, group, data_quality_flag)
  } else NULL

  neh <- if (file.exists(nehring_csv)) {
    n <- readr::read_csv(nehring_csv, show_col_types = FALSE,
                          col_types = readr::cols(date = readr::col_character()))
    n$sample <- paste0(n$site, "_", n$date)
    n$group <- "Nehring (1980), springs"
    n$data_quality_flag <- "ok"
    n |> select(sample, He, N2, Ar, group, data_quality_flag)
  } else NULL

  air <- tibble::tibble(sample = "Air (dry, reference)", He = 0.000524, N2 = 78.08,
                         Ar = 0.934, group = "Reference", data_quality_flag = "ok")

  combined <- bind_rows(
    new_raw |> select(sample, He, N2, Ar, group, data_quality_flag),
    mj, neh, air
  ) |>
    mutate(He_s = He * 100, N2_s = N2, Ar_s = Ar * 10)

  xy <- .ternary_xy(combined$He_s, combined$Ar_s, combined$N2_s)
  combined <- bind_cols(combined, xy)

  triangle <- tibble::tibble(
    x = c(0, 1, 0.5, 0), y = c(0, 0, sqrt(3) / 2, 0)
  )
  corner_labels <- tibble::tibble(
    x = c(0, 1, 0.5), y = c(-0.04, -0.04, sqrt(3) / 2 + 0.03),
    label = c("He x100", "Ar x10", "N2")
  )

  p <- ggplot(combined, aes(x = x, y = y)) +
    geom_path(data = triangle, color = "grey40") +
    geom_point(aes(color = group, shape = data_quality_flag), size = 3) +
    ggrepel::geom_text_repel(aes(label = sample), size = 2.5, max.overlaps = 20, seed = 719) +
    geom_text(data = corner_labels, aes(x = x, y = y, label = label),
              inherit.aes = FALSE, fontface = "bold", size = 3.5) +
    scale_shape_manual(values = c("ok" = 16, "air_contaminated_suspect" = 4), name = "Sample quality") +
    coord_equal() +
    labs(color = NULL,
         title = "N2-He-Ar ternary diagram (Giggenbach-style)",
         subtitle = "Raw (uncorrected) composition -- real dry air plotted for reference") +
    theme_steamboat(base_size = 11) +
    theme(axis.title = element_blank(), axis.text = element_blank(),
          axis.ticks = element_blank(), panel.grid = element_blank())

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 8, height = 7, dpi = 300)
  message("[gas_historical_comparison] Wrote ", out_png)
  invisible(list(data = combined, plot = p))
}
#' Build a simple before/after figure for the real
#' run_phreeqc_gas_phase_fischer_pairing() result: pH and the three
#' carbonate saturation indices (Calcite/Aragonite/Dolomite), the only
#' parameters with a real (non -999.999-sentinel) value on both sides.
build_gas_phase_pairing_figure <- function(
    before_after_csv = "data/derived/gas_analysis/gas_phase_fischer_pairing_before_after.csv",
    out_png = "output/figures/gas_analysis/gas_phase_fischer_pairing_before_after.png") {

  if (!file.exists(before_after_csv)) {
    message("[gas_historical_comparison] ", before_after_csv, " not found -- run run_phreeqc_gas_phase_fischer_pairing() first.")
    return(invisible(NULL))
  }
  d <- readr::read_csv(before_after_csv, show_col_types = FALSE) |>
    filter(!is.na(delta)) |>
    tidyr::pivot_longer(cols = c(before_no_gas_phase, after_real_gas_phase),
                         names_to = "state", values_to = "value") |>
    mutate(state = recode(state,
      before_no_gas_phase = "Before (water alone)",
      after_real_gas_phase = "After (equilibrated with real NV26-1 gas)"
    ))

  p <- ggplot(d, aes(x = parameter, y = value, fill = state)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6) +
    geom_hline(yintercept = 0, color = "grey40") +
    scale_fill_manual(values = c("Before (water alone)" = "#0072B2",
                                  "After (equilibrated with real NV26-1 gas)" = "#D55E00"),
                       name = NULL) +
    labs(x = NULL, y = "pH or saturation index",
         title = "SBF_0001 water re-equilibrated against NV26-1's real gas composition",
         subtitle = "Carbonate minerals shift from supersaturated to undersaturated; pH drops ~2 units") +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "bottom")

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 7.5, height = 5.5, dpi = 300)
  message("[gas_historical_comparison] Wrote ", out_png)
  invisible(p)
}
#' Build the He-isotope (Rc/Ra) historical comparison: the new NV26
#' samples against the real, Steamboat-specific 1982 baseline
#' (Torgersen & Jenkins, Table 5 -- 4 springs, water and gas phases,
#' Rc/Ra 3.7-6.1, their own text flags two anomalous gas values as
#' "viewed with some scepticism"). This is the primary historical
#' comparison -- it is Steamboat-specific and 25 years earlier than
#' Kennedy & van Soest (2007), which is regional (not Steamboat-
#' specific) and is kept as a secondary corroborating point only.
#'
#' A second panel is added showing the real 2026 analog of the same
#' "gas reads differently than water" pattern Torgersen & Jenkins'
#' own water-vs-gas He split already shows for 1982: no dissolved-gas/
#' He measurement exists for the 2026 water sample (SBF_0001), so this
#' is NOT a literal He-isotope comparison -- it is the real temperature
#' geothermometer comparison (D'Amore-Panichi gas vs. Na/K and quartz/
#' chalcedony water) at the one real co-located 2026 point (NV26-1 gas
#' / SBF_0001 water), shown on its own axis rather than forced onto the
#' Rc/Ra scale. This gap (no 2026 water He datum) is stated explicitly,
#' not papered over.
build_he_isotope_historical_comparison <- function(
    con,
    torgersen_csv = "data/raw/historical/torgersen_jenkins_1982_he_isotopes.csv",
    out_csv = "data/derived/gas_analysis/he_isotope_historical_comparison.csv",
    out_png = "output/figures/gas_analysis/he_isotope_historical_comparison.png") {

  new_raw <- DBI::dbGetQuery(con, "
    SELECT sample_label AS sample, he3_he4_r_ra AS rc_ra, data_quality_flag
    FROM Gas_Analyses
  ")
  if (nrow(new_raw) == 0) {
    message("[gas_historical_comparison] No Gas_Analyses rows found -- nothing to compare.")
    return(invisible(NULL))
  }
  new_raw$group <- "This project (Fischer/Ruprecht, Apr 2026)"
  new_raw$flag <- ifelse(new_raw$data_quality_flag == "ok", "ok", "skeptical")
  new_raw <- new_raw |> select(sample, rc_ra, group, flag)

  tj <- if (file.exists(torgersen_csv)) {
    t <- readr::read_csv(torgersen_csv, show_col_types = FALSE)
    t$sample <- paste0("Spring ", t$spring, " (", t$phase, ")")
    t$group <- "Torgersen & Jenkins (1982)"
    t |> select(sample, rc_ra, group, flag)
  } else NULL

  combined <- bind_rows(new_raw, tj)

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(combined, out_csv)
  message("[gas_historical_comparison] Wrote ", nrow(combined), " row(s) to ", out_csv)

  p_he <- ggplot(combined |> filter(!is.na(rc_ra)), aes(x = group, y = rc_ra, color = flag)) +
    geom_jitter(width = 0.1, size = 3, alpha = 0.85) +
    ggrepel::geom_text_repel(aes(label = sample), size = 2.6, max.overlaps = 20, seed = 331) +
    scale_color_manual(values = c("ok" = "#0072B2", "skeptical" = "#D55E00"), name = "Sample quality") +
    labs(x = NULL, y = "Rc/Ra (He-3/He-4)",
         title = "A. He isotopes: 1982 water vs. gas, and 2026 gas",
         subtitle = "1982 gas > 1982 water at every spring; 2026 has gas only (no water He datum)") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.x = element_text(angle = 15, hjust = 1), legend.position = "bottom")

  source("scripts/analysis/geothermometer_water_gas_comparison.R", local = TRUE)
  fissure_tbl <- build_geothermometer_fissure_point_table(con)

  p_geotherm <- if (!is.null(fissure_tbl) && nrow(fissure_tbl) > 0) {
    ggplot(fissure_tbl, aes(x = reorder(method, estimated_temp_C), y = estimated_temp_C, fill = basis)) +
      geom_col(width = 0.6) +
      geom_hline(aes(yintercept = measured_temp_C), linetype = "dashed", color = "grey40") +
      coord_flip() +
      scale_fill_manual(values = c("gas (NV26-1)" = "#D55E00", "water (SBF_0001)" = "#0072B2"), name = NULL) +
      labs(x = NULL, y = "Estimated temperature (C)",
           title = "B. 2026 analog: gas vs. water geothermometers",
           subtitle = "Same real co-located point (NV26-1/SBF_0001); dashed line = measured temperature") +
      theme_steamboat(base_size = 11) +
      theme(legend.position = "bottom")
  } else NULL

  p <- if (!is.null(p_geotherm)) {
    patchwork::wrap_plots(p_he, p_geotherm, ncol = 2)
  } else {
    p_he
  }

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = if (!is.null(p_geotherm)) 13 else 8, height = 6, dpi = 300)
  message("[gas_historical_comparison] Wrote ", out_png)
  invisible(list(data = combined, plot = p))
}