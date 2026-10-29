# ============================================================
# lst_ternary_diagrams.R
#
# Two new ternary diagrams for the seven real Lower Sinter Terrace
# flowpath samples (fissure, SBRR, SBW_0001, SBW_0002, and the three
# real springs/seep SBS_0001/2/3), built 2026-10-27 as part of the
# proposal's new PHREEQC geochemical modeling subsection:
#
#   1. build_giggenbach_ternary_figure() -- Na/1000-K/100-sqrt(Mg)
#      ternary with Giggenbach (1988) Full-/Partial-Equilibrium/
#      Immature maturity zones and Na-K/K-Mg isotherms. Tests directly
#      whether these samples are equilibrated enough for the Na/K
#      geothermometer already reported throughout this proposal to be
#      trusted at face value -- a real, previously unexamined
#      assumption behind every Na/K number already used.
#   2. build_anion_ternary_figure() -- Cl-SO4-HCO3 ternary with
#      Giggenbach (1991) water-source zones (Mature/Steam-heated/
#      Peripheral). A second, independent cross-check of the Piper
#      diagram's water-type read (lst_map_and_piper_figures.R).
#
# Geometry (ternary_to_cartesian/ternary_frame/ternary_grid_lines) and
# the Giggenbach isotherm/zone math are ported directly from the IGNIS
# project's own hand-built utils_plotting.R
# (C:/Projects/IGNIS/IGNIS_Geochem_Database_Directory/R/utils_plotting.R,
# plot_ternary_giggenbach()/plot_ternary_anions(),
# classify_giggenbach()/classify_anion_ternary()), the same project and
# the same porting approach already used for this project's own Piper
# diagram (lst_map_and_piper_figures.R). Simplified relative to IGNIS:
# no prospect-based shape/fill aesthetic system (this project has a
# single prospect), just one point + label per sample, colored by
# feature type.
#
# Data source: this project's real, already-built PHREEQC_Solutions
# table (Na/K/Mg/Cl/SO4/Alkalinity, standardized mg/L, for the seven
# real flowpath samples) -- no new PHREEQC execution.
#
# Usage:
#   source("scripts/analysis/lst_ternary_diagrams.R")
#   build_lst_ternary_figures(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

source("scripts/analysis/plot_theme.R")

.FLOWPATH_SAMPLE_IDS <- c(816, 819, 821, 815, 825, 820, 822)

# meq/L equivalent weights (charge-equivalent factor = molar mass / valence)
.MEQ_FACTORS <- c(Cl = 35.45, SO4 = 48.03, HCO3 = 61.02)

# --- Ternary geometry helpers, ported verbatim from IGNIS ------------------

.ternary_to_cartesian <- function(top, right, left) {
  total <- top + right + left
  a <- top / total
  b <- right / total
  x <- 0.5 * (2 * b + a)
  y <- (sqrt(3) / 2) * a
  list(x = x, y = y)
}

.ternary_frame <- function() {
  tibble(x = c(0, 1, 0.5, 0), y = c(0, 0, sqrt(3) / 2, 0))
}

.ternary_grid_lines <- function() {
  grids <- list()
  h <- sqrt(3) / 2
  for (p in c(0.2, 0.4, 0.6, 0.8)) {
    grids[[length(grids) + 1]] <- tibble(x = c(p / 2, 1 - p / 2), y = c(p * h, p * h))
    grids[[length(grids) + 1]] <- tibble(x = c(p, (1 + p) / 2), y = c(0, (1 - p) * h))
    grids[[length(grids) + 1]] <- tibble(x = c(1 - p, (1 - p) / 2), y = c(0, (1 - p) * h))
  }
  grids
}

