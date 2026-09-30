# ============================================================
# port_chemistry_summary.R
#
# Purpose (added 2026-09-30): a chemistry-by-sampling-port summary.
# Sampling_Ports (Galena 1/2/3, SB2/3, SBHR -- named commingling points
# from Dhakal et al. (2025)'s production well -> port -> injection well
# flow diagram) previously had zero linkage to any chemistry table --
# it existed purely for the well-network flow diagrams/GeoPackage
# lines. This script builds the first real chemistry summary grouped
# by port, from two real sources:
#
#   1. The six NDEP PRR "outlet" composite samples now promoted
#      (Galena 1/2/3 Outlet, SB2 Outlet, SB3 Outlet, SBHR Outlet -- see
#      scripts/ingest/promote_staged_ndep.R and
#      data/raw/ndep/PRR/staged_ndep_location_map.csv), joined to their
#      port via an explicit, human-reviewed lookup table below (SB2/3
#      is fed by two distinct outlet taps, so this can't be a single
#      Sampling_Ports.location_id join alone).
#   2. A best-effort join through Production_Port_Links -> Wells ->
#      (Wells.location_id, where populated) -> chemistry, so that any
#      future individual-production-well chemistry ingested for wells
#      feeding a given port picks up automatically. As of this
#      writing, zero production/injection wells have both a populated
#      location_id AND real chemistry, so this join contributes
#      nothing today -- it is included so the summary is ready for
#      that data, not to imply it exists now.
#
# Deliberately does NOT report a standard deviation or confidence
# interval -- each port has exactly n=2 real dates (2024 semi-annual
# submittal), far too few to support one.
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

# Robust to being source()'d with the project root as cwd (run_pipeline.R,
# an interactive console) OR with notebooks/ as cwd (a Quarto notebook
# without knitr root.dir pinning, e.g. notebooks/05) -- same file.exists
# fallback convention already used elsewhere in this project.
.plot_theme_path <- file.path("scripts", "analysis", "plot_theme.R")
if (!file.exists(.plot_theme_path)) .plot_theme_path <- file.path("..", .plot_theme_path)
source(.plot_theme_path)

# Outlet-station Location name -> Sampling_Ports.port_name. Kept as an
# explicit, human-reviewed lookup (not a DB join) because SB2/3 is fed
# by two distinct named outlet taps that can't both be represented by
# Sampling_Ports' single location_id FK.
outlet_to_port_map <- tibble::tribble(
  ~location_name,      ~port_name,
  "Galena 1 Outlet",   "Galena 1",
  "Galena 2 Outlet",   "Galena 2",
  "Galena 3 Outlet",   "Galena 3",
  "SB2 Outlet",        "SB2/3",
  "SB3 Outlet",        "SB2/3",
  "SBHR Outlet",       "SBHR"
)

