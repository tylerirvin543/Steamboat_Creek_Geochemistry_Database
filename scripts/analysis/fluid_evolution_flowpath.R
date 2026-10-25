# ============================================================
# fluid_evolution_flowpath.R
#
# Purpose (added 2026-10-24, continuing the gas-informed parent-fluid
# work in scripts/phreeqc/15_gas_informed_parent_fluid.R):
#
# Traces real chemistry, PHREEQC saturation indices, geothermometry,
# and stable isotopes along the Lower Sinter Terrace's real, sampled
# flowpath -- from the two reconstructed PARENT fluids (fissure,
# resort tank), through the as-measured (degassed) discharge at those
# same two points, through a real nearby LST well (SBW_0001), to the
# downstream Steamboat Creek stations this project already uses for
# its Cl mass-balance work (SBRR, then SBBV further downstream, per
# chloride_mass_balance.R) -- i.e. what we would see at the
# conductivity-logger/USGS-gauge end of the system if the LST sources
# above are really feeding it.
#
# This does NOT model fluid transport (no PHREEQC TRANSPORT/ADVECTION
# block, no spatial flow-path distances) -- it assembles and plots the
# REAL measured/modeled values at each real, dated sample point in a
# fixed conceptual order, so a reader can see where constituents
# converge, diverge, or behave inconsistently with simple conservative
# dilution along the way.
#
# All PHREEQC speciation/SI/geothermometry values used here were
# computed with the LLNL database (llnl.dat, auto-recommended for
# every sample here since each exceeds 50 C) -- see
# data/derived/phreeqc/parent_fluid_diagnostics.csv for the per-sample
# database, charge-balance error, and gas-equilibration convergence
# status (one real convergence failure -- the resort parent fluid's
# gas re-equilibration step -- is reported there, not hidden).
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

