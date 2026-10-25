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
#' signature of its own (Cl = 17.1 mg/L); its field temperature was
#' originally recorded as 59.4 C but corrected to 15.2 C after a
#' project-wide Fahrenheit/Celsius field-thermometer bug fix (see
#' AGENTS.md) -- a normal creek temperature, not an elevated one. The
#' Cl-based argument for a conservative (not pure) meteoric end-member
#' still holds; the temperature-based part of it does not.
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
        "meteoric water (Cl=17.1 mg/L, T=15.2C, not 59.4C as first reported). Quartz SI omitted (never\n",
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
        "(Cl=17.1 mg/L, T=15.2C, not 59.4C as first reported) and is therefore a conservative, not a theoretically pure, dilution reference.\n",
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



#' Small helper: real Locations.name for a sample_id (falls back to a
#' bare "sample_id N" string if not found) -- used so subtitles/titles
#' read real site names for ANY thermal/meteoric/target combination,
#' not just the four hardcoded in earlier versions of this figure.
.sample_location_name <- function(con, sample_id) {
  nm <- dbGetQuery(con, "
    SELECT l.name FROM Samples s JOIN Locations l ON s.location_id = l.location_id
    WHERE s.sample_id = ?
  ", params = list(sample_id))
  if (nrow(nm) == 0 || is.na(nm$name[1])) paste0("sample_id ", sample_id) else nm$name[1]
}

#' Figure 4: forward REACTION-path titration -- does titrating the given
#' candidate phase(s) into the fissure+SBRR (or an alternate end-member)
#' mixing line reconcile a real target's chemistry, where PHREEQC's own
#' inverse-modeling search (every real attempt on file) finds zero
#' feasible solutions?
#'
#' Built 2026-10-25, generalized 2026-10-25 (same day, follow-on session)
#' to work for ANY real target/phase-set/meteoric-end-member combination
#' stored in PHREEQC_Reaction_Path_Runs -- panels are built dynamically
#' from (a) whichever elements the run's own phase list actually
#' consumes (.REACTION_PATH_PHASE_STOICHIOMETRY) and (b) one
#' saturation-index panel per titrated phase actually present in the
#' output, rather than a hardcoded Ca/Mg/Alkalinity/SI_Calcite/
#' SI_Dolomite list. Overlays the target's own real observed value as a
#' horizontal reference line per element panel (SI panels get none --
#' it's a derived quantity, not a lab value), and marks the best-fit
#' reaction progress with a vertical line.
build_reaction_path_titration_figure <- function(con, run_id = NULL, target_sample_id = 821,
    out_png = "output/figures/manuscript/reaction_path_titration.png") {

  if (is.null(run_id)) {
    run_row <- dbGetQuery(con, "
      SELECT run_id FROM PHREEQC_Reaction_Path_Runs
      WHERE target_sample_id = ? ORDER BY run_id DESC LIMIT 1
    ", params = list(target_sample_id))
    if (nrow(run_row) == 0) {
      message("  -> No PHREEQC_Reaction_Path_Runs row for target_sample_id ", target_sample_id,
              "; run run_phreeqc_reaction_path_from_config() first. Skipping.")
      return(invisible(NULL))
    }
    run_id <- run_row$run_id[1]
  }

  run_info <- dbGetQuery(con, "SELECT * FROM PHREEQC_Reaction_Path_Runs WHERE run_id = ?", params = list(run_id))
  if (nrow(run_info) == 0) { message("  -> No run_id ", run_id, " found. Skipping."); return(invisible(NULL)) }
  phases_in_run <- trimws(strsplit(run_info$phases[1], ",")[[1]])

  all_steps <- dbGetQuery(con, "
    SELECT step_index, reaction_progress_mol, parameter, value
    FROM PHREEQC_Reaction_Path_Steps WHERE run_id = ?
  ", params = list(run_id))
  if (nrow(all_steps) == 0) { message("  -> No PHREEQC_Reaction_Path_Steps rows for run_id ", run_id, ". Skipping."); return(invisible(NULL)) }

  # Candidate element panels: whichever of Ca/Mg/Alkalinity/SO4/F this
  # run's own phase list actually consumes, translated to the real Steps
  # parameter key (only SO4 differs, stored as "S_6_").
  consumed_elements <- unique(unlist(lapply(phases_in_run, function(p) {
    row <- .REACTION_PATH_PHASE_STOICHIOMETRY[[p]]
    if (is.null(row)) character() else names(row)
  })))
  if (length(consumed_elements) == 0) consumed_elements <- c("Ca", "Mg", "Alkalinity")  # fallback for an unrecognized phase list
  element_step_keys <- .REACTION_PATH_STEP_PARAM_KEY[consumed_elements]
  element_step_keys <- element_step_keys[element_step_keys %in% all_steps$parameter]

  # SI panels: one per titrated phase actually present in the output.
  si_keys <- paste0("SI_", phases_in_run)
  si_keys <- si_keys[si_keys %in% all_steps$parameter]

  keep_keys <- c(unname(element_step_keys), si_keys)
  steps <- all_steps |> filter(parameter %in% keep_keys)
  if (nrow(steps) == 0) { message("  -> No plottable parameters found for run_id ", run_id, ". Skipping."); return(invisible(NULL)) }

  element_labels <- c(Ca = "Ca (mol/kgw)", Mg = "Mg (mol/kgw)", Alkalinity = "Alkalinity (mol/kgw, as HCO3)",
                       SO4 = "SO4 (mol/kgw, as S(6))", F = "F (mol/kgw)")
  panel_labels <- c(
    setNames(element_labels[names(element_step_keys)], unname(element_step_keys)),
    setNames(paste0(phases_in_run, " SI"), si_keys)
  )
  panel_levels <- unique(unname(panel_labels)[match(keep_keys, names(panel_labels))])
  steps <- steps |> mutate(parameter_label = factor(panel_labels[parameter], levels = panel_levels))

  # Real observed reference lines for every element panel present.
  target_row <- dbGetQuery(con, "SELECT * FROM PHREEQC_Solutions WHERE sample_id = ?", params = list(target_sample_id))
  obs_lines <- tibble::tibble(solutions_name = names(element_step_keys)) |>
    mutate(
      step_key = unname(element_step_keys[solutions_name]),
      value = sapply(solutions_name, function(p) {
        v <- target_row[[p]][1]
        if (is.null(v) || is.na(v)) NA_real_ else v / 1000 / .REACTION_PATH_MW[[p]]
      })
    ) |>
    filter(!is.na(value)) |>
    mutate(parameter_label = factor(panel_labels[step_key], levels = panel_levels))

  fit <- tryCatch(summarize_reaction_path_fit(con, run_id, target_sample_id = target_sample_id,
                                               fit_parameters = names(element_step_keys)),
                   error = function(e) { message("  -> summarize_reaction_path_fit() failed: ", conditionMessage(e)); NULL })
  best_x <- if (!is.null(fit) && !is.null(fit$best_fit) && nrow(fit$best_fit) > 0) fit$best_fit$reaction_progress_mol[1] else NA_real_

  target_name <- .sample_location_name(con, target_sample_id)
  thermal_name <- .sample_location_name(con, run_info$thermal_sample_id[1])
  meteoric_name <- .sample_location_name(con, run_info$meteoric_sample_id[1])
  phases_str <- paste(phases_in_run, collapse = " + ")
  n_panel <- length(panel_levels)
  ncol_use <- min(3, max(n_panel, 1))

  p <- ggplot(steps, aes(x = reaction_progress_mol, y = value)) +
    geom_line(color = "#D55E00", linewidth = 0.9) +
    geom_hline(data = obs_lines, aes(yintercept = value), linetype = "dashed", color = "grey30") +
    { if (is.finite(best_x)) geom_vline(xintercept = best_x, linetype = "dotted", color = "#0072B2", linewidth = 0.8) } +
    facet_wrap(~parameter_label, scales = "free_y", ncol = ncol_use) +
    labs(
      x = paste0("Net reaction progress titrated (mol of ", phases_str, "; negative = net precipitation, positive = net dissolution)"),
      y = NULL,
      title = paste0("Forward REACTION-path titration: can ", phases_str, " mass transfer reconcile ", target_name, "?"),
      subtitle = stringr::str_wrap(paste0(
        "Orange line: PHREEQC's own modeled trajectory, titrating the ", thermal_name, "(", run_info$thermal_sample_id[1],
        ")+", meteoric_name, "(", run_info$meteoric_sample_id[1], ") conservative mix at its real mixing fraction (",
        round(run_info$mixing_fraction_thermal[1], 3), "). Dashed grey: the target's own real observed value. ",
        "Dotted blue: the best-fit reaction progress."
      ), width = 105),
      caption = paste0(
        "run_id ", run_id, "; phases = ", phases_str, "; thermal = ", run_info$thermal_sample_id[1],
        "; meteoric = ", run_info$meteoric_sample_id[1], ". Source: PHREEQC_Reaction_Path_Runs/Steps, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 8))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 12.5, height = max(4, ceiling(n_panel / ncol_use) * 3.2), dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}


#' Figure 5: forward REACTION-path titration summary -- does the earlier,
#' SI/pH-based read ("the three real LST springs sit much closer to the
#' pure-mixing curve than SBW_0001") hold up once the SAME forward
#' titration method is run against each one directly, using real
#' Ca/Mg/Alkalinity mass balance rather than just SI/pH?
#'
#' Built 2026-10-25 as the direct follow-on once the SBW_0001 titration
#' was complete (flagged in ROADMAP.md/manuscript/
#' 05_discussion_and_future_work.qmd as the concrete next step). Reads
#' every stored PHREEQC_Reaction_Path_Runs/Steps combination for the
#' given targets, computes the combined Ca/Mg/Alkalinity RMSE at (a) the
#' step closest to zero reaction progress (pure conservative mixing, no
#' reaction) and (b) the real best-fit reaction progress, and plots both
#' as a dumbbell per target -- directly showing how much, if at all,
#' titrating calcite/dolomite improves the fit for each real downgradient
#' point.
build_reaction_path_fit_comparison_figure <- function(con,
    target_sample_ids = c(821, 825, 820, 822, 815),
    out_png = "output/figures/manuscript/reaction_path_fit_comparison.png") {

  target_labels <- c(`821` = "SBW_0001 (well, across creek)", `825` = "SBS_0001 (spring)",
                      `820` = "SBS_0002 (seep)", `822` = "SBS_0003 (spring)",
                      `815` = "SBW_0002 (resort tank, clamped f=1.0)")

  rows <- lapply(target_sample_ids, function(sid) {
    run_row <- dbGetQuery(con, "
      SELECT run_id FROM PHREEQC_Reaction_Path_Runs
      WHERE target_sample_id = ? ORDER BY run_id DESC LIMIT 1
    ", params = list(sid))
    if (nrow(run_row) == 0) {
      message("  -> No PHREEQC_Reaction_Path_Runs row for target_sample_id ", sid, " -- skipping from comparison.")
      return(NULL)
    }
    run_id <- run_row$run_id[1]
    steps <- dbGetQuery(con, "
      SELECT step_index, reaction_progress_mol, parameter, value
      FROM PHREEQC_Reaction_Path_Steps
      WHERE run_id = ? AND parameter IN ('Ca','Mg','Alkalinity')
    ", params = list(run_id))
    if (nrow(steps) == 0) return(NULL)

    target_row <- dbGetQuery(con, "SELECT * FROM PHREEQC_Solutions WHERE sample_id = ?", params = list(sid))
    mw <- c(Ca = 40.078, Mg = 24.305, Alkalinity = 61.017)
    obs_mol <- sapply(names(mw), function(p) {
      v <- target_row[[p]][1]
      if (is.null(v) || is.na(v)) NA_real_ else v / 1000 / mw[[p]]
    })

    wide <- steps |>
      tidyr::pivot_wider(id_cols = c(step_index, reaction_progress_mol), names_from = parameter, values_from = value)
    pct_mat <- sapply(names(mw), function(p) {
      if (is.na(obs_mol[[p]]) || !(p %in% names(wide))) return(rep(NA_real_, nrow(wide)))
      100 * (wide[[p]] - obs_mol[[p]]) / obs_mol[[p]]
    })
    rmse <- sqrt(rowMeans(pct_mat^2, na.rm = TRUE))
    wide$combined_rmse_pct <- rmse

    zero_row <- wide[which.min(abs(wide$reaction_progress_mol)), ]
    best_row <- wide[which.min(wide$combined_rmse_pct), ]

    tibble::tibble(
      sample_id = sid,
      target_label = target_labels[[as.character(sid)]],
      pure_mixing_rmse_pct = zero_row$combined_rmse_pct[1],
      best_fit_rmse_pct = best_row$combined_rmse_pct[1],
      best_fit_reaction_progress_mol = best_row$reaction_progress_mol[1]
    )
  })
  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) { message("  -> No real reaction-path runs found for any target. Skipping comparison figure."); return(invisible(NULL)) }
  summary_tbl <- dplyr::bind_rows(rows) |> dplyr::arrange(best_fit_rmse_pct)

  plot_df <- summary_tbl |>
    tidyr::pivot_longer(cols = c(pure_mixing_rmse_pct, best_fit_rmse_pct), names_to = "stage", values_to = "rmse_pct") |>
    dplyr::mutate(
      stage_label = ifelse(stage == "pure_mixing_rmse_pct", "Pure conservative mixing (no reaction)", "Best-fit reaction progress"),
      target_label = factor(target_label, levels = summary_tbl$target_label)
    )

  p <- ggplot(plot_df, aes(x = rmse_pct, y = target_label)) +
    geom_line(aes(group = target_label), color = "grey60", linewidth = 1) +
    geom_point(aes(color = stage_label), size = 4) +
    scale_color_manual(values = c("Pure conservative mixing (no reaction)" = "#999999", "Best-fit reaction progress" = "#D55E00"),
                        name = NULL) +
    labs(
      x = "Combined Ca/Mg/Alkalinity RMSE (%, lower is a better fit)",
      y = NULL,
      title = "Does titrating calcite/dolomite actually help, for each real downgradient target?",
      subtitle = paste0(
        "Grey: fit quality at pure conservative mixing (fissure+SBRR, no reaction). Orange: fit quality at each
",
        "target's own real best-fit reaction progress (forward REACTION-path titration)."
      ),
      caption = paste0(
        "SBW_0001 needs by far the largest reaction-progress correction and shows the largest improvement, but SBS_0001
",
        "(a real Low Sinter Terrace spring) shows the WORST fit of all four even after titration -- the earlier SI/pH-only
",
        "read (forward_mixing_model_validation.png) that the three springs uniformly sit close to the mixing curve does not
",
        "fully hold up once real Ca/Mg/Alkalinity mass balance is checked directly. SBS_0002 needs almost no correction;
",
        "SBS_0003 needs a small one. Source: PHREEQC_Reaction_Path_Runs/Steps, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "top", plot.caption = element_text(hjust = 0, size = 8))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 10, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)

  out_csv <- "data/derived/phreeqc/reaction_path_fit_comparison.csv"
  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(summary_tbl, out_csv, row.names = FALSE)
  message("  -> Wrote ", out_csv)

  invisible(list(plot = p, table = summary_tbl))
}



#' Figure 6: SBS_0001 sensitivity test -- does adding a sulfate/fluoride
#' phase, or using a different (higher-sulfate) meteoric end-member,
#' actually resolve the real calcium/alkalinity tension found in the
#' baseline fissure+SBRR+Calcite+Dolomite titration (Figure 5/
#' reaction_path_fit_comparison.png)?
#'
#' Built 2026-10-25 (same-day follow-on) per direct request to test two
#' concrete, grounded hypotheses: SBS_0001 has the highest SO4 (187 mg/L)
#' and lowest Alkalinity of the four real downgradient targets -- the
#' classic gypsum/anhydrite signature a carbonate-only titration cannot
#' produce -- and/or SBS_0001 may mix with a different, higher-sulfate
#' shallow water than the other targets. Reads every stored
#' PHREEQC_Reaction_Path_Runs/Steps combination for sample 825 (SBS_0001)
#' and plots best-fit combined RMSE across every real variant tested:
#' the baseline, three phase-set variants (+Anhydrite, +Gypsum,
#' +Anhydrite+Fluorite), two alternate-meteoric variants (Tick Spring,
#' Jumbo Grade Spring), and one combined variant. Reports the real
#' outcome, whatever it is -- neither hypothesis is guaranteed (or found)
#' to fully resolve the tension.
build_sbs0001_sensitivity_figure <- function(con,
    out_png = "output/figures/manuscript/sbs0001_sensitivity_comparison.png") {

  variants <- tibble::tribble(
    ~variant_label,                                  ~thermal_sample_id, ~meteoric_sample_id, ~phases,
    "Baseline (Calcite+Dolomite, SBRR)",              816, 819, "Calcite,Dolomite",
    "+ Anhydrite (SBRR)",                             816, 819, "Calcite,Dolomite,Anhydrite",
    "+ Gypsum (SBRR)",                                816, 819, "Calcite,Dolomite,Gypsum",
    "+ Anhydrite + Fluorite (SBRR)",                  816, 819, "Calcite,Dolomite,Anhydrite,Fluorite",
    "Alt. meteoric: Tick Spr. (Calcite+Dolomite)",    816, 919, "Calcite,Dolomite",
    "Alt. meteoric: Jumbo Gr. S. (Calcite+Dolomite)", 816, 920, "Calcite,Dolomite",
    "Combined: Anhydrite+Fluorite + Tick Spr.",       816, 919, "Calcite,Dolomite,Anhydrite,Fluorite"
  )

  rows <- lapply(seq_len(nrow(variants)), function(i) {
    v <- variants[i, ]
    run_row <- dbGetQuery(con, "
      SELECT run_id FROM PHREEQC_Reaction_Path_Runs
      WHERE target_sample_id = 825 AND thermal_sample_id = ? AND meteoric_sample_id = ? AND phases = ?
      ORDER BY run_id DESC LIMIT 1
    ", params = list(v$thermal_sample_id, v$meteoric_sample_id, v$phases))
    if (nrow(run_row) == 0) {
      message("  -> No matching run for variant ", v$variant_label, " -- skipping from sensitivity figure.")
      return(NULL)
    }
    run_id <- run_row$run_id[1]
    fit <- tryCatch(summarize_reaction_path_fit(con, run_id, target_sample_id = 825), error = function(e) NULL)
    if (is.null(fit) || is.null(fit$best_fit) || nrow(fit$best_fit) == 0) return(NULL)
    tibble::tibble(variant_label = v$variant_label, run_id = run_id,
                   best_rmse_pct = fit$best_fit$combined_rmse_pct[1],
                   best_reaction_progress_mol = fit$best_fit$reaction_progress_mol[1])
  })
  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) { message("  -> No SBS_0001 sensitivity-test runs found. Skipping figure."); return(invisible(NULL)) }
  summary_tbl <- dplyr::bind_rows(rows) |> dplyr::arrange(desc(best_rmse_pct))
  summary_tbl$variant_label <- factor(summary_tbl$variant_label, levels = summary_tbl$variant_label)

  p <- ggplot(summary_tbl, aes(x = best_rmse_pct, y = variant_label)) +
    geom_col(aes(fill = grepl("^Baseline", variant_label)), width = 0.6) +
    geom_text(aes(label = sprintf("%.1f%%", best_rmse_pct)), hjust = -0.15, size = 3.5) +
    scale_fill_manual(values = c(`TRUE` = "grey60", `FALSE` = "#D55E00"), guide = "none") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      x = "Best-fit combined Ca/Mg/Alkalinity RMSE (%, lower is a better fit)",
      y = NULL,
      title = "Does a sulfate phase or a different meteoric end-member resolve SBS_0001 real tension?",
      subtitle = paste0(
        "SBS_0001 has the highest SO4 (187 mg/L) and lowest Alkalinity of the four real downgradient targets -- the
",
        "classic gypsum/anhydrite signature a carbonate-only titration cannot produce. Tested here against the real baseline."
      ),
      caption = paste0(
        "Every variant improves on the baseline somewhat, but none fully resolves it. The best single result (Tick Spr.
",
        "meteoric end-member, 33.4%) is still worse than SBS_0002 (39.4%) or SBS_0003 (19.7%) own baseline fits, and the
",
        "combined test (both hypotheses together) does not improve further on Tick Spring alone -- the improvements do not
",
        "simply stack. Tick Spring and Jumbo Grade Spring have real chemistry but no coordinate on file (same limitation
",
        "documented project-wide). Source: PHREEQC_Reaction_Path_Runs/Steps, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 8))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 10.5, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)

  out_csv <- "data/derived/phreeqc/sbs0001_sensitivity_comparison.csv"
  write.csv(summary_tbl, out_csv, row.names = FALSE)
  message("  -> Wrote ", out_csv)

  invisible(list(plot = p, table = summary_tbl))
}


#' Convenience wrapper: build the full LST illustration figure set.
build_lst_phreeqc_illustration_figures <- function(con) {
  build_forward_mixing_validation_figure(con)
  build_lst_flow_network_figure()
  build_lst_aquifer_depth_profile_figure()
  build_reaction_path_titration_figure(con, target_sample_id = 821)
  # The baseline (Calcite+Dolomite, SBRR) run, not whichever variant was
  # most recently run -- the sensitivity-test variants (Anhydrite/Gypsum/
  # Fluorite/alternate meteoric end-members) are covered by
  # build_sbs0001_sensitivity_figure() below, not this per-target figure.
  sbs0001_baseline_run <- dbGetQuery(con, "
    SELECT run_id FROM PHREEQC_Reaction_Path_Runs
    WHERE target_sample_id = 825 AND meteoric_sample_id = 819 AND phases = 'Calcite,Dolomite'
    ORDER BY run_id DESC LIMIT 1
  ")$run_id[1]
  build_reaction_path_titration_figure(con, run_id = sbs0001_baseline_run, target_sample_id = 825,
      out_png = "output/figures/manuscript/reaction_path_titration_sbs0001.png")
  build_reaction_path_titration_figure(con, target_sample_id = 820,
      out_png = "output/figures/manuscript/reaction_path_titration_sbs0002.png")
  build_reaction_path_titration_figure(con, target_sample_id = 822,
      out_png = "output/figures/manuscript/reaction_path_titration_sbs0003.png")
  build_reaction_path_titration_figure(con, target_sample_id = 815,
      out_png = "output/figures/manuscript/reaction_path_titration_sbw0002.png")
  build_reaction_path_fit_comparison_figure(con)
  build_sbs0001_sensitivity_figure(con)
  invisible(TRUE)
}
