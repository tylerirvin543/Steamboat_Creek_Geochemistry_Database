# What the baseline mixing results say about detecting change (read-only; no PHREEQC runs).
# For each Lower Sinter Terrace feature: baseline fingerprint (Cl, mixing fraction between the
# fissure and SBRR, Cl/B, Na/Cl), the smallest change that would stand out from analytical
# uncertainty, and how a change at the fissure/springs would show at the creek station SBBV.
# Planning values, not tests: one snapshot per feature, no replicates.

change_detection_from_mixing <- function(con, cv_analytical = 0.05, cv_creek_record = 0.09,
                                         c_thermal = 820,
                                         out_dir = "data/derived/change_detection",
                                         fig_dir = "output/figures/manuscript") {
  library(dplyr); library(ggplot2)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  ids <- c(`SBF_0001 fissure` = 816, `SBW_0002 resort tank` = 815, `SBW_0001 well` = 821,
           `SBS_0001 spring` = 825, `SBS_0002 spring` = 820, `SBS_0003 spring` = 822,
           `SBRR creek (upstream)` = 819, `SBBV creek (downstream)` = 818)
  chem <- DBI::dbGetQuery(con, sprintf(
    "SELECT sample_id, Cl, Na, B, SO4, Alkalinity FROM PHREEQC_Solutions WHERE sample_id IN (%s)",
    paste(ids, collapse = ",")))
  chem$feature <- names(ids)[match(chem$sample_id, ids)]
  cl_f <- chem$Cl[chem$sample_id == 816]; cl_rr <- chem$Cl[chem$sample_id == 819]
  fp <- chem |>
    mutate(mix_fraction = (Cl - cl_rr) / (cl_f - cl_rr), Cl_B = Cl / B, Na_Cl = Na / Cl)

  # Two single measurements differ by chance more than 1.96 * sqrt(2) * cv (about 2.77 cv).
  k <- 1.96 * sqrt(2)
  mdc_cl <- k * cv_analytical
  mdc_ratio <- k * sqrt(2) * cv_analytical
  fp <- fp |>
    mutate(MDC_Cl_pct = 100 * mdc_cl,
           MDC_ratio_pct = 100 * mdc_ratio,
           MDC_mixfrac = mdc_cl * Cl / (cl_f - cl_rr))

  # Creek: SBBV chloride is mostly thermal. A fractional change x in thermal chloride flux
  # changes SBBV chloride by x * thermal share of the chloride.
  cl_bv <- chem$Cl[chem$sample_id == 818]
  thermal_cl_share <- (cl_bv - cl_rr) / cl_bv
  thermal_flow_fraction <- (cl_bv - cl_rr) / (c_thermal - cl_rr)
  cv_creek <- sqrt(cv_analytical^2 + cv_creek_record^2)
  mdc_thermal_flux_pct <- 100 * k * cv_creek / thermal_cl_share
  creek <- data.frame(
    thermal_flow_fraction_pct = 100 * thermal_flow_fraction,
    thermal_share_of_SBBV_Cl_pct = 100 * thermal_cl_share,
    creek_cv_pct = 100 * cv_creek,
    min_detectable_change_in_thermal_Cl_flux_pct = mdc_thermal_flux_pct)

  write.csv(fp, file.path(out_dir, "feature_fingerprint_and_mdc.csv"), row.names = FALSE)
  write.csv(creek, file.path(out_dir, "creek_detectability.csv"), row.names = FALSE)

  d <- fp |> filter(!is.na(mix_fraction), !grepl("creek", feature)) |>
    mutate(feature = factor(feature, feature[order(mix_fraction)]))
  g <- ggplot(d, aes(mix_fraction, feature)) +
    geom_errorbar(aes(xmin = mix_fraction - MDC_mixfrac, xmax = mix_fraction + MDC_mixfrac), width = 0.2, orientation = "y") +
    geom_point(size = 2.5) +
    labs(x = "Thermal (fissure) fraction from chloride", y = NULL,
         title = "Baseline fingerprint and the smallest change each feature could show",
         subtitle = sprintf("Bars: two single samples differ beyond chance at %.0f%% chloride (5%% analytical error per sample)", 100 * mdc_cl),
         caption = sprintf("Creek (SBBV): thermal water is %.0f%% of flow but %.0f%% of chloride, so a change of about %.0f%% in thermal chloride flux\nis the smallest the creek record could show (analytical plus 9%% reconstruction error). Planning values; one snapshot, no replicates.",
                           100 * thermal_flow_fraction, 100 * thermal_cl_share, mdc_thermal_flux_pct)) +
    theme_minimal(base_size = 10) + theme(plot.caption = element_text(hjust = 0))
  ggsave(file.path(fig_dir, "change_detection_fingerprint.png"), g, width = 8, height = 4.2, dpi = 200)
  invisible(list(fingerprint = fp, creek = creek, plot = g))
}
