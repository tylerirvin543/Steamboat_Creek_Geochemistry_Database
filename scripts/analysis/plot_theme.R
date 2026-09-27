# Shared ggplot2 theme and palette for "publication-ready" Steamboat
# Geochemistry Database figures.
#
# Purpose: several sessions' worth of figures (facies clustering, PHREEQC
# results, chloride ratios, sampling-frequency curves) were each built with
# ad hoc ggplot defaults. This file gives any *new or re-saved* figure a
# single, consistent look -- font sizes appropriate for a manuscript page,
# a colorblind-safe categorical palette keyed to this project's own
# site_type / era / facies vocabulary, and a thin caption style for
# statistic-in-caption figures (a pattern already used throughout
# notebooks/07 and 08).
#
# This does NOT retroactively touch already-generated PNGs (e.g. the
# existing output/figures/facies/*.png) -- apply theme_steamboat() the next
# time a figure's generating code is edited or re-run.

library(ggplot2)

theme_steamboat <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = rel(1.05)),
      plot.subtitle = element_text(color = "grey35", size = rel(0.85)),
      plot.caption = element_text(hjust = 0, color = "grey40", size = rel(0.72)),
      legend.position = "right",
      panel.grid.minor = element_blank(),
      strip.background = element_rect(fill = "grey92", color = NA),
      strip.text = element_text(face = "bold")
    )
}

# Okabe-Ito colorblind-safe palette, mapped to this project's recurring
# categorical vocabulary. Not every figure uses every key -- ggplot's
# `scale_*_manual(values = ...)` silently ignores unused names.
palette_steamboat <- c(
  fumarole          = "#D55E00",
  spring            = "#E69F00",
  seep              = "#CC79A7",
  well              = "#0072B2",
  domestic          = "#56B4E9",
  creek             = "#009E73",
  transect          = "#009E73",
  background        = "#999999",
  `1990-91`         = "#0072B2",
  `2024-26`         = "#D55E00",
  thermal           = "#D55E00",
  intermediate      = "#E69F00",
  `background_dilute` = "#999999",
  quartz            = "#0072B2",
  chalcedony        = "#56B4E9",
  `Na/K (Giggenbach)` = "#D55E00",
  `Na/K (Fournier)`   = "#E69F00"
)

scale_color_steamboat <- function(...) {
  ggplot2::scale_color_manual(values = palette_steamboat, ...)
}

scale_fill_steamboat <- function(...) {
  ggplot2::scale_fill_manual(values = palette_steamboat, ...)
}