#' Compute a real chemistry-by-sampling-port summary.
#'
#' @param con DBI connection.
#' @param analytes Which analyte codes to summarize (defaults to the
#'   major ions plus SiO2/B, matching this project's other chemistry
#'   figures).
#' @return A list: `outlet_samples` (every real outlet-composite
#'   value, one row per port/analyte/date -- the actual data, not just
#'   an average), `by_port` (n/mean/min/max per port/analyte, deliberately
#'   no SD given n=2), and `well_level` (the Production_Port_Links ->
#'   Wells -> chemistry join described above; 0 rows today, kept for
#'   when that data exists).
compute_port_chemistry_summary <- function(con,
    analytes = c("Ca", "Mg", "Na", "K", "Cl", "SO4", "Alkalinity", "SiO2", "B")) {

  message("---- Computing chemistry-by-sampling-port summary ----")

  major_ions <- dbGetQuery(con, "
    SELECT name AS location_name, analyte, value, units
    FROM vw_major_ions
  ")
  # SiO2/B aren't in vw_major_ions' filter -- pull them directly.
  extra_ions <- dbGetQuery(con, "
    SELECT l.name AS location_name, la.analyte, la.value, la.units
    FROM Lab_Analyses la
    JOIN Samples s ON s.sample_id = la.sample_id
    JOIN Locations l ON l.location_id = s.location_id
    WHERE la.analyte IN ('SiO2', 'B')
  ")

  outlet_chem <- bind_rows(major_ions, extra_ions) |>
    filter(analyte %in% analytes) |>
    inner_join(outlet_to_port_map, by = "location_name")

  if (nrow(outlet_chem) == 0) {
    message("  -> No promoted outlet-station chemistry found yet -- ",
            "run promote_staged_ndep(con) first.")
    outlet_chem <- tibble::tibble(
      location_name = character(), analyte = character(),
      value = numeric(), units = character(), port_name = character()
    )
  }

  by_port <- outlet_chem |>
    group_by(port_name, analyte) |>
    summarise(
      n = dplyr::n(),
      mean = mean(value, na.rm = TRUE),
      min = min(value, na.rm = TRUE),
      max = max(value, na.rm = TRUE),
      .groups = "drop"
    ) |>
    arrange(port_name, analyte)

  # Best-effort well-level join -- see header comment. Structured to
  # return real rows automatically the moment a production/injection
  # well has both a location_id and chemistry, without any code change.
  well_level <- dbGetQuery(con, "
    SELECT sp.port_name, w.well_name, la.analyte, la.value, la.units
    FROM Production_Port_Links ppl
    JOIN Wells w ON w.well_id = ppl.well_id
    JOIN Sampling_Ports sp ON sp.port_id = ppl.port_id
    JOIN Locations l ON l.location_id = w.location_id
    JOIN Samples s ON s.location_id = l.location_id
    JOIN Lab_Analyses la ON la.sample_id = s.sample_id
  ")
  if (nrow(well_level) == 0) {
    message("  -> No individual production/injection well has both a ",
            "location and chemistry yet -- well_level is empty by design, ",
            "not a bug (see header comment).")
  }

  message("  -> ", nrow(by_port), " port x analyte summary row(s) from ",
          length(unique(outlet_chem$port_name)), " port(s), n=",
          paste(unique(by_port$n), collapse = "/"), " sample date(s) each.")

  list(outlet_samples = outlet_chem, by_port = by_port, well_level = well_level)
}

#' Save the summary to a stable CSV and one figure, mirroring
#' chloride_mass_balance.R's own "read-only reporting" pattern.
build_port_chemistry_report <- function(con,
    out_csv = "data/derived/port_chemistry/port_chemistry_summary.csv",
    out_fig = "output/figures/port_chemistry/port_chemistry_by_port.png") {

  result <- compute_port_chemistry_summary(con)

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  write.csv(result$by_port, out_csv, row.names = FALSE, na = "")
  message("  -> Wrote ", nrow(result$by_port), " row(s) to ", out_csv, ".")

  if (nrow(result$outlet_samples) > 0) {
    key_analytes <- c("Cl", "Na", "SO4", "Alkalinity")
    plot_data <- result$outlet_samples |> filter(analyte %in% key_analytes)

    p <- ggplot(plot_data, aes(x = port_name, y = value, color = analyte)) +
      geom_point(size = 3, alpha = 0.85,
                 position = position_jitterdodge(jitter.width = 0.05, dodge.width = 0.6)) +
      stat_summary(fun = mean, geom = "point", shape = 3, size = 4,
                   position = position_dodge(width = 0.6), color = "black") +
      labs(
        x = "Sampling port", y = "Concentration (mg/L)", color = "Analyte",
        title = "Chemistry at Ormat's production/injection sampling ports",
        subtitle = paste(
          "Each point is one real 2024 NDEP PRR sample (n=2 dates per port,",
          "the '+' marks their mean) -- too few for a confidence interval"
        )
      ) +
      theme_steamboat()

    dir.create(dirname(out_fig), showWarnings = FALSE, recursive = TRUE)
    ggsave(out_fig, p, width = 9, height = 5.5, dpi = 300)
    message("  -> Wrote ", out_fig, ".")
  } else {
    message("  -> No outlet chemistry to plot yet.")
  }

  invisible(result)
}
