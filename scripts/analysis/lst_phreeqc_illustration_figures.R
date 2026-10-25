# ============================================================
# lst_phreeqc_illustration_figures.R
#
# Three new, publication-oriented figures illustrating the Lower Sinter
# Terrace gas-informed parent-fluid / mixing / flowpath PHREEQC work
# (scripts/phreeqc/15_gas_informed_parent_fluid.R,
# scripts/analysis/fluid_evolution_flowpath.R), built 2026-10-25 per
# direct request, complementing (not replacing) the existing
# parent_fluid_comparison.png / parent_fluid_database_sensitivity.png /
# fluid_evolution_flowpath.png / lst_conceptual_flowpath.png:
#
#   1. build_forward_mixing_validation_figure() -- tests whether real
#      target samples (SBW_0001, SBW_0002) fall on the real PHREEQC
#      MIX-block conservative-mixing curve (pure dilution) or deviate
#      from it (evidence of additional reaction). Uses the already-
#      computed PHREEQC_Mixing_Results sweep + each target's own real
#      PHREEQC_Results.
#   2. build_lst_flow_network_figure() -- a real ggraph/tidygraph
#      network diagram of the LST flow/mixing system, replacing the
#      flat box-and-line lst_conceptual_flowpath.png with an actual
#      directed graph, colored by fluid grouping (reconstructed parent
#      / measured thermal discharge / mixed / meteoric / downstream
#      creek / monitoring point) and annotated with real PHREEQC/mass-
#      balance quantities on each edge.
#   3. build_lst_aquifer_depth_profile_figure() -- a depth-profile
#      ("well-log") figure placing the real, historically documented
#      (White 1964, 1968) aquifer intervals at GS-1, the South
#      Steamboat well, and Steamboat well 4 alongside SBW_0001's own
#      complete absence of depth/completion data -- directly answering
#      "where are the aquifers along this flowpath" and "when do we
#      need well-log data here" (answer: now, for SBW_0001/SBW_0002).
#
# None of these are a live geophysical/well-log DATABASE query for (2)
# or (3) -- the aquifer intervals are literature values (White 1964,
# 1968, already read and cited in
# notebooks/07_historical_context_sorey1992.qmd section 4.7), hand-
# encoded here with full citation, not pulled from a structured Wells
# table column (because no such structured record exists yet -- this
# figure's own point is that it should).
#
# Usage:
#   source("scripts/analysis/lst_phreeqc_illustration_figures.R")
#   build_lst_phreeqc_illustration_figures(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(tidygraph)
library(ggraph)

source("scripts/analysis/plot_theme.R")

