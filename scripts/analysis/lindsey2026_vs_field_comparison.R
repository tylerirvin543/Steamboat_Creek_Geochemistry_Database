# ============================================================
# lindsey2026_vs_field_comparison.R
#
# Read-only comparison of Lindsey et al. (2026) Table 5 samples with this
# project's closest samples:
#   SBG002 (runoff, Jun 2025)  vs sample 816 (SBF_0001, 2026-05-01)   <- main pair
#   SBG001 (pipe, Jun 2025)    vs 816 and vs 815 (SBW_0002 resort tank)
# Outputs: view vw_lindsey_vs_field, data/derived/lindsey2026_vs_field_comparison.csv,
# data/derived/lindsey2026_vs_field_ratios.csv, output/figures/lindsey_vs_field_chemistry.png.
# Different labs and dates: two samples against two samples, not a trend.
# ============================================================
library(DBI); library(dplyr); library(tidyr); library(ggplot2); library(readr); library(patchwork)

.lv_ids <- c(SBG001_pipe = "LINDSEY2026_SBG001_2025-06-01", SBG002_runoff = "LINDSEY2026_SBG002_2025-06-01",
             SBF_0001_2026 = "SBF_0001-2026-05-01", SBW_0002_2026 = "SBW_0002-2026-05-01")
.lv_analytes <- c("pH","SC","TDS","Na","K","Ca","Mg","Cl","SO4","Alkalinity","Si","B","Li","As")

lindsey_vs_field <- function(con, out_dir = "data/derived", fig = "output/figures/lindsey_vs_field_chemistry.png") {
  dbExecute(con, "DROP VIEW IF EXISTS vw_lindsey_vs_field")
  sel <- paste(sprintf("MAX(CASE WHEN s.external_sample_id = '%s' THEN la.value END) AS %s", .lv_ids, names(.lv_ids)), collapse = ",\n  ")
  dbExecute(con, sprintf("CREATE VIEW vw_lindsey_vs_field AS
    SELECT la.analyte,\n  %s
    FROM Lab_Analyses la JOIN Samples s ON s.sample_id = la.sample_id
    WHERE s.external_sample_id IN (%s) AND la.analyte IN (%s)
    GROUP BY la.analyte", sel, paste0("'", .lv_ids, "'", collapse = ","), paste0("'", .lv_analytes, "'", collapse = ",")))
  v <- dbGetQuery(con, "SELECT * FROM vw_lindsey_vs_field")
  v <- v[match(.lv_analytes, v$analyte), ]
  v <- v |> mutate(
    pct_runoff_vs_816 = round(100 * (SBG002_runoff - SBF_0001_2026) / SBF_0001_2026, 1),
    pct_pipe_vs_816 = round(100 * (SBG001_pipe - SBF_0001_2026) / SBF_0001_2026, 1),
    pct_pipe_vs_815 = round(100 * (SBG001_pipe - SBW_0002_2026) / SBW_0002_2026, 1))

  # ratios, charge balance, geothermometers (mg/L basis)
  samp <- c("SBG001_pipe", "SBG002_runoff", "SBF_0001_2026", "SBW_0002_2026")
  long <- v |> select(analyte, all_of(samp)) |> pivot_longer(-analyte, names_to = "sample") |>
    pivot_wider(names_from = analyte, values_from = value)
  eqw <- c(Na = 22.99, K = 39.10, Ca = 40.08 / 2, Mg = 24.31 / 2, Cl = 35.45, SO4 = 96.06 / 2, Alkalinity = 61.02)
  rat <- long |> mutate(
    Cl_B = Cl / B, Na_Cl = Na / Cl, Na_K = Na / K, Li_Cl = Li / Cl, Si_Cl = Si / Cl, SO4_Cl = SO4 / Cl,
    cations_meq = Na / eqw["Na"] + K / eqw["K"] + Ca / eqw["Ca"] + Mg / eqw["Mg"],
    anions_meq = Cl / eqw["Cl"] + SO4 / eqw["SO4"] + Alkalinity / eqw["Alkalinity"],
    charge_balance_pct = round(100 * (cations_meq - anions_meq) / (cations_meq + anions_meq), 2),
    T_NaK_giggenbach_C = round(1390 / (1.75 + log10(Na_K)) - 273.15, 1),
    T_quartz_C = round(1309 / (5.19 - log10(Si * 2.2139)) - 273.15, 1)) |>
    select(sample, Cl_B, Na_Cl, Na_K, Li_Cl, Si_Cl, SO4_Cl, charge_balance_pct, T_NaK_giggenbach_C, T_quartz_C) |>
    mutate(across(c(Cl_B, Na_Cl, Na_K, Li_Cl, Si_Cl, SO4_Cl), \(x) signif(x, 3)))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  write_csv(v, file.path(out_dir, "lindsey2026_vs_field_comparison.csv"))
  write_csv(rat, file.path(out_dir, "lindsey2026_vs_field_ratios.csv"))

  # figure: Schoeller-style + ratio panel
  lab <- c(SBG001_pipe = "SBG001 pipe (Jun 2025, Lindsey)", SBG002_runoff = "SBG002 runoff (Jun 2025, Lindsey)",
           SBF_0001_2026 = "816 SBF_0001 fissure (May 2026)", SBW_0002_2026 = "815 SBW_0002 resort tank (May 2026)")
  ions <- c("Na","K","Ca","Mg","Cl","SO4","Alkalinity","Si","B","Li")
  sch <- v |> filter(analyte %in% ions) |> select(analyte, all_of(samp)) |> pivot_longer(-analyte, names_to = "sample") |>
    mutate(analyte = factor(analyte, ions), sample = factor(lab[sample], lab))
  p1 <- ggplot(sch, aes(analyte, value, colour = sample, group = sample)) + geom_line() + geom_point(size = 2) +
    scale_y_log10() + labs(x = NULL, y = "mg/L (log scale)", colour = NULL, title = "Major and trace ions") + theme_minimal(base_size = 10) +
    theme(legend.position = "bottom", legend.direction = "vertical")
  rr <- rat |> select(sample, Cl_B, Na_K, Li_Cl, SO4_Cl) |> pivot_longer(-sample, names_to = "ratio") |>
    mutate(sample = factor(lab[sample], lab))
  p2 <- ggplot(rr, aes(sample, value, fill = sample)) + geom_col(show.legend = FALSE) +
    facet_wrap(~ratio, scales = "free_y", nrow = 1) + scale_x_discrete(labels = NULL) +
    labs(x = NULL, y = "ratio (mg/L basis)", title = "Conservative and geothermometer ratios") + theme_minimal(base_size = 10)
  cap <- paste("Lindsey et al. (2026) Table 5 against this project's samples at the same Location (SBF_0001) and the resort tank.",
               "Different laboratories and dates; two samples against two samples, not a trend.", sep = "\n")
  fg <- p1 / p2 + plot_annotation(caption = cap)
  dir.create(dirname(fig), recursive = TRUE, showWarnings = FALSE)
  ggsave(fig, fg, width = 9, height = 9, dpi = 200)
  list(comparison = v, ratios = rat)
}
