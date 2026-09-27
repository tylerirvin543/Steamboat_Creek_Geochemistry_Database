# ============================================================
# build_mixing_and_distribution_plots.R
#
# Purpose:
# Three "nicer/more informative figure" upgrades requested
# 2026-09-26, using packages already installed/used elsewhere in this
# project (ggdist, ggbeeswarm, boot) but not yet applied to these
# specific real results:
#   1. plot_mixing_fraction_distribution(con) -- the univariate
#      distribution of the real PHREEQC mixing fraction itself
#      (one value per real sample), complementing (not duplicating)
#      the existing fraction-vs-predicted-SI relationship plot in
#      notebooks/06_phreeqc_geochemical_modeling.qmd.
#   2. plot_si_distribution_by_group(con) -- a polished ggdist
#      half-eye comparison of PHREEQC saturation indices
#      (Calcite/Dolomite/Quartz) between background/well/thermal
#      samples, with a bootstrap 95% CI on the genuinely-thermal
#      group's mean drawn on top -- upgrades notebook 08's
#      tabular-only fitdistrplus/boot section.
#   3. bootstrap_ci_by_group() -- generic nonparametric bootstrap
#      helper, reused for the Cl/B ratio figure added to notebook 07
#      (belt-and-suspenders next to the existing Welch t-test there).
#
# Usage:
#   source("scripts/analysis/build_mixing_and_distribution_plots.R")
#   plot_mixing_fraction_distribution(con)
#   si <- plot_si_distribution_by_group(con); si$plot
#   bootstrap_ci_by_group(ratio_plot_data, value_col = "Cl_B", group_col = "era_short")
# ============================================================

library(DBI)
library(dplyr)
library(tidyr)
library(ggplot2)
library(ggdist)
library(ggbeeswarm)
library(ggrepel)
library(boot)

.save_if_requested2 <- function(plot_obj, out_path, width = 8, height = 6, dpi = 200) {
  if (!is.null(out_path)) {
    # Resolve project-root-relative regardless of which notebook
    # sources this file: notebooks that pin knitr root.dir to the
    # project root (e.g. 06) already have the right cwd, but ones
    # that do not (e.g. 08) render with cwd=notebooks/, which would
    # otherwise silently write into notebooks/output/... instead of
    # this project's real output/figures/ tree. Same fix pattern
    # already used for the facies PCA biplot/heatmap figures.
    resolved_path <- out_path
    if (basename(getwd()) == "notebooks") {
      resolved_path <- file.path("..", out_path)
    }
    dir.create(dirname(resolved_path), showWarnings = FALSE, recursive = TRUE)
    ggsave(resolved_path, plot = plot_obj, width = width, height = height, dpi = dpi)
  }
  invisible(plot_obj)
}

#' Generic nonparametric bootstrap 95% CI on a group mean -- the same
#' approach notebook 08 already uses for the small real-thermal
#' PHREEQC SI sample, factored out for reuse.
#' @return tibble: group, n, mean, ci_lo, ci_hi
bootstrap_ci_by_group <- function(df, value_col, group_col, R = 5000, seed = 4821) {
  # Every dplyr verb below is namespace-qualified (dplyr::filter,
  # dplyr::select, ...), not called bare -- notebooks that also load
  # Hmisc (e.g. 08_statistical_synthesis.qmd) mask several of these
  # with incompatible base-style versions, which silently broke this
  # exact function with "unused argument (-ci)" the first time it was
  # tried there. Confirmed fixed by qualifying every call explicitly.
  set.seed(seed)
  df %>%
    dplyr::rename(.value = dplyr::all_of(value_col), .group = dplyr::all_of(group_col)) %>%
    dplyr::filter(!is.na(.value)) %>%
    dplyr::group_by(.group) %>%
    dplyr::summarise(
      n = dplyr::n(), mean = mean(.value),
      ci = {
        b <- boot::boot(.value, function(d, i) mean(d[i]), R = R)
        ci <- boot::boot.ci(b, type = "perc")$percent[4:5]
        list(ci)
      },
      .groups = "drop"
    ) %>%
    dplyr::mutate(ci_lo = purrr::map_dbl(ci, 1), ci_hi = purrr::map_dbl(ci, 2)) %>%
    dplyr::select(-ci) %>%
    dplyr::rename(!!group_col := .group)
}