#' Figure 1: real target chemistry vs. the real PHREEQC conservative-
#' mixing curve.
build_forward_mixing_validation_figure <- function(con,
    out_png = "output/figures/manuscript/forward_mixing_model_validation.png") {

  curve <- dbGetQuery(con, "
    SELECT mixing_fraction_thermal, parameter, predicted_value
    FROM PHREEQC_Mixing_Results
    WHERE parameter IN ('SI_Calcite','SI_Dolomite','SI_Quartz','pH')
  ") |>
    filter(predicted_value > -900, parameter != "SI_Quartz") |>  # drop PHREEQC's undefined sentinel; quartz SI never defined along this run
    mutate(parameter_label = recode(parameter,
      SI_Calcite = "Calcite SI", SI_Dolomite = "Dolomite SI", pH = "pH"))

  if (nrow(curve) == 0) {
    message("  -> No PHREEQC_Mixing_Results found; run run_phreeqc_mixing_from_config()/15_gas_informed_parent_fluid.R first. Skipping.")
    return(invisible(NULL))
  }

  targets_raw <- dbGetQuery(con, "
    SELECT r.sample_id, r.parameter, r.value
    FROM PHREEQC_Results r
    WHERE r.sample_id IN (815, 821)
      AND r.parameter IN ('SI_Calcite','SI_Dolomite','pH')
  ")
  mix_frac <- c(`815` = 1.04415584415584, `821` = 0.555844155844156)  # from parent_fluid_mixing_comparison.csv (f_thermal_measured)
  targets <- targets_raw |>
    mutate(
      mixing_fraction_thermal = mix_frac[as.character(sample_id)],
      sample_label = ifelse(sample_id == 815, "SBW_0002 (resort tank)", "SBW_0001 (nearby LST well)"),
      parameter_label = recode(parameter, SI_Calcite = "Calcite SI", SI_Dolomite = "Dolomite SI", pH = "pH")
    )

  p <- ggplot(curve, aes(x = mixing_fraction_thermal, y = predicted_value)) +
    geom_line(color = "#0072B2", linewidth = 0.9) +
    geom_vline(xintercept = 1, linetype = "dotted", color = "grey60") +
    geom_point(data = targets, aes(x = mixing_fraction_thermal, y = value, color = sample_label), size = 3.5) +
    facet_wrap(~parameter_label, scales = "free_y", ncol = 3) +
    scale_color_manual(values = c("SBW_0002 (resort tank)" = "#D55E00", "SBW_0001 (nearby LST well)" = "#009E73"), name = NULL) +
    labs(
      x = "Conservative-Cl thermal mixing fraction (f = 0 meteoric, f = 1 thermal end-member)",
      y = "PHREEQC-predicted value",
      title = "Forward model: does real target chemistry fall on the pure-mixing curve?",
      subtitle = paste0(
        "Blue line: PHREEQC MIX-block prediction for pure conservative mixing (no reaction) between the\n",
        "reconstructed parent fluid and Boyd Domestic Well. Points: each target's own real, full-chemistry\n",
        "PHREEQC speciation, plotted at its own real measured mixing fraction."
      ),
      caption = paste0(
        "A point on the curve is consistent with simple dilution; a point off the curve implies additional\n",
        "reaction (precipitation/dissolution, degassing) beyond conservative mixing. Quartz SI omitted: PHREEQC\n",
        "did not report a defined quartz saturation index anywhere along this mixing run.\n",
        "Source: PHREEQC_Mixing_Results + PHREEQC_Results, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "top", plot.caption = element_text(hjust = 0))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11, height = 5.2, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Figure 2: a real ggraph network diagram of the LST flow/mixing
#' system (flow connections + chemical groupings).
build_lst_flow_network_figure <- function(
    out_png = "output/figures/manuscript/lst_flow_network_graph.png") {

  nodes <- tibble::tribble(
    ~name,            ~label_full,                                                         ~group,
    "parent_fissure", "Parent fluid\n(from fissure + NV26-1 gas)\nCl = 781 mg/L",            "Reconstructed parent",
    "parent_resort",  "Parent fluid\n(from resort tank + NV26-1 gas)\nCl = 797 mg/L",         "Reconstructed parent",
    "fissure",        "Fissure discharge\nSBF_0001\nCl = 815 mg/L",                           "Measured thermal discharge",
    "resort",         "Resort-tank discharge\nSBW_0002\nCl = 849 mg/L",                       "Measured thermal discharge",
    "nearby_well",    "Nearby LST well\nSBW_0001\nCl = 473 mg/L",                             "Mixed (thermal+meteoric)",
    "meteoric",       "Meteoric end-member\nBoyd Domestic Well\nCl = 45 mg/L",                "Meteoric end-member",
    "sbrr",           "Steamboat Creek\n@ SBRR\nCl = 17 mg/L",                                "Downstream creek",
    "sbbv",           "Steamboat Creek\n@ SBBV\nCl = 126 mg/L",                               "Downstream creek",
    "sbgg",           "SBGG logger /\nUSGS gauge",                                           "Monitoring point"
  )

  edges <- tibble::tribble(
    ~from,            ~to,            ~label,
    "parent_fissure", "fissure",      "steam loss 4.2%",
    "parent_resort",  "resort",       "steam loss 6.1%",
    "parent_fissure", "parent_resort","Cl agree within 2.1%",
    "fissure",        "nearby_well",  "shallow mixing",
    "resort",         "nearby_well",  "shallow mixing",
    "meteoric",       "nearby_well",  "dilution",
    "nearby_well",    "sbrr",         "f_thermal=0.56-0.58",
    "meteoric",       "sbrr",         "dilution",
    "sbrr",           "sbbv",         "+ ~100 gpm unseen\nLST inflow (White 1968)",
    "sbbv",           "sbgg",         ""
  )

  manual_xy <- tibble::tribble(
    ~name,            ~x,   ~y,
    "parent_fissure", 0,    2.2,
    "parent_resort",  0,    0.0,
    "fissure",        2.5,  2.2,
    "resort",         2.5,  0.0,
    "meteoric",       2.5,  4.8,
    "nearby_well",    5.0,  1.1,
    "sbrr",           7.4,  1.1,
    "sbbv",           10.4, 1.1,
    "sbgg",           12.9, 1.1
  )

  group_colors <- c(
    "Reconstructed parent" = "#0072B2",
    "Measured thermal discharge" = "#D55E00",
    "Mixed (thermal+meteoric)" = "#CC79A7",
    "Meteoric end-member" = "#56B4E9",
    "Downstream creek" = "#009E73",
    "Monitoring point" = "#999999"
  )

  nodes <- nodes |> left_join(manual_xy, by = "name")
  graph <- tbl_graph(nodes = nodes, edges = edges, directed = TRUE)
  lay <- create_layout(graph, layout = "manual", x = nodes$x, y = nodes$y)

  p <- ggraph(lay) +
    geom_edge_diagonal(aes(label = label), color = "grey55", linewidth = 0.6,
                        arrow = arrow(length = unit(3, "mm"), type = "closed"),
                        start_cap = rectangle(2.3, 0.85, "cm"), end_cap = rectangle(2.3, 0.85, "cm"),
                        label_size = 3.0, angle_calc = "along", label_dodge = unit(3, "mm"),
                        label_colour = "grey20") +
    geom_node_label(aes(label = label_full, fill = group), color = "white", fontface = "bold",
                     size = 2.9, label.padding = unit(0.35, "lines"), label.r = unit(0.12, "lines"),
                     lineheight = 0.9) +
    scale_fill_manual(values = group_colors, name = "Fluid grouping") +
    labs(
      title = "Lower Sinter Terrace flow network: real chemistry grouping and mixing connections",
      subtitle = "Edge labels give the real PHREEQC/mass-balance quantity linking each pair of points where available.",
      caption = "Source: scripts/phreeqc/15_gas_informed_parent_fluid.R, fluid_evolution_flowpath.R, geochem_operational.sqlite."
    ) +
    theme_graph(base_family = "sans") +
    theme(
      plot.title = element_text(face = "bold", size = 15),
      plot.subtitle = element_text(size = 11, color = "grey30"),
      plot.caption = element_text(size = 8.5, color = "grey40", hjust = 0),
      legend.position = "bottom"
    ) +
    expand_limits(x = c(min(nodes$x) - 1.8, max(nodes$x) + 1.8), y = c(min(nodes$y) - 1, max(nodes$y) + 1))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 16.5, height = 7.8, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Figure 3: real, literature-sourced (White 1964, 1968) aquifer/
#' completion-interval depth profile along the LST flowpath, with
#' SBW_0001's data gap shown explicitly.
build_lst_aquifer_depth_profile_figure <- function(
    out_png = "output/figures/manuscript/lst_aquifer_depth_profile.png") {

  wells_order <- c("GS-1\n(400 ft TD)", "South Steamboat well\n(~188 ft TD)",
                    "Steamboat well 4 /\nSBW_0002 (unconfirmed\nsame pad, 225 ft TD)",
                    "SBW_0001\n(no depth data on file)")
  well_x <- c(1, 5, 9, 13)
  names(well_x) <- wells_order
  bar_width <- 0.9

  total_depth <- tibble::tribble(
    ~well, ~depth,
    wells_order[1], 400,
    wells_order[2], 188,
    wells_order[3], 225
  )

  zones <- tibble::tribble(
    ~well, ~ymin, ~ymax, ~zone_type, ~zone_label,
    wells_order[1], 150, 399.5, "Thermal/aquifer", "Tuff-breccia\ndike aquifer",
    wells_order[2], 0,   160,   "Thermal/aquifer", "Saline thermal\n(75-95C)",
    wells_order[2], 160, 188,   "Meteoric",        "Dilute meteoric\n(Cl 6-8 ppm)",
    wells_order[3], 70,  80,    "Thermal/aquifer", "High-Cl zone"
  )

  points <- tibble::tribble(
    ~well, ~depth, ~label, ~kind,
    wells_order[1], 193, "Peak 158C\n(hottest point,\nLow Terrace)", "peak_temp",
    wells_order[3], 142, "Eruption\nonset", "eruption",
    wells_order[3], 58,  "Dilution zone", "dilution",
    wells_order[3], 105, "Dilution zone\n(major aquifer)", "dilution",
    wells_order[3], 184, "Peak BHT\n154.9C", "peak_temp"
  )

  zone_colors <- c("Thermal/aquifer" = "#D55E00", "Meteoric" = "#56B4E9")
  point_colors <- c("peak_temp" = "#B2182B", "eruption" = "#E69F00", "dilution" = "#2166AC")
  point_shapes <- c("peak_temp" = 18, "eruption" = 17, "dilution" = 16)

  p <- ggplot() +
    geom_rect(data = total_depth, aes(xmin = well_x[well] - bar_width, xmax = well_x[well] + bar_width,
                                       ymin = 0, ymax = depth), fill = "grey92", color = "grey60") +
    geom_rect(data = zones, aes(xmin = well_x[well] - bar_width, xmax = well_x[well] + bar_width,
                                 ymin = ymin, ymax = ymax, fill = zone_type), alpha = 0.92) +
    geom_text(data = zones, aes(x = well_x[well], y = (ymin + ymax) / 2, label = zone_label),
              size = 2.9, lineheight = 0.85, color = "white", fontface = "bold") +
    geom_point(data = points, aes(x = well_x[well] + bar_width + 0.5, y = depth, color = kind, shape = kind), size = 3.4) +
    geom_segment(data = points, aes(x = well_x[well] + bar_width, xend = well_x[well] + bar_width + 0.4,
                                     y = depth, yend = depth), color = "grey50", linewidth = 0.3) +
    geom_text(data = points, aes(x = well_x[well] + bar_width + 0.65, y = depth, label = label),
              hjust = 0, size = 2.7, lineheight = 0.85, color = "grey20") +
    annotate("rect", xmin = well_x[4] - bar_width, xmax = well_x[4] + bar_width, ymin = 0, ymax = 70,
             fill = NA, color = "grey40", linetype = "dashed", linewidth = 0.6) +
    annotate("text", x = well_x[4], y = 35, label = "?\nNo structured depth/\ncompletion data\non file",
             size = 3.1, color = "grey30", fontface = "italic", lineheight = 0.95) +
    scale_x_continuous(breaks = well_x, labels = names(well_x), position = "top", limits = c(-1.5, 17.5)) +
    scale_y_reverse(name = "Depth below ground surface (ft)", limits = c(430, -15)) +
    scale_fill_manual(values = zone_colors, name = "Zone type") +
    scale_color_manual(values = point_colors, guide = "none") +
    scale_shape_manual(values = point_shapes, name = "Named feature",
                        labels = c(peak_temp = "Peak temperature", eruption = "Eruption onset", dilution = "Dilution/major aquifer")) +
    labs(
      title = "Where are the aquifers? Real well-log evidence along the Lower Sinter Terrace flowpath",
      subtitle = paste0(
        "Depth intervals and features from White (1964, 1968)'s original drilling logs -- the only structured subsurface\n",
        "control this project currently has for any point on the real 2026 flowpath."
      ),
      caption = paste0(
        "SBW_0001 (a real 2026 sampling point on the flowpath) has NO depth, completion, or lithology data on file at all --\n",
        "the single biggest concrete gap for turning this flowpath into a real multi-aquifer mixing model. Steamboat well 4's\n",
        "identity as SBW_0002's feeding well is a plausible, NBMG-corroborated hypothesis, not confirmed.\n",
        "Source: White (1964, 1968), notebooks/07_historical_context_sorey1992.qmd section 4.7; Wells, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(
      axis.text.x = element_text(face = "bold", size = 9, lineheight = 0.9),
      axis.title.x = element_blank(),
      panel.grid.major.x = element_blank(),
      plot.caption = element_text(hjust = 0, size = 8)
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 12.5, height = 7.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Convenience wrapper: build all three.
build_lst_phreeqc_illustration_figures <- function(con) {
  build_forward_mixing_validation_figure(con)
  build_lst_flow_network_figure()
  build_lst_aquifer_depth_profile_figure()
  invisible(TRUE)
}
