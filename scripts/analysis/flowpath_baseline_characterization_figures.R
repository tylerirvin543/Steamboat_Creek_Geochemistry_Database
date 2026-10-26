# ============================================================
# flowpath_baseline_characterization_figures.R
#
# Purpose (added 2026-10-26, per explicit user direction that the
# PHREEQC mixing/reaction-path/geothermometer work on the Lower Sinter
# Terrace flowpath is a ONE-TIME, same-era BASELINE characterization --
# a demonstration of the modeling approach's capability, not an
# iterative refinement project -- these four figures interpret the
# real, already-successful runs on file. No new PHREEQC execution is
# performed here; everything is read from PHREEQC_Solutions,
# PHREEQC_Mixing_Fractions (mixing_run_id 6, fissure 816 + SBRR 819),
# and PHREEQC_Reaction_Path_Runs/Steps already in the database.
#
# Core method behind figures 1 and 4 (the "gain/loss" framework): for
# each real downgradient target, the real stored Cl-based mixing
# fraction f against the fissure(816)/SBRR(819) end-member pair
# (clamped to 1.0 for SBW_0002, which already exceeds the valid range --
# see Session 2026-10-25) gives a conservative-mixing PREDICTION for
# every other species: predicted = C_meteoric + f*(C_thermal -
# C_meteoric). The % difference between the real measured value and
# this prediction is the species' real gain (positive) or loss
# (negative) relative to perfectly conservative transport -- the same
# logic already used for Ca/Mg/Alkalinity in the forward REACTION-path
# titration (16_reaction_path_titration.R), generalized here to every
# major species across every real target in one comparison.
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(tidyr)

source("scripts/analysis/plot_theme.R")

.FLOWPATH_TARGETS <- c(821, 825, 820, 822, 815)
.FLOWPATH_FEATURE_TYPE <- c(
  `821` = "Well", `825` = "Spring", `820` = "Seep", `822` = "Spring",
  `815` = "Well (resort)", `818` = "Downstream creek"
)
.FLOWPATH_LABELS <- c(
  `821` = "SBW_0001", `825` = "SBS_0001", `820` = "SBS_0002",
  `822` = "SBS_0003", `815` = "SBW_0002", `818` = "SBBV"
)