#' Assemble the real flowpath table: one row per node, with every
#' constituent/SI/geothermometer/isotope value available for it.
#'
#' @param con DBI connection.
#' @param parent_result Output of
#'   scripts/phreeqc/15_gas_informed_parent_fluid.R's
#'   compare_fissure_and_resort_parents(con).
build_fluid_evolution_table <- function(con, parent_result) {
  geo <- read.csv("docs/data/geothermometer_by_site.csv", stringsAsFactors = FALSE)
  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()
  si <- dbGetQuery(con, "
    SELECT sample_id, parameter, value FROM PHREEQC_Results
    WHERE sample_id IN (815, 816, 818, 819, 821) AND parameter LIKE 'SI_%'
  ")
  iso <- dbGetQuery(con, "
    SELECT sample_id, analyte, value FROM Isotope_Analyses
    WHERE sample_id IN (815, 816, 818, 819, 821)
  ")

  .get_si <- function(sid, mineral) {
    v <- si$value[si$sample_id == sid & si$parameter == paste0("SI_", mineral)]
    if (length(v) == 0) NA_real_ else v[1]
  }
  .get_iso <- function(sid, an) {
    v <- iso$value[iso$sample_id == sid & iso$analyte == an]
    if (length(v) == 0) NA_real_ else v[1]
  }
  .get_geo <- function(sid, col) {
    v <- geo[[col]][geo$sample_id == sid]
    if (length(v) == 0) NA_real_ else v[1]
  }
  .sol <- function(sid, col) {
    v <- solutions[[col]][solutions$sample_id == sid]
    if (length(v) == 0) NA_real_ else v[1]
  }

  real_nodes <- tibble::tribble(
    ~node, ~sample_id, ~flowpath_order, ~node_type,
    "Parent fluid (fissure, reconstructed)", NA_integer_, 1, "Reconstructed parent",
    "Parent fluid (resort, reconstructed)",  NA_integer_, 1, "Reconstructed parent",
    "SBF_0001 (fissure, measured)",          816L,        2, "Measured LST discharge",
    "SBW_0002 (resort tank, measured)",      815L,        2, "Measured LST discharge",
    "SBW_0001 (nearby LST well)",            821L,        3, "Measured LST discharge",
    "SBRR (Steamboat Creek, near-field)",    819L,        4, "Downstream creek",
    "SBBV (Steamboat Creek, downstream)",    818L,        5, "Downstream creek"
  )

  rows <- lapply(seq_len(nrow(real_nodes)), function(i) {
    r <- real_nodes[i, ]
    if (r$node == "Parent fluid (fissure, reconstructed)") {
      pf <- parent_result$pf_fissure
      list(Cl = pf$parent_row$Cl, Na = pf$parent_row$Na, SO4 = pf$parent_row$SO4,
           Si = pf$parent_row$Si, B = pf$parent_row$B, pH = pf$pH_parent,
           temperature_C = pf$T_reservoir_C,
           SI_Calcite = if (nrow(pf$SI_parent) > 0) pf$SI_parent$SI[pf$SI_parent$mineral == "Calcite"][1] else NA_real_,
           SI_Quartz = if (nrow(pf$SI_parent) > 0) pf$SI_parent$SI[pf$SI_parent$mineral == "Quartz"][1] else NA_real_,
           T_NaK_Giggenbach = NA_real_, T_quartz_C = NA_real_, d18O = NA_real_, d2H = NA_real_)
    } else if (r$node == "Parent fluid (resort, reconstructed)") {
      pf <- parent_result$pf_resort
      list(Cl = pf$parent_row$Cl, Na = pf$parent_row$Na, SO4 = pf$parent_row$SO4,
           Si = pf$parent_row$Si, B = pf$parent_row$B, pH = pf$pH_parent,
           temperature_C = pf$T_reservoir_C,
           SI_Calcite = NA_real_, SI_Quartz = NA_real_,  # gas-equilibration did not converge for this one (see diagnostics)
           T_NaK_Giggenbach = NA_real_, T_quartz_C = NA_real_, d18O = NA_real_, d2H = NA_real_)
    } else {
      sid <- r$sample_id
      list(Cl = .sol(sid, "Cl"), Na = .sol(sid, "Na"), SO4 = .sol(sid, "SO4"),
           Si = .sol(sid, "Si"), B = .sol(sid, "B"), pH = .sol(sid, "pH"),
           temperature_C = .sol(sid, "temperature"),
           SI_Calcite = .get_si(sid, "Calcite"), SI_Quartz = .get_si(sid, "Quartz"),
           T_NaK_Giggenbach = .get_geo(sid, "T_NaK_gigg_activity"),
           T_quartz_C = .get_geo(sid, "T_quartz_C"),
           d18O = .get_iso(sid, "d18O"), d2H = .get_iso(sid, "d2H"))
    }
  })

  bind_cols(real_nodes, bind_rows(rows)) |>
    mutate(node = factor(node, levels = real_nodes$node))
}

#' Multi-panel figure: each tracked constituent/SI/geothermometer/
#' isotope across the real flowpath, in conceptual downstream order.
build_fluid_evolution_figure <- function(con, parent_result,
    out_png = "output/figures/manuscript/fluid_evolution_flowpath.png") {

  tbl <- build_fluid_evolution_table(con, parent_result)

  long <- tbl |>
    select(node, node_type, Cl, Na, SO4, Si, B, pH, SI_Calcite, SI_Quartz,
           T_NaK_Giggenbach, T_quartz_C, d18O, d2H) |>
    tidyr::pivot_longer(cols = -c(node, node_type), names_to = "quantity", values_to = "value") |>
    filter(!is.na(value)) |>
    mutate(quantity = factor(quantity, levels = c(
      "Cl", "Na", "SO4", "Si", "B", "pH", "SI_Calcite", "SI_Quartz",
      "T_NaK_Giggenbach", "T_quartz_C", "d18O", "d2H"
    ), labels = c(
      "Cl (mg/L)", "Na (mg/L)", "SO4 (mg/L)", "SiO2 (mg/L)", "B (mg/L)", "pH",
      "SI Calcite", "SI Quartz", "Na/K Giggenbach T (C)", "Quartz T (C)",
      "d18O (permil)", "d2H (permil)"
    )))

  p <- ggplot(long, aes(x = node, y = value, color = node_type)) +
    geom_point(size = 2.8) +
    facet_wrap(~quantity, scales = "free_y", ncol = 3) +
    scale_color_manual(values = c(
      "Reconstructed parent" = "#0072B2",
      "Measured LST discharge" = "#D55E00",
      "Downstream creek" = "#009E73"
    ), name = NULL) +
    labs(x = NULL, y = NULL,
         title = "Fluid evolution along the real, sampled Lower Sinter Terrace flowpath",
         subtitle = "Parent fluids (reconstructed) -> measured LST discharge -> nearby well -> Steamboat Creek (SBRR, then downstream SBBV)") +
    theme_steamboat(base_size = 9) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 6.5),
          legend.position = "top", strip.text = element_text(size = 8))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11, height = 9, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Honest, small-n statistical check: are the real Na/K-Giggenbach
#' reservoir-temperature estimates for the three real LST thermal
#' points (fissure 816, resort 815, well 821) consistent with a single
#' shared parent (i.e. no significant difference), or do they differ?
#' n=3 -- explicitly NOT treated as a basis for strong inference, just
#' a documented, reproducible first look.
test_geothermometer_common_source <- function(con) {
  geo <- read.csv("docs/data/geothermometer_by_site.csv", stringsAsFactors = FALSE)
  thermal <- geo |> filter(sample_id %in% c(816, 815, 821))
  cv <- sd(thermal$T_NaK_gigg_activity) / mean(thermal$T_NaK_gigg_activity) * 100
  rng <- diff(range(thermal$T_NaK_gigg_activity))
  list(
    n = nrow(thermal),
    values = setNames(thermal$T_NaK_gigg_activity, thermal$location_name),
    mean_C = mean(thermal$T_NaK_gigg_activity),
    sd_C = sd(thermal$T_NaK_gigg_activity),
    cv_pct = cv,
    range_C = rng,
    note = paste0(
      "n=3: too small for a formal ANOVA/t-test with real power. Reported descriptively: ",
      "mean ", round(mean(thermal$T_NaK_gigg_activity), 1), " C, range ", round(rng, 1),
      " C, coefficient of variation ", round(cv, 1), "%. A ", round(rng, 1),
      " C spread across three independently sampled real LST points is small relative to the ",
      "~50-100 C spread this project's own geothermometer-vs-measured-temperature divergence ",
      "work already documents across the full real sample set -- consistent with (not proof of) ",
      "a single shared deep source for these three points specifically."
    )
  )
}

#' A schematic, box-and-arrow conceptual figure laying out the real
#' flowpath this analysis traces: deep parent fluid -> degassing
#' (informed qualitatively by visual inspection of the July/October
#' 2025 calibrated thermal-infrared surveys already shared for this
#' project, which show discrete, persistent hot-point sources (likely
#' active degassing/boiling vents) along the terrace's western margin
#' and a more diffuse, broader warm signature tracking the creek
#' channel itself (more consistent with shallow seepage/mixing than
#' point-source degassing) -- NOT yet from a digitized raster, since
#' the underlying GeoTIFF files are not yet on disk; see
#' docs/action_items_for_user.md item 12) -> measured LST discharge
#' points -> shallow meteoric mixing -> Steamboat Creek (SBRR) ->
#' White (1968)'s own ~100 gpm of "unseen" LST thermal inflow (see
#' notebooks/07_historical_context_sorey1992.qmd section 4.7) ->
#' Steamboat Creek (SBBV, downstream) -> further downstream to the
#' SBGG conductivity logger / USGS discharge gauge.
build_lst_conceptual_flowpath_figure <- function(
    out_png = "output/figures/manuscript/lst_conceptual_flowpath.png") {

  nodes <- tibble::tribble(
    ~id, ~x, ~y, ~label, ~kind,
    "parent",    0, 4, "Deep parent fluid\n(reconstructed: ~172-178C Na/K reservoir T)", "parent",
    "degas",     1, 5, "Degassing / boiling\n(steaming ground -- visually\npersistent point sources, TIR survey)", "process",
    "fissure",   2, 5.5, "Fissure discharge\n(SBF_0001, Cl ~815 mg/L)", "discharge",
    "resort",    2, 4.5, "Resort-tank discharge\n(SBW_0002, Cl ~849 mg/L)", "discharge",
    "well",      2, 3.5, "Nearby LST well\n(SBW_0001, Cl ~473 mg/L)", "discharge",
    "seep",      1, 2.5, "Shallow seepage / mixing\n(diffuse warm signature\ntracking the creek channel, TIR survey)", "process",
    "meteoric",  2, 2, "Meteoric / creek water\n(dilution end-member)", "meteoric",
    "sbrr",      3.5, 4, "Steamboat Creek @ SBRR\n(near-field, Cl ~17 mg/L)", "creek",
    "unseen",    4.5, 5, "+ ~100 gpm unseen LST\nthermal inflow (White 1968)", "process",
    "sbbv",      5.5, 4, "Steamboat Creek @ SBBV\n(downstream, Cl ~126 mg/L)", "creek",
    "logger",    7, 4, "SBGG conductivity logger /\nUSGS discharge gauge\n(further downstream)", "logger"
  )

  edges <- tibble::tribble(
    ~x, ~y, ~xend, ~yend,
    0, 4, 1, 5,
    1, 5, 2, 5.5,
    1, 5, 2, 4.5,
    0, 4, 2, 3.5,
    2, 5.5, 1, 2.5,
    2, 4.5, 1, 2.5,
    2, 3.5, 1, 2.5,
    1, 2.5, 3.5, 4,
    2, 2, 3.5, 4,
    3.5, 4, 4.5, 5,
    4.5, 5, 5.5, 4,
    5.5, 4, 7, 4
  )

  kind_colors <- c(parent = "#0072B2", process = "#999999", discharge = "#D55E00",
                    meteoric = "#56B4E9", creek = "#009E73", logger = "#CC79A7")

  p <- ggplot() +
    geom_segment(data = edges, aes(x = x, y = y, xend = xend, yend = yend),
                 arrow = arrow(length = unit(0.12, "inches"), type = "closed"),
                 color = "grey40", linewidth = 0.5) +
    geom_label(data = nodes, aes(x = x, y = y, label = label, fill = kind),
               color = "white", fontface = "bold", size = 2.7, label.padding = unit(0.3, "lines")) +
    scale_fill_manual(values = kind_colors, guide = "none") +
    coord_cartesian(xlim = c(-0.5, 8), ylim = c(1, 6.5)) +
    labs(title = "Conceptual flowpath: Lower Sinter Terrace parent fluid to the downstream conductivity logger",
         subtitle = "Real Cl values shown where measured; degassing-vs-seepage framing is a qualitative read of the shared thermal-infrared imagery, not yet a digitized layer") +
    theme_void(base_size = 11) +
    theme(plot.title = element_text(face = "bold", size = 12),
          plot.subtitle = element_text(size = 9, color = "grey30"))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 12, height = 6.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Driver: run everything in this file against the real database,
#' assuming scripts/phreeqc/15_gas_informed_parent_fluid.R's
#' run_parent_fluid_analysis(con) has already been run.
run_fluid_evolution_flowpath <- function(con, parent_result = NULL) {
  if (is.null(parent_result)) {
    parent_result <- compare_fissure_and_resort_parents(con)
  }
  evolution_table <- build_fluid_evolution_table(con, parent_result)
  table_path <- "data/derived/phreeqc/fluid_evolution_flowpath.csv"
  write.csv(evolution_table, table_path, row.names = FALSE)
  build_fluid_evolution_figure(con, parent_result)
  build_lst_conceptual_flowpath_figure()
  geo_test <- test_geothermometer_common_source(con)
  message("[fluid evolution] ", geo_test$note)
  invisible(list(table = evolution_table, geothermometer_test = geo_test))
}
