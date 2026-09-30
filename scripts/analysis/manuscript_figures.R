# ============================================================
# manuscript_figures.R
#
# Purpose: generates the two figures used in the thesis-proposal
# document (manuscript/00_thesis_proposal.qmd) that don't already have
# a home in an existing script/notebook chunk:
#
#   1. discharge_through_time.png -- the 1955-2026 thermal-water
#      discharge comparison already coded inline inside
#      notebooks/07_historical_context_sorey1992.qmd's `discharge-plot`
#      chunk. Factored out here so the manuscript doesn't need to
#      render the (heavy, DB-querying) full notebook just to get one
#      figure, and so the notebook and the manuscript are guaranteed to
#      show the same numbers rather than maintaining two copies.
#   2. steamboat_timeline.png -- a new, simple horizontal timeline
#      figure spanning the 1950s USGS-era characterization through the
#      June 2025 eruption and this project's own 2026 monitoring
#      network, built from dates already documented elsewhere in this
#      project (website/timeline.Rmd, notebooks/07's discharge table,
#      docs/literature/annotated_bibliography.qmd) rather than
#      estimated fresh.
#
# Neither figure is committed as a static image -- both are produced
# on demand, consistent with this project's existing convention (see
# manuscript/04_results.qmd's own note to that effect).
#
# Usage (from the project root):
#   source("scripts/analysis/manuscript_figures.R")
#   build_manuscript_figures(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(ggrepel)

source("scripts/analysis/plot_theme.R")
source("scripts/analysis/chloride_mass_balance.R")

#' Reproduce notebooks/07's discharge-through-time comparison as a
#' standalone, reusable figure.
build_discharge_through_time_figure <- function(con,
    out_png = "output/figures/manuscript/discharge_through_time.png") {

  cmb <- compute_chloride_mass_balance(con)
  qtw_live <- if (is.na(cmb$mean_Q_TW_Ls)) NA_real_ else cmb$mean_Q_TW_Ls

  discharge_hist <- tibble::tribble(
    ~period, ~year_mid, ~Ls,

    "White (1968), Apr 1955",                        1955,    1110 * 0.0630902,
    "White (1968), Apr 1964",                        1964,    1385 * 0.0630902,
    "Shump (1985), 1981-82 avg",                     1981.5,  1300 * 0.0630902,
    "Collar (1990), Jun 1988",                       1988.5,   523 * 0.0630902,
    "Collar (1990), Mar 1989",                       1989.2,   663 * 0.0630902,
    "Collar & Huntley (1990), 1988-89 natural-only",  1988.8,  0.80 * 1120 * 0.0630902,
    "Sorey & Spielman (2008), 2007-08",              2007.5,  mean(c(730, 1214)) * 0.0630902,
    "Sorey & Spielman (2017), 2008-2016 avg",        2012,     60,
    "This project (database), 5/1/2026",             2026.33, qtw_live,
    "Irvin & Lindsey (2026 poster), post-eruption avg", 2026,  27
  ) |>
    filter(!is.na(Ls))

  p <- ggplot(discharge_hist, aes(x = year_mid, y = Ls)) +
    geom_line(alpha = 0.3) +
    geom_point(aes(color = grepl("This project", period)),
               size = 3, show.legend = FALSE) +
    ggrepel::geom_text_repel(aes(label = period), size = 2.6,
                              max.overlaps = 30, seed = 4172) +
    scale_color_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "black")) +
    labs(
      x = "Year", y = "Thermal-water discharge (L/s)",
      title = "Thermal-water discharge to Steamboat Creek, 1955-2026",
      subtitle = "No confidence intervals shown -- no source reports a measurement uncertainty"
    ) +
    theme_steamboat()

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' A simple, real-dates-only horizontal timeline of Steamboat Hills
#' events spanning the pre-Ormat USGS-characterization era through this
#' project's own 2026 monitoring network. Dates are drawn from sources
#' already cited elsewhere in this project (Thompson & White 1964,
#' White 1968, Sorey & Colvard 1992, Sorey 2000, Klein et al. 2007,
#' Dhakal et al. 2025, Lindsey et al. 2026, website/timeline.Rmd's
#' EXIF-dated photo timeline) -- nothing here is estimated fresh.
build_steamboat_timeline_figure <- function(
    out_png = "output/figures/manuscript/steamboat_timeline.png") {

  events <- tibble::tribble(
    ~year, ~label, ~era,
    1950,  "USGS thermal-gradient/chemistry test holes (GS-1 to GS-8)",        "Historical",
    1964,  "Thompson & White / White et al.: regional geology and structure",  "Historical",
    1968,  "White: hydrology, activity, and heat flow of the thermal system",  "Historical",
    1986,  "SB GEO's first power plants begin production",                    "Development",
    1987,  "Natural hot-spring flow at the main/low terraces begins to fail",  "Development",
    1990,  "Ormat consolidates Steamboat production under one operator",      "Development",
    1992,  "Sorey & Colvard: spring-flow decline attributed largely to\nregional groundwater decline, not CPI production", "Development",
    2000,  "Sorey: groundwater levels recover, but spring flow does not\nresume on the main terrace", "Development",
    2007,  "Klein, Johnson & Spielman: monitor-well network documented",       "Development",
    2022,  "Renewed steaming ground first noted at the Lower Sinter Terrace",  "Reawakening",
    2025,  "Lower Sinter Terrace eruption (June 3); wellhead capped,\ndischarge redistributes laterally", "Reawakening",
    2025,  "This project's temperature/conductivity logger network deployed", "This project",
    2026,  "Lindsey et al. publish the first full eruption account (Feb);\nspring/well remapping and chemistry sampling continue", "This project"
  )

  p <- ggplot(events, aes(x = year, y = 0)) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_point(aes(color = era), size = 3) +
    ggrepel::geom_text_repel(
      aes(label = paste0(year, ": ", label), color = era),
      size = 2.5, direction = "y", nudge_y = rep(c(0.6, -0.6), length.out = nrow(events)),
      segment.size = 0.3, max.overlaps = 20, seed = 917
    ) +
    scale_color_manual(values = c(
      "Historical"    = "#0072B2",
      "Development"   = "#999999",
      "Reawakening"   = "#D55E00",
      "This project"  = "#009E73"
    )) +
    scale_y_continuous(limits = c(-1.2, 1.2)) +
    labs(x = "Year", y = NULL, color = "Period",
         title = "Steamboat Hills: from characterization to reawakening") +
    theme_steamboat() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 10, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Convenience wrapper: build both new manuscript figures.
build_manuscript_figures <- function(con) {
  build_discharge_through_time_figure(con)
  build_steamboat_timeline_figure()
  invisible(TRUE)
}