#' Compute the real conservative-mixing gain/loss table: one row per
#' real target x species, using the real, already-stored Cl-based
#' mixing fraction (mixing_run_id, default 6 = fissure 816 + SBRR 819).
compute_species_gainloss_table <- function(con, mixing_run_id = 6,
    thermal_sample_id = 816, meteoric_sample_id = 819,
    target_sample_ids = .FLOWPATH_TARGETS,
    species = c("Na", "SO4", "Si", "B", "K", "Alkalinity")) {

  sol <- dbReadTable(con, "PHREEQC_Solutions")
  thermal <- sol[sol$sample_id == thermal_sample_id, ][1, ]
  meteoric <- sol[sol$sample_id == meteoric_sample_id, ][1, ]

  f_tbl <- DBI::dbGetQuery(con, "
    SELECT sample_id, mixing_fraction_thermal AS f
    FROM PHREEQC_Mixing_Fractions WHERE mixing_run_id = ?
  ", params = list(mixing_run_id))

  rows <- lapply(target_sample_ids, function(sid) {
    f_raw <- f_tbl$f[f_tbl$sample_id == sid]
    if (length(f_raw) == 0) {
      message("  -> No mixing fraction on file for sample_id ", sid, " -- skipping.")
      return(NULL)
    }
    f <- min(f_raw[1], 1)  # clamp, same convention as the reaction-path titration (SBW_0002)
    meas <- sol[sol$sample_id == sid, ][1, ]
    tibble::tibble(
      sample_id = sid,
      target_label = .FLOWPATH_LABELS[as.character(sid)],
      feature_type = .FLOWPATH_FEATURE_TYPE[as.character(sid)],
      f_Cl = f_raw[1],
      species = species,
      predicted = meteoric[species] |> unlist() + f * (thermal[species] |> unlist() - meteoric[species] |> unlist()),
      measured = meas[species] |> unlist()
    )
  })
  tbl <- dplyr::bind_rows(rows)
  tbl$pct_residual <- 100 * (tbl$measured - tbl$predicted) / tbl$predicted
  tbl
}

#' Figure: species x target gain/loss tile plot (the single most
#' information-dense new figure in this set).
build_species_gainloss_heatmap_figure <- function(con,
    out_png = "output/figures/manuscript/species_gainloss_heatmap.png") {

  tbl <- compute_species_gainloss_table(con)
  if (nrow(tbl) == 0) { message("  -> No data for species gain/loss heatmap."); return(invisible(NULL)) }

  tbl <- tbl |>
    mutate(
      target_label = factor(target_label, levels = rev(unique(target_label[order(f_Cl)]))),
      species = factor(species, levels = c("Na", "K", "SO4", "Si", "B", "Alkalinity"))
    )

  p <- ggplot(tbl, aes(x = species, y = target_label, fill = pct_residual)) +
    geom_tile(color = "white", linewidth = 0.6) +
    geom_text(aes(label = sprintf("%+.0f%%", pct_residual)), size = 3.4,
              color = ifelse(abs(tbl$pct_residual) > 35, "white", "grey15")) +
    scale_fill_gradient2(low = "#2166AC", mid = "grey95", high = "#B2182B", midpoint = 0,
                          name = "% vs.\nconservative\nmixing") +
    labs(
      x = NULL, y = NULL,
      title = "What is gained or lost along the flowpath, species by species?",
      subtitle = paste0(
        "Real measured value vs. what the same Cl-based mixing fraction (fissure 816 + SBRR 819) would predict\n",
        "if each species traveled conservatively. Blue = depleted relative to conservative mixing; red = enriched."
      ),
      caption = paste0(
        "Na is conservative everywhere (+/-6%), the basis for treating Cl/Na as reliable tracers. Sulfate is gained\n",
        "everywhere but far more at springs/seep (+44 to +62%) than wells (-3 to +20%). Alkalinity is gained at both\n",
        "wells but LOST at two of the three springs -- opposite signs for the same species, by feature type.\n",
        "Source: PHREEQC_Solutions + PHREEQC_Mixing_Fractions (mixing_run_id 6), geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 8), legend.position = "right")

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)

  out_csv <- "data/derived/phreeqc/species_gainloss_table.csv"
  write.csv(tbl, out_csv, row.names = FALSE)
  message("  -> Wrote ", out_csv)
  invisible(list(plot = p, table = tbl))
}

#' Figure: real Cl-based mixing fraction, every real target, sorted,
#' colored by feature type -- "how does mixing occur" at a glance.
build_mixing_fraction_bar_figure <- function(con, mixing_run_id = 6,
    out_png = "output/figures/manuscript/mixing_fraction_by_target.png") {

  f_tbl <- DBI::dbGetQuery(con, "
    SELECT sample_id, mixing_fraction_thermal AS f
    FROM PHREEQC_Mixing_Fractions WHERE mixing_run_id = ?
  ", params = list(mixing_run_id))
  f_tbl <- f_tbl[f_tbl$sample_id %in% names(.FLOWPATH_LABELS), ]
  f_tbl$target_label <- .FLOWPATH_LABELS[as.character(f_tbl$sample_id)]
  f_tbl$feature_type <- .FLOWPATH_FEATURE_TYPE[as.character(f_tbl$sample_id)]
  f_tbl$target_label <- factor(f_tbl$target_label, levels = f_tbl$target_label[order(f_tbl$f)])

  type_colors <- c("Well" = "#D55E00", "Well (resort)" = "#E69F00",
                    "Spring" = "#0072B2", "Seep" = "#56B4E9",
                    "Downstream creek" = "#009E73")

  p <- ggplot(f_tbl, aes(x = f, y = target_label, fill = feature_type)) +
    geom_col(width = 0.6) +
    geom_vline(xintercept = c(0, 1), linetype = "dashed", color = "grey50") +
    geom_text(aes(label = sprintf("%.2f", f)), hjust = -0.2, size = 3.5) +
    scale_fill_manual(values = type_colors, name = "Feature type") +
    scale_x_continuous(limits = c(0, 1.15), expand = expansion(mult = c(0, 0.05))) +
    labs(
      x = "Cl-based mixing fraction (fraction fissure end-member)", y = NULL,
      title = "How much of each discharge point is 'fissure-strength' fluid?",
      subtitle = "Two-end-member conservative-Cl mixing: fissure (SBF_0001, f=1) and SBRR (f=0)",
      caption = paste0(
        "SBW_0002 (resort) exceeds f=1 (1.04, clamped) -- more concentrated than the fissure reference itself, a real,\n",
        "already-documented finding (Session 2026-09-12). SBBV sits far downstream and still implies ~14% fissure-\n",
        "strength fluid by Cl alone, consistent with this project's own Cl mass-balance discharge estimate (58.7 L/s).\n",
        "Source: PHREEQC_Mixing_Fractions, mixing_run_id 6, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 8))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(list(plot = p, table = f_tbl))
}

#' Figure: temperature along the flowpath, two panels --
#' (A) per-feature three-stage cooling profile (Na/K reservoir estimate
#' -> quartz-equilibration estimate -> measured discharge temperature),
#' directly operationalizing "what do the geothermometers say about
#' near-surface hot/dissolving zones"; (B) the simple downstream creek
#' profile (SBRR -> SBBV) showing the real re-warming.
build_temperature_profile_figure <- function(con,
    out_png = "output/figures/manuscript/temperature_flowpath_profile.png") {

  source("scripts/phreeqc/09_run_phreeqc.R", local = TRUE)
  real_thermal_ids <- c(816, 815, 821, 825, 820, 822)
  nak <- calculate_activity_geothermometers(con)
  nak <- nak[nak$sample_id %in% real_thermal_ids & nak$db_file == "llnl.dat", ]

  sw <- DBI::dbGetQuery(con, sprintf(
    "SELECT sample_id, temperature_C, parameter, value FROM PHREEQC_Temp_Sweep
     WHERE sample_id IN (%s) AND parameter = 'SI_Quartz'",
    paste(real_thermal_ids, collapse = ",")))
  .zero_cross <- function(t, s) {
    if (length(t) < 2) return(NA_real_)
    o <- order(t); t <- t[o]; s <- s[o]
    for (i in seq_len(length(t) - 1)) {
      if (!is.na(s[i]) && !is.na(s[i+1]) && sign(s[i]) != sign(s[i+1])) {
        return(t[i] + (s[i] / (s[i] - s[i+1])) * (t[i+1] - t[i]))
      }
    }
    NA_real_
  }
  qz <- sw |> dplyr::group_by(sample_id) |> dplyr::summarise(T_quartz = .zero_cross(temperature_C, value), .groups = "drop")

  meas <- DBI::dbGetQuery(con, sprintf(
    "SELECT sample_id, value AS T_measured FROM PHREEQC_Results WHERE parameter='temp' AND sample_id IN (%s)",
    paste(real_thermal_ids, collapse = ",")))

  labels6 <- c(`816` = "SBF_0001 (fissure)", `815` = "SBW_0002 (resort)",
               `821` = "SBW_0001 (well)", `825` = "SBS_0001 (spring)",
               `820` = "SBS_0002 (seep)", `822` = "SBS_0003 (spring)")
  type6 <- c(`816` = "Well", `815` = "Well (resort)", `821` = "Well",
             `825` = "Spring", `820` = "Seep", `822` = "Spring")

  panelA <- nak[, c("sample_id", "T_NaK_gigg_activity")] |>
    dplyr::left_join(qz, by = "sample_id") |>
    dplyr::left_join(meas, by = "sample_id") |>
    dplyr::mutate(label = labels6[as.character(sample_id)], feature_type = type6[as.character(sample_id)]) |>
    tidyr::pivot_longer(cols = c(T_NaK_gigg_activity, T_quartz, T_measured),
                         names_to = "stage", values_to = "temperature_C") |>
    dplyr::mutate(stage = factor(stage, levels = c("T_NaK_gigg_activity", "T_quartz", "T_measured"),
                                  labels = c("Na/K reservoir\nestimate", "Quartz-equilibration\nestimate", "Measured\ndischarge")))

  pA <- ggplot(panelA, aes(x = stage, y = temperature_C, group = label, color = feature_type)) +
    geom_line(linewidth = 0.9, alpha = 0.85) +
    geom_point(size = 2.6) +
    ggrepel::geom_text_repel(data = panelA |> dplyr::filter(stage == levels(panelA$stage)[3]),
                              aes(label = label), size = 3, hjust = -0.1, direction = "y",
                              nudge_x = 0.15, segment.size = 0.3, show.legend = FALSE) +
    scale_color_manual(values = c("Well" = "#D55E00", "Well (resort)" = "#E69F00",
                                   "Spring" = "#0072B2", "Seep" = "#56B4E9"), name = "Feature type") +
    labs(x = NULL, y = "Temperature (degrees C)",
         title = "A. Three-stage cooling: deep reservoir to shallow discharge") +
    theme_steamboat(base_size = 10) +
    theme(legend.position = "top")

  creek <- data.frame(
    label = factor(c("SBRR (near-field)", "SBBV (downstream)"), levels = c("SBRR (near-field)", "SBBV (downstream)")),
    temperature_C = c(15.2, 23.7)
  )
  pB <- ggplot(creek, aes(x = label, y = temperature_C, group = 1)) +
    geom_line(color = "#009E73", linewidth = 1) +
    geom_point(size = 3.5, color = "#009E73") +
    geom_text(aes(label = sprintf("%.1f C", temperature_C)), vjust = -1, size = 3.5) +
    expand_limits(y = c(10, 28)) +
    labs(x = NULL, y = "Temperature (degrees C)",
         title = "B. Steamboat Creek re-warms downstream") +
    theme_steamboat(base_size = 10)

  p <- patchwork::wrap_plots(pA, pB, ncol = 2, widths = c(2, 1)) +
    patchwork::plot_annotation(
      subtitle = paste0(
        "Panel A: every real thermal feature cools in three real, computable stages -- Na/K and quartz are both\n",
        "systematically above measured discharge temperature at every feature, and the gap is largest at the two\n",
        "cooler springs (SBS_0001, SBS_0003), consistent with more near-surface processing there than at the wells.\n",
        "Panel B: Steamboat Creek's real measured temperature rises from SBRR to SBBV, direct confirmation of real\n",
        "thermal inflow entering the creek between the two stations."
      )
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Figure: a focused, 2-panel version of the gain/loss heatmap --
#' sulfate and alkalinity residuals only, explicitly grouped by feature
#' type, making the springs-vs-wells distinction the headline.
build_springs_vs_wells_residual_figure <- function(con,
    out_png = "output/figures/manuscript/springs_vs_wells_residuals.png") {

  tbl <- compute_species_gainloss_table(con, species = c("SO4", "Alkalinity"))
  if (nrow(tbl) == 0) { message("  -> No data for springs-vs-wells figure."); return(invisible(NULL)) }

  tbl <- tbl |>
    dplyr::mutate(
      target_label = factor(target_label, levels = target_label[order(f_Cl)] |> unique()),
      species_label = ifelse(species == "SO4", "Sulfate (SO4)", "Alkalinity")
    )

  type_colors <- c("Well" = "#D55E00", "Well (resort)" = "#E69F00",
                    "Spring" = "#0072B2", "Seep" = "#56B4E9")

  p <- ggplot(tbl, aes(x = target_label, y = pct_residual, fill = feature_type)) +
    geom_col(width = 0.6) +
    geom_hline(yintercept = 0, color = "grey40") +
    geom_text(aes(label = sprintf("%+.0f%%", pct_residual),
                  vjust = ifelse(pct_residual >= 0, -0.4, 1.2)), size = 3.3) +
    facet_wrap(~species_label, scales = "free_y") +
    scale_fill_manual(values = type_colors, name = "Feature type") +
    labs(
      x = NULL, y = "% vs. conservative Cl-based mixing",
      title = "Springs and wells diverge in opposite directions on alkalinity, both gain sulfate",
      subtitle = "Same gain/loss calculation as the full heatmap, isolated to the two species with the clearest feature-type pattern",
      caption = paste0(
        "All three springs/seep gain far more sulfate than either well (+44 to +62% vs. -3 to +20%), plausibly\n",
        "near-surface H2S oxidation at an open discharge point. Alkalinity is gained at both wells but LOST\n",
        "at two of three springs -- opposite signs for the same species -- consistent with a shared deep source but\n",
        "divergent near-surface processes between feature types, not simply 'connected' or 'not connected.'\n",
        "Source: PHREEQC_Solutions + PHREEQC_Mixing_Fractions (mixing_run_id 6), geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 8), axis.text.x = element_text(angle = 20, hjust = 1))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9.5, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(list(plot = p, table = tbl))
}

#' Convenience wrapper: build all four baseline-characterization figures.
build_flowpath_baseline_characterization_figures <- function(con) {
  build_species_gainloss_heatmap_figure(con)
  build_mixing_fraction_bar_figure(con)
  build_temperature_profile_figure(con)
  build_springs_vs_wells_residual_figure(con)
  invisible(TRUE)
}