.flowpath_chemistry <- function(con) {
  dbGetQuery(con, sprintf("
    SELECT ps.sample_id, l.name AS location_name, ps.Na, ps.K, ps.Mg,
           ps.Cl, ps.SO4, ps.Alkalinity
    FROM PHREEQC_Solutions ps
    JOIN Samples s ON ps.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE ps.sample_id IN (%s)
  ", paste(.FLOWPATH_SAMPLE_IDS, collapse = ",")))
}

#' Giggenbach (1988) Na-K-sqrt(Mg) maturity ternary, built directly from
#' this project's real PHREEQC_Solutions chemistry for the seven real
#' flowpath samples.
build_giggenbach_ternary_figure <- function(con,
    out_png = "output/figures/manuscript/giggenbach_ternary.png") {

  df <- .flowpath_chemistry(con) |>
    filter(!is.na(Na), !is.na(K), !is.na(Mg)) |>
    mutate(Na_1000 = Na / 1000, K_100 = K / 100, Mg_sq = sqrt(Mg))

  if (nrow(df) == 0) {
    message("  -> No complete Na/K/Mg chemistry for the Giggenbach ternary. Skipping.")
    return(invisible(NULL))
  }

  tc <- .ternary_to_cartesian(df$Na_1000, df$Mg_sq, df$K_100)
  df$tx <- tc$x
  df$ty <- tc$y
  tri <- .ternary_frame()
  h3 <- sqrt(3) / 2

  # Maturity-index boundary curves (Giggenbach 1988: log(Na/K) = MI -
  # 0.315*log(K2/Mg) relationship, evaluated at MI = 2.0 and 2.66, the
  # conventional Full/Partial-Equilibrium boundaries).
  eq_temps <- seq(40, 360, by = 1)
  compute_curve <- function(mi_value) {
    intercept <- mi_value - 0.315 * 13.95
    slope <- 0.315 * 4410
    tibble(T_C = eq_temps) |>
      mutate(
        log_nak = intercept + slope / (T_C + 273.15),
        log_k2mg = 13.95 - 4410 / (T_C + 273.15),
        na_raw = 10^log_nak / 1000,
        mg_raw = 1 / sqrt(10^log_k2mg),
        k_raw = 1 / 100
      ) |>
      filter(is.finite(mg_raw), mg_raw > 0, is.finite(na_raw), na_raw > 0)
  }
  add_xy <- function(curve) {
    tc2 <- .ternary_to_cartesian(curve$na_raw, curve$mg_raw, curve$k_raw)
    curve$x <- tc2$x
    curve$y <- tc2$y
    curve
  }
  upper_curve <- add_xy(compute_curve(2.66))
  lower_curve <- add_xy(compute_curve(2.0))

  mg_vtx <- .ternary_to_cartesian(0, 1, 0)
  na_vtx <- .ternary_to_cartesian(1, 0, 0)
  k_vtx  <- .ternary_to_cartesian(0, 0, 1)

  fe_poly <- tibble(
    x = c(upper_curve$x, k_vtx$x, na_vtx$x, upper_curve$x[1]),
    y = c(upper_curve$y, k_vtx$y, na_vtx$y, upper_curve$y[1])
  )
  pe_poly <- tibble(
    x = c(upper_curve$x, rev(lower_curve$x)),
    y = c(upper_curve$y, rev(lower_curve$y))
  )

  p <- ggplot() +
    geom_polygon(data = fe_poly, aes(x, y), fill = "grey45", alpha = 0.12) +
    geom_polygon(data = pe_poly, aes(x, y), fill = "grey70", alpha = 0.10) +
    geom_path(data = tri, aes(x, y), color = "black", linewidth = 0.6) +
    geom_path(data = upper_curve, aes(x, y), color = "black", linewidth = 1.0) +
    geom_path(data = lower_curve, aes(x, y), color = "black", linewidth = 1.0) +
    annotate("text", x = 0.5, y = h3 * 0.92, label = "Full Equilibrium",
             size = 3.4, fontface = "bold.italic") +
    annotate("text", x = 0.62, y = h3 * 0.35, label = "Partial\nEquilibrium",
             size = 3.0, fontface = "bold.italic") +
    annotate("text", x = 0.85, y = 0.06, label = "Immature\nWaters",
             size = 3.0, fontface = "bold.italic") +
    annotate("text", x = 0.5, y = h3 + 0.05, label = "bold(Na/1000)", parse = TRUE, size = 3.5) +
    annotate("text", x = -0.05, y = -0.03, label = "bold(K/100)", parse = TRUE, size = 3.5) +
    annotate("text", x = 1.07, y = -0.03, label = 'bold(sqrt(Mg))', parse = TRUE, size = 3.5) +
    geom_point(data = df, aes(tx, ty, color = location_name), size = 3.2) +
    ggrepel::geom_text_repel(
      data = df, aes(tx, ty, label = location_name), size = 2.8,
      segment.size = 0.2, box.padding = 0.4, max.overlaps = 20
    ) +
    coord_fixed(clip = "off") +
    theme_steamboat() +
    theme(axis.title = element_blank(), axis.text = element_blank(),
          axis.ticks = element_blank(), panel.grid = element_blank(),
          legend.position = "none",
          plot.margin = margin(10, 40, 30, 20)) +
    labs(
      title = "Giggenbach Na-K-sqrt(Mg) ternary",
      subtitle = "Geothermal fluid maturity (Giggenbach 1988), real PHREEQC-conditioned chemistry",
      caption = sprintf("N = %d real flowpath samples. Grey band = Partial Equilibrium; white band above = Full Equilibrium.", nrow(df))
    )

  ggsave(out_png, p, width = 7.5, height = 6.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Cl-SO4-HCO3 (Giggenbach 1991) water-source ternary, built directly
#' from this project's real PHREEQC_Solutions chemistry for the seven
#' real flowpath samples. Alkalinity (this project's standard HCO3-mass-
#' equivalent code, per the project-wide convention established in
#' Sessions 15-16) stands in for HCO3 here.
build_anion_ternary_figure <- function(con,
    out_png = "output/figures/manuscript/anion_ternary.png") {

  df <- .flowpath_chemistry(con) |>
    filter(!is.na(Cl), !is.na(SO4), !is.na(Alkalinity)) |>
    mutate(
      Cl_meq   = Cl / .MEQ_FACTORS["Cl"],
      SO4_meq  = SO4 / .MEQ_FACTORS["SO4"],
      HCO3_meq = Alkalinity / .MEQ_FACTORS["HCO3"]
    )

  if (nrow(df) == 0) {
    message("  -> No complete Cl/SO4/Alkalinity chemistry for the anion ternary. Skipping.")
    return(invisible(NULL))
  }

  tc <- .ternary_to_cartesian(df$Cl_meq, df$SO4_meq, df$HCO3_meq)
  df$tx <- tc$x
  df$ty <- tc$y
  tri <- .ternary_grid_frame <- .ternary_frame()

  make_poly <- function(top_vals, right_vals, left_vals) {
    xs <- numeric(length(top_vals)); ys <- numeric(length(top_vals))
    for (i in seq_along(top_vals)) {
      pt <- .ternary_to_cartesian(top_vals[i], right_vals[i], left_vals[i])
      xs[i] <- pt$x; ys[i] <- pt$y
    }
    tibble(x = xs, y = ys)
  }
  mature_poly <- make_poly(c(1, 0.6, 0.6), c(0, 0.4, 0), c(0, 0, 0.4))
  steam_poly  <- make_poly(c(0, 0.4, 0), c(1, 0.6, 0.6), c(0, 0, 0.4))
  periph_poly <- make_poly(c(0, 0, 0.4), c(0, 0.4, 0), c(1, 0.6, 0.6))

  p <- ggplot() +
    geom_polygon(data = mature_poly, aes(x, y), fill = "#D55E00", alpha = 0.07) +
    geom_polygon(data = steam_poly, aes(x, y), fill = "#E69F00", alpha = 0.07) +
    geom_polygon(data = periph_poly, aes(x, y), fill = "#009E73", alpha = 0.07) +
    geom_path(data = .ternary_grid_frame, aes(x, y), color = "grey30", linewidth = 0.5) +
    annotate("text", x = mean(mature_poly$x), y = mean(mature_poly$y), label = "Mature\nWaters",
             size = 3.0, color = "#D55E00", fontface = "bold.italic", alpha = 0.7) +
    annotate("text", x = mean(steam_poly$x), y = mean(steam_poly$y), label = "Steam-\nheated",
             size = 3.0, color = "#E69F00", fontface = "bold.italic", alpha = 0.7) +
    annotate("text", x = mean(periph_poly$x), y = mean(periph_poly$y), label = "Peripheral\nWaters",
             size = 3.0, color = "#009E73", fontface = "bold.italic", alpha = 0.7) +
    annotate("text", x = 0.5, y = sqrt(3) / 2 + 0.05, label = "Cl", size = 3.4, fontface = "bold") +
    annotate("text", x = 1.07, y = -0.03, label = expression(bold(SO[4]^{"2-"})), size = 3.2) +
    annotate("text", x = -0.07, y = -0.03, label = expression(bold(HCO[3]^{"-"})), size = 3.2) +
    geom_point(data = df, aes(tx, ty, color = location_name), size = 3.2) +
    ggrepel::geom_text_repel(
      data = df, aes(tx, ty, label = location_name), size = 2.8,
      segment.size = 0.2, box.padding = 0.4, max.overlaps = 20
    ) +
    coord_fixed(clip = "off") +
    theme_steamboat() +
    theme(axis.title = element_blank(), axis.text = element_blank(),
          axis.ticks = element_blank(), panel.grid = element_blank(),
          legend.position = "none",
          plot.margin = margin(10, 40, 30, 20)) +
    labs(
      title = "Cl-SO4-HCO3 ternary",
      subtitle = "Water-source classification (Giggenbach 1991); Alkalinity stands in for HCO3",
      caption = sprintf("N = %d real flowpath samples, meq/L.", nrow(df))
    )

  ggsave(out_png, p, width = 7.5, height = 6.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

build_lst_ternary_figures <- function(con) {
  build_giggenbach_ternary_figure(con)
  build_anion_ternary_figure(con)
  invisible(TRUE)
}