#' Real PHREEQC mixing-fraction distribution, split into two groups
#' (background_dilute vs. thermal_or_other). Deliberately uses the
#' FULL PHREEQC_Mixing_Fractions table (n=754: every real sample with
#' a Cl value gets a linear conservative-mixing fraction computed, not
#' just the 111 that went through the fuller PHREEQC MIX-block
#' geochemical prediction in PHREEQC_Mixing_Results) -- restricting to
#' the 111-sample set was tried first and silently DROPPED the real
#' SBW_0002 outlier (f=1.044, "more concentrated than the thermal
#' reference itself") this figure is specifically meant to surface,
#' because that sample never converged in the fuller MIX-block run.
plot_mixing_fraction_distribution <- function(con, out_path = "output/figures/phreeqc/mixing_fraction_distribution.png") {
  mf <- dbGetQuery(con, "
    SELECT f.sample_id, f.mixing_fraction_thermal, l.name AS location_name, l.site_type,
           r.thermal_end_member_id, r.meteoric_end_member_id
    FROM PHREEQC_Mixing_Fractions f
    JOIN PHREEQC_Mixing_Runs r ON r.mixing_run_id = f.mixing_run_id
    JOIN Samples sm ON sm.sample_id = f.sample_id
    JOIN Locations l ON l.location_id = sm.location_id
    WHERE f.tracer = 'Cl'
  ")
  if (nrow(mf) == 0) {
    message("[mixing] No PHREEQC_Mixing_Fractions rows found -- has the real mixing run been executed?")
    return(invisible(NULL))
  }
  thermal_name <- dbGetQuery(con, sprintf(
    "SELECT l.name FROM Samples s JOIN Locations l ON l.location_id = s.location_id WHERE s.sample_id = %d",
    mf$thermal_end_member_id[1]))$name
  meteoric_name <- dbGetQuery(con, sprintf(
    "SELECT l.name FROM Samples s JOIN Locations l ON l.location_id = s.location_id WHERE s.sample_id = %d",
    mf$meteoric_end_member_id[1]))$name

  # 2026-09-26: site_type == "background" is now (correctly) reserved
  # for a genuinely-unclassified NDEP station -- every real creek/ditch
  # sample that used to be mislabeled "background" is now "creek" (see
  # ndep_locations.R's fix + the retroactive backfill). The dilute-
  # reference group below is keyed on "creek" accordingly, with a
  # defensive fallback to also catch any future truly-ambiguous
  # "background" row rather than silently dropping it from the plot.
  mf <- mf %>% mutate(group = ifelse(site_type %in% c("creek", "background"), "creek_dilute", "thermal_or_other"))
  mf$label <- ifelse(mf$mixing_fraction_thermal > 1 | mf$mixing_fraction_thermal < 0, mf$location_name, NA)

  p <- ggplot(mf, aes(x = group, y = mixing_fraction_thermal, color = group, fill = group)) +
    ggdist::stat_halfeye(alpha = 0.55, .width = c(0.66, 0.95), point_interval = "median_qi") +
    ggbeeswarm::geom_quasirandom(width = 0.08, size = 0.9, alpha = 0.35, show.legend = FALSE) +
    geom_hline(yintercept = c(0, 1), linetype = "dashed", color = "grey40") +
    ggrepel::geom_text_repel(aes(label = label), na.rm = TRUE, size = 3,
                              segment.size = 0.3, seed = 4172, max.overlaps = 20, show.legend = FALSE) +
    labs(
      title = "Distribution of real Cl-derived mixing fractions by sample group",
      subtitle = paste0("f = 0: meteoric end-member (", meteoric_name, "); f = 1: thermal end-member (", thermal_name, ")"),
      x = NULL, y = "Mixing fraction thermal (f)", color = "Group", fill = "Group",
      caption = paste0(
        "n = ", nrow(mf), " real samples with a Cl measurement. The labeled point beyond f=1 (dashed line) is MORE\n",
        "concentrated in Cl than the chosen thermal reference sample itself -- a real finding (not an error),\n",
        "consistent with using a single representative, not maximum-concentration, thermal end-member."
      )
    ) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none", plot.caption = element_text(hjust = 0, size = 8.5))
  .save_if_requested2(p, out_path, width = 8, height = 6)
}

#' Polished PHREEQC saturation-index distribution comparison, faceted
#' by mineral, with a bootstrap 95% CI drawn on the genuinely-thermal
#' group's mean -- upgrades notebook 08's tabular-only fitdistrplus/
#' boot section.
#'
#' Uses a real 3-way split (background / well / thermal), NOT the
#' "background_dilute vs. thermal_or_other" binary notebook 08's own
#' `phr` chunk uses -- that binary groups every non-background
#' site_type together, which today means 71-85 NDEP/domestic "well"
#' PHREEQC results get lumped in with only ~10 genuinely thermal
#' fumarole/seep/spring samples. Confirmed directly (2026-09-26): this
#' makes notebook 08's own prose ("n = 7-8 real thermal... samples")
#' now stale relative to what its own code currently computes against
#' the grown database (that stale claim is fixed separately, in the
#' notebook edit, not silently reproduced here).
#' @return list(plot=, data=, boot_summary=)
plot_si_distribution_by_group <- function(con, out_path = "output/figures/statistics/si_distribution_by_group.png") {
  phr <- dbGetQuery(con, "
    SELECT r.sample_id, r.parameter, r.value, l.site_type
    FROM PHREEQC_Results r
    JOIN Samples sm ON r.sample_id = sm.sample_id
    JOIN Locations l ON sm.location_id = l.location_id
    WHERE r.parameter IN ('SI_Calcite','SI_Dolomite','SI_Quartz')
  ") %>%
    filter(value > -900) %>%
    mutate(
      # 2026-09-26: "creek" (not "background") is now the real dilute-
      # reference group -- every NDEP creek/ditch station that used
      # to be mislabeled site_type="background" is now correctly
      # "creek" (see ndep_locations.R's fix + retroactive backfill),
      # and this is a real, substantial population (227 real
      # SI_Calcite rows), not the tiny n=2 the old comment here
      # described (that was the handful of ALREADY-correctly-labeled
      # creek rows from other sources, before the NDEP mislabeling
      # was fixed).
      group = case_when(
        site_type %in% c("creek", "background") ~ "creek",
        site_type == "well" ~ "well (domestic/NDEP)",
        site_type %in% c("fumarole", "seep", "spring") ~ "thermal (fumarole/seep/spring)",
        TRUE ~ NA_character_  # transect: n=2, still too small to place meaningfully
      ),
      mineral = sub("^SI_", "", parameter)
    ) %>%
    filter(!is.na(group)) %>%
    mutate(group = factor(group, levels = c("creek", "well (domestic/NDEP)", "thermal (fumarole/seep/spring)")))

  boot_summary <- bootstrap_ci_by_group(
    phr %>% filter(group == "thermal (fumarole/seep/spring)"),
    value_col = "value", group_col = "mineral"
  ) %>% mutate(group = "thermal (fumarole/seep/spring)")

  p <- ggplot(phr, aes(x = group, y = value, color = group, fill = group)) +
    ggdist::stat_halfeye(alpha = 0.55, .width = c(0.66, 0.95), point_interval = "median_qi") +
    ggbeeswarm::geom_quasirandom(width = 0.08, size = 0.8, alpha = 0.4, show.legend = FALSE) +
    geom_errorbar(
      data = boot_summary,
      aes(x = "thermal (fumarole/seep/spring)", y = mean, ymin = ci_lo, ymax = ci_hi),
      inherit.aes = FALSE, width = 0.15, color = "black", linewidth = 0.6
    ) +
    facet_wrap(~ mineral, scales = "free_y") +
    labs(
      title = "PHREEQC saturation-index distributions by mineral and sample group",
      subtitle = paste0(
        "ggdist half-eye + individual samples; black bars = bootstrap 95% CI on the real thermal-group mean (n=",
        paste(boot_summary$n, collapse = "-"), ")"
      ),
      x = NULL, y = "Saturation index", color = "Group", fill = "Group"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 20, hjust = 1), legend.position = "none")
  .save_if_requested2(p, out_path, width = 11, height = 5)
  list(plot = p, data = phr, boot_summary = boot_summary)
}
