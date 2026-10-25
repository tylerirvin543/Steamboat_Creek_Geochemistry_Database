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
#'
#' Restructured 2026-10-25 per direct user correction: the real
#' upgradient thermal sources are the fissure (sample 816, SBF_0001)
#' and the resort well (815, SBW_0002) -- their gas-informed parent-
#' fluid reconstructions already agree within ~2% Cl (session
#' 2026-10-24) -- and the real downgradient targets are the LST's own
#' discharge points: SBW_0001 (821, the across-creek well) and the
#' three real Lower Sinter Terrace springs SBS_0001/0002/0003
#' (825/820/822). "Hot spring 6" and GS-5 were considered and
#' explicitly rejected as targets: this project's own Locations record
#' labels the former "main terrace ACEC," and White (1964) states in
#' his own text that GS-3/GS-4/GS-5 are "drill holes on the Main
#' Terrace" -- neither is a Low Terrace feature.
#'
#' Meteoric/dilution reference: SBRR (sample 819, Steamboat Creek @
#' Rhodes Road), chosen per direct user correction over both Boyd
#' Domestic Well (implausible Ca/Mg, wrong-direction location) and
#' Jumbo Grade Spring (better chemistry fit, but no coordinate on file
#' at all -- "a random spring we don't know"). SBRR is real, precisely
#' located, and already extensively used elsewhere in this project, but
#' it is NOT a pure meteoric water: it carries a modest real thermal
#' signature of its own (Cl = 17.1 mg/L, field temperature 59.4 C),
#' consistent with sitting close to the thermal field itself. Using it
#' as the dilution end-member is therefore a conservative choice, not a
#' theoretically pure one -- stated plainly here and in every caption.
build_forward_mixing_validation_figure <- function(con,
    thermal_sample_id = 816, meteoric_sample_id = 819,
    target_sample_ids = c(821, 825, 820, 822),
    out_png = "output/figures/manuscript/forward_mixing_model_validation.png") {

  run_row <- dbGetQuery(con, "
    SELECT mixing_run_id FROM PHREEQC_Mixing_Runs
    WHERE thermal_end_member_id = ? AND meteoric_end_member_id = ?
    ORDER BY mixing_run_id DESC LIMIT 1
  ", params = list(thermal_sample_id, meteoric_sample_id))

  if (nrow(run_row) == 0) {
    message("  -> No PHREEQC_Mixing_Runs row for thermal=", thermal_sample_id,
            "/meteoric=", meteoric_sample_id, "; run run_phreeqc_mixing_from_config() first. Skipping.")
    return(invisible(NULL))
  }
  mixing_run_id <- run_row$mixing_run_id[1]

  curve <- dbGetQuery(con, "
    SELECT mixing_fraction_thermal, parameter, predicted_value
    FROM PHREEQC_Mixing_Results
    WHERE mixing_run_id = ? AND parameter IN ('SI_Calcite','SI_Dolomite','SI_Quartz','pH')
  ", params = list(mixing_run_id)) |>
    filter(predicted_value > -900, parameter != "SI_Quartz") |>  # drop PHREEQC's undefined sentinel; quartz SI never defined along this run
    mutate(parameter_label = recode(parameter,
      SI_Calcite = "Calcite SI", SI_Dolomite = "Dolomite SI", pH = "pH"))

  if (nrow(curve) == 0) {
    message("  -> No usable PHREEQC_Mixing_Results rows for mixing_run_id ", mixing_run_id, ". Skipping.")
    return(invisible(NULL))
  }

  target_labels <- c(`821` = "SBW_0001 (well, across creek)", `825` = "SBS_0001 (spring)",
                      `820` = "SBS_0002 (seep)", `822` = "SBS_0003 (spring)")

  frac <- dbGetQuery(con, "
    SELECT sample_id, mixing_fraction_thermal FROM PHREEQC_Mixing_Fractions
    WHERE mixing_run_id = ? AND sample_id IN (?,?,?,?)
  ", params = c(list(mixing_run_id), as.list(target_sample_ids)))

  targets_raw <- dbGetQuery(con, paste0("
    SELECT r.sample_id, r.parameter, r.value
    FROM PHREEQC_Results r
    WHERE r.sample_id IN (", paste(target_sample_ids, collapse = ","), ")
      AND r.parameter IN ('SI_Calcite','SI_Dolomite','pH')
  "))

  targets <- targets_raw |>
    left_join(frac, by = "sample_id") |>
    mutate(
      sample_label = target_labels[as.character(sample_id)],
      parameter_label = recode(parameter, SI_Calcite = "Calcite SI", SI_Dolomite = "Dolomite SI", pH = "pH")
    ) |>
    filter(!is.na(mixing_fraction_thermal))

  target_colors <- c(
    "SBW_0001 (well, across creek)" = "#D55E00",
    "SBS_0001 (spring)" = "#009E73",
    "SBS_0002 (seep)" = "#CC79A7",
    "SBS_0003 (spring)" = "#0072B2"
  )

  p <- ggplot(curve, aes(x = mixing_fraction_thermal, y = predicted_value)) +
    geom_line(color = "grey40", linewidth = 0.9) +
    geom_vline(xintercept = 1, linetype = "dotted", color = "grey60") +
    geom_point(data = targets, aes(x = mixing_fraction_thermal, y = value, color = sample_label), size = 3.2) +
    facet_wrap(~parameter_label, scales = "free_y", ncol = 3) +
    scale_color_manual(values = target_colors, name = "Real downgradient target") +
    labs(
      x = "Conservative-Cl thermal mixing fraction (f = 0 meteoric, f = 1 thermal end-member)",
      y = "PHREEQC-predicted value",
      title = "Forward model: do the real downgradient LST targets fall on the pure-mixing curve?",
      subtitle = paste0(
        "Grey line: PHREEQC MIX-block prediction for pure conservative mixing (no reaction) between the\n",
        "fissure (SBF_0001, sample 816) and SBRR (Steamboat Creek @ Rhodes Road, sample 819).\n",
        "Points: each real target's own full-chemistry PHREEQC speciation at its own real mixing fraction."
      ),
      caption = paste0(
        "Targets are the real downgradient LST discharge points (SBW_0001 + the three real LST springs), NOT hot\n",
        "spring 6/GS-5 (both confirmed Main Terrace, not Low Terrace -- excluded). SBRR replaces earlier Boyd\n",
        "Domestic Well/Jumbo Grade Spring choices -- a real, precisely located site, though itself not a pure\n",
        "meteoric water (Cl=17.1 mg/L, T=59.4C). Quartz SI omitted (never\n",
        "defined along this mixing run). Source: PHREEQC_Mixing_Results/Fractions + PHREEQC_Results, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "top", plot.caption = element_text(hjust = 0))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11.5, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Figure 2: a real ggraph network diagram of the LST flow/mixing
#' system (flow connections + chemical groupings).
#'
#' Restructured 2026-10-25 per direct user correction:
#'  - Flow direction now runs upgradient -> downgradient: the fissure
#'    (SBF_0001) and resort well (SBW_0002) sit spatially higher
#'    (elevation ~1408 m, upper Low Sinter Terrace, west side) and feed
#'    a shallow mixing zone that discharges to SBW_0001 (east side,
#'    across the creek, lower elevation ~1397 m -- presumed to tap an
#'    aquifer that passes beneath the creek despite sitting beside it)
#'    and the three real Low Terrace springs SBS_0001/0002/0003
#'    (elevations 1388-1400 m, a real, monotonic downgradient sequence).
#'  - Meteoric end-member changed from Boyd Domestic Well to Jumbo
#'    Grade Spring, with its unconfirmed southwest/west position noted
#'    directly in its own node label (no geolocated southwest/west
#'    groundwater sample exists in this project yet).
#'  - The Steamboat Creek chain is now geographically ordered SBRR ->
#'    SBGG -> SBBV (SBGG, Geiger Grade, sits well upstream of SBBV, not
#'    downstream of it as an earlier version of this figure had it),
#'    fed by the LST mixing zone collectively (not by any one target
#'    individually) via the same real "~100 gpm unseen inflow" estimate
#'    already used in the flowpath-evolution figure.
build_lst_flow_network_figure <- function(
    out_png = "output/figures/manuscript/lst_flow_network_graph.png") {

  nodes <- tibble::tribble(
    ~name,            ~label_full,                                                                 ~group,
    "parent_fissure", "Parent fluid\n(from fissure + NV26-1 gas)\nCl = 781 mg/L",                    "Reconstructed parent",
    "parent_resort",  "Parent fluid\n(from resort tank + NV26-1 gas)\nCl = 797 mg/L",                 "Reconstructed parent",
    "fissure",        "Fissure discharge\nSBF_0001 (upper LST, west side)\nCl = 815 mg/L, elev. 1408 m\nshallow vent + real lateral outflow\n(2025 thermal-IR, along-fissure heating)", "Measured thermal discharge",
    "resort",         "Resort-tank discharge\nSBW_0002 (upper LST, west side)\nCl = 849 mg/L, elev. 1409 m", "Measured thermal discharge",
    "mixing_zone",    "Shallow LST mixing/\ndegassing zone",                                          "Mixing zone",
    "meteoric",       "Dilution reference\n(SBRR water chemistry, sample 819)\nCl = 17 mg/L, T = 59C -- real but not\npurely meteoric; same real site as the\nSBRR node further right", "Meteoric end-member",
    "sbw1",           "SBW_0001\n(across creek, ag. field, elev. 1397 m)\nf_thermal = 0.58",          "Downgradient target",
    "sbs2",           "SBS_0002 (seep)\nelev. 1400 m, f_thermal = 0.78",                              "Downgradient target",
    "sbs1",           "SBS_0001 (spring)\nelev. 1397 m, f_thermal = 0.89",                            "Downgradient target",
    "sbs3",           "SBS_0003 (spring, lowest)\nelev. 1389 m, f_thermal = 0.85",                    "Downgradient target",
    "sbrr",           "Steamboat Creek\n@ SBRR (upstream control)\nCl = 17 mg/L",                     "Downstream creek",
    "sbgg",           "SBGG logger\n(Geiger Grade)",                                                  "Monitoring point",
    "sbbv",           "Steamboat Creek\n@ SBBV\nCl = 126 mg/L",                                       "Downstream creek"
  )

  edges <- tibble::tribble(
    ~from,            ~to,            ~label,
    "parent_fissure", "fissure",      "steam loss 4.2%",
    "parent_resort",  "resort",       "steam loss 6.1%",
    "parent_fissure", "parent_resort","Cl agree within 2.1%",
    "fissure",        "mixing_zone",  "",
    "resort",         "mixing_zone",  "",
    "meteoric",       "mixing_zone",  "dilution",
    "mixing_zone",    "sbw1",         "",
    "mixing_zone",    "sbs2",         "",
    "mixing_zone",    "sbs1",         "",
    "mixing_zone",    "sbs3",         "",
    "mixing_zone",    "sbrr",         "+ ~100 gpm unseen\nLST inflow (White 1968)",
    "sbrr",           "sbgg",         "",
    "sbgg",           "sbbv",         ""
  )

  manual_xy <- tibble::tribble(
    ~name,            ~x,   ~y,
    "parent_fissure", 0,    2.2,
    "parent_resort",  0,    0.0,
    "fissure",        2.3,  2.2,
    "resort",         2.3,  0.0,
    "meteoric",       2.3,  4.6,
    "mixing_zone",    4.8,  2.2,
    "sbw1",           7.3,  4.4,
    "sbs2",           7.3,  2.9,
    "sbs1",           7.3,  1.4,
    "sbs3",           7.3, -0.1,
    "sbrr",           9.8,  2.2,
    "sbgg",           12.3, 2.2,
    "sbbv",           14.8, 2.2
  )

  group_colors <- c(
    "Reconstructed parent" = "#0072B2",
    "Measured thermal discharge" = "#D55E00",
    "Mixing zone" = "#E69F00",
    "Downgradient target" = "#CC79A7",
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
      title = "Lower Sinter Terrace flow network: upgradient sources to downgradient springs/well",
      subtitle = paste0(
        "Flow runs upgradient (fissure/resort well, upper LST, west side) to downgradient (SBW_0001 across\n",
        "the creek, and the three real LST springs). SBGG sits upstream of SBBV. Edge labels give real\n",
        "PHREEQC/mass-balance quantities where available."
      ),
      caption = paste0(
        "Dilution reference: SBRR's own real water chemistry (sample 819), not Boyd Domestic Well or Jumbo Grade\n",
        "Spring -- a real, precisely located site, though SBRR itself carries a modest real thermal signature\n",
        "(Cl=17.1 mg/L, T=59.4C) and is therefore a conservative, not a theoretically pure, dilution reference.\n",
        "Source: scripts/phreeqc/15_gas_informed_parent_fluid.R, fluid_evolution_flowpath.R, geochem_operational.sqlite."
      )
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
  ggsave(out_png, p, width = 17, height = 9.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Figure 3: real, literature-sourced (White 1964, 1968) aquifer/
#' completion-interval depth profile along the LST flowpath, with
#' SBW_0001's data gap shown explicitly.
build_lst_aquifer_depth_profile_figure <- function(
    out_png = "output/figures/manuscript/lst_aquifer_depth_profile.png") {

  # Ordered south-to-north (real latitude): South Steamboat Well (39.3779)
  # < GS-1 (39.3789) < SBW_0002/Steamboat well 4 (39.3797) < SBW_0001
  # (39.3806) < SBF_0001, the fissure (39.3824, farther north but west of
  # SBW_0001) -- per direct user correction 2026-10-25.
  wells_order <- c("South Steamboat well\n(~188 ft TD)", "GS-1\n(400 ft TD)",
                    "Steamboat well 4 /\nSBW_0002 (unconfirmed\nsame pad, 225 ft TD)",
                    "SBW_0001\n(no depth data on file)",
                    "SBF_0001 fissure\n(farther north, west side;\nno depth data on file)")
  well_x <- c(1, 5, 9, 13, 17)
  names(well_x) <- wells_order
  bar_width <- 0.9

  total_depth <- tibble::tribble(
    ~well, ~depth,
    wells_order[1], 188,
    wells_order[2], 400,
    wells_order[3], 225
  )

  zones <- tibble::tribble(
    ~well, ~ymin, ~ymax, ~zone_type, ~zone_label,
    wells_order[1], 0,   160,   "Thermal/aquifer", "Saline thermal\n(75-95C)",
    wells_order[1], 160, 188,   "Meteoric",        "Dilute meteoric\n(Cl 6-8 ppm)",
    wells_order[2], 150, 399.5, "Thermal/aquifer", "Tuff-breccia\ndike aquifer",
    wells_order[3], 70,  80,    "Thermal/aquifer", "High-Cl zone"
  )

  points <- tibble::tribble(
    ~well, ~depth, ~label, ~kind,
    wells_order[2], 193, "Peak 158C\n(hottest point,\nLow Terrace)", "peak_temp",
    wells_order[3], 142, "Eruption\nonset", "eruption",
    wells_order[3], 58,  "Dilution zone", "dilution",
    wells_order[3], 105, "Dilution zone\n(major aquifer)", "dilution",
    wells_order[3], 184, "Peak BHT\n154.9C", "peak_temp"
  )

  no_data_wells <- c(wells_order[4], wells_order[5])

  zone_colors <- c("Thermal/aquifer" = "#D55E00", "Meteoric" = "#56B4E9")
  point_colors <- c("peak_temp" = "#B2182B", "eruption" = "#E69F00", "dilution" = "#2166AC")
  point_shapes <- c("peak_temp" = 18, "eruption" = 17, "dilution" = 16)

  no_data_df <- tibble::tibble(well = no_data_wells, x = well_x[no_data_wells])

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
    geom_rect(data = no_data_df, aes(xmin = x - bar_width, xmax = x + bar_width, ymin = 0, ymax = 70),
              fill = NA, color = "grey40", linetype = "dashed", linewidth = 0.6) +
    geom_text(data = no_data_df, aes(x = x, y = 35), label = "?\nNo structured depth/\ncompletion data\non file",
              size = 3.1, color = "grey30", fontface = "italic", lineheight = 0.95) +
    scale_x_continuous(breaks = well_x, labels = names(well_x), position = "top", limits = c(-1.5, 21.5)) +
    scale_y_reverse(name = "Depth below ground surface (ft)", limits = c(430, -15)) +
    scale_fill_manual(values = zone_colors, name = "Zone type") +
    scale_color_manual(values = point_colors, guide = "none") +
    scale_shape_manual(values = point_shapes, name = "Named feature",
                        labels = c(peak_temp = "Peak temperature", eruption = "Eruption onset", dilution = "Dilution/major aquifer")) +
    labs(
      title = "Where are the aquifers? Real well-log evidence along the Lower Sinter Terrace flowpath",
      subtitle = paste0(
        "Ordered south to north by real latitude. Depth intervals and features from White (1964, 1968)'s\n",
        "original drilling logs -- the only structured subsurface control this project currently has for any point\n",
        "on the real 2026 flowpath."
      ),
      caption = paste0(
        "Both SBW_0001 and the fissure (SBF_0001) -- real 2026 sampling points on the flowpath -- have NO depth,\n",
        "completion, or lithology data on file at all. Steamboat well 4's identity as SBW_0002's feeding well is a\n",
        "plausible, NBMG-corroborated hypothesis, not confirmed.\n",
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
  ggsave(out_png, p, width = 15, height = 7.5, dpi = 300)
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
