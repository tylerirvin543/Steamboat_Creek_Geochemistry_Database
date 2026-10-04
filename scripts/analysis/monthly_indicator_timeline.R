## scripts/analysis/monthly_indicator_timeline.R
##
## Assembles a real, monthly-resolution, long-format indicator table
## spanning the 2025-06-03 Lower Sinter Terrace eruption and its
## aftermath, per the design sketch in docs/action_items_for_user.md
## item 8 and the 2026-10-04 plan. Default date range (2025-01-01
## onward) is deliberately scoped to where real post-eruption coverage
## exists across multiple indicators -- NOT the full historical record,
## most of which has no matching subsurface monitoring data for this
## question (see the "honest gap" note in that design sketch).
##
## This assembles and visualizes the monthly data only. No
## cross-correlation, lag analysis, PCA, or null-model testing is
## implemented here -- that is explicitly the next, separate step per
## the design sketch's own phasing.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(ggplot2)
})

.month_floor <- function(d) as.Date(format(d, "%Y-%m-01"))

## "field_mean" (used as the `site` value for injection_pressure and
## well_production) means: the simple average, across every well
## reporting a value in that document/month, of the given metric --
## not a flow-weighted or production-weighted average. Documented here
## once and referenced from both indicators' figure captions below.
.FIELD_MEAN_NOTE <- "'field_mean' = the simple average across every well reporting a value for that document date (not flow- or production-weighted)."

.monthly_injection_pressure <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT document_date, canonical_well_name, value
    FROM Injection_Operating_History
    WHERE parameter = 'pressure_psig' AND metric_type = 'current' AND value IS NOT NULL
  ")
  if (nrow(df) == 0) return(NULL)
  df %>%
    dplyr::mutate(month = .month_floor(as.Date(document_date))) %>%
    dplyr::group_by(month) %>%
    dplyr::summarise(value = mean(value, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(indicator = "injection_pressure", metric = "mean_current_psig", site = "field_mean")
}

.monthly_well_production <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT document_date, well_name, well_type, parameter, unit, value
    FROM Well_Production_History
    WHERE parameter IN ('wellhead_pressure_psig', 'flow') AND value IS NOT NULL
  ")
  if (nrow(df) == 0) return(NULL)
  df %>%
    dplyr::mutate(month = .month_floor(as.Date(document_date)),
                   metric = ifelse(endsWith(parameter, paste0("_", unit)), parameter, paste0(parameter, "_", unit))) %>%
    dplyr::group_by(month, metric) %>%
    dplyr::summarise(value = mean(value, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(indicator = "well_production", site = "field_mean")
}

.monthly_conductivity <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT co.timestamp, cl.logger_name, cl.role, co.sc_25c
    FROM Conductivity_Observations co
    JOIN Conductivity_Loggers cl ON cl.logger_id = co.logger_id
    WHERE co.sc_25c IS NOT NULL
  ")
  if (nrow(df) == 0) return(NULL)
  df %>%
    dplyr::mutate(
      month = .month_floor(as.Date(timestamp)),
      # Real station names (SBRR = Rhodes Road upstream control, SBGG
      # = Geiger Grade downstream), not the generic logger_name, per
      # direct user feedback -- mapped from the logger's deployment
      # role rather than hardcoding a logger_id, so this still works
      # if loggers are swapped/replaced in the future.
      site = dplyr::case_when(
        role == "upstream_control" ~ "SBRR (Rhodes Road, upstream control)",
        role == "downstream" ~ "SBGG (Geiger Grade, downstream)",
        TRUE ~ logger_name
      )
    ) %>%
    dplyr::group_by(month, site) %>%
    dplyr::summarise(value = mean(sc_25c, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(indicator = "conductivity", metric = "mean_sc25c_uScm")
}

.monthly_field_chemistry <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT s.collection_time, l.name AS site, fm.parameter, fm.value
    FROM Field_Measurements fm
    JOIN Samples s ON s.sample_id = fm.sample_id
    JOIN Locations l ON l.location_id = s.location_id
    WHERE fm.parameter IN ('pH', 'temperature', 'conductivity')
      AND l.name NOT GLOB 'SBO_*'
  ")
  if (nrow(df) == 0) return(NULL)
  df %>%
    dplyr::mutate(
      date = .parse_any_date_ratios(collection_time),
    ) %>%
    dplyr::filter(!is.na(date)) %>%
    dplyr::mutate(month = .month_floor(date)) %>%
    dplyr::group_by(month, site, parameter) %>%
    dplyr::summarise(value = mean(value, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(indicator = "field_chemistry", metric = parameter)
}

.monthly_tracer_ratios <- function(tracer_wide) {
  if (is.null(tracer_wide) || nrow(tracer_wide) == 0) return(NULL)
  tracer_wide %>%
    dplyr::filter(!is.na(date)) %>%
    dplyr::mutate(month = .month_floor(date)) %>%
    dplyr::group_by(month, sample_group_label) %>%
    dplyr::summarise(
      Cl_B = mean(Cl_B, na.rm = TRUE), Na_Cl = mean(Na_Cl, na.rm = TRUE), n = dplyr::n(),
      .groups = "drop"
    ) %>%
    tidyr::pivot_longer(cols = c(Cl_B, Na_Cl), names_to = "metric", values_to = "value") %>%
    dplyr::filter(is.finite(value)) %>%
    dplyr::mutate(indicator = "tracer_ratios") %>%
    dplyr::rename(site = sample_group_label)
}

## STMGID MW3/MW10 (continuous, multi-year, wider South Truckee
## Meadows basin) and the three real 2025 U230-round wells (Herz
## Domestic, Herz Deep, NDOT -- short series, genuinely inside the
## Steamboat field) are different enough in both time span and
## geographic relevance that combining them in one figure buried the
## real, field-specific signal under STMGID's much longer flat lines.
## Split into two separate water-level figures (2026-10-04, per direct
## user feedback) while keeping one "water_level" indicator in the CSV.
.WATER_LEVEL_GROUPS <- list(
  stmgid_regional = c("STMGID MW3", "STMGID MW10"),
  u230_field_wells = c("Herz Domestic Well", "Herz Deep", "NDOT")
)

.monthly_water_levels <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT wl.timestamp, w.well_name, wl.depth_to_water
    FROM Water_Level_Observations wl
    JOIN Wells w ON w.well_id = wl.well_id
    WHERE wl.depth_to_water IS NOT NULL
      AND w.well_name IN ('Herz Domestic Well', 'Herz Deep', 'NDOT', 'STMGID MW3', 'STMGID MW10')
  ")
  if (nrow(df) == 0) return(NULL)
  df %>%
    dplyr::mutate(month = .month_floor(as.Date(substr(timestamp, 1, 10)))) %>%
    dplyr::group_by(month, well_name) %>%
    dplyr::summarise(value = mean(depth_to_water, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
    dplyr::mutate(indicator = "water_level", metric = "mean_depth_to_water_ft") %>%
    dplyr::rename(site = well_name)
}

## Per-indicator (or per-indicator-subgroup, for water_level) title and
## a short, real caption describing what the figure shows, what
## "field_mean" means where relevant, and -- for field_chemistry, whose
## legend is intentionally simplified -- where to find full per-site
## detail.
.FIGURE_META <- list(
  injection_pressure = list(
    title = "Injection wellhead pressure (field mean, current reading)",
    caption = paste0(
      "Mean 'current' wellhead pressure across all injection wells reported in each NDEP UIC permit document on file. ", .FIELD_MEAN_NOTE,
      " Only one document (2025-05-30) exists today -- this becomes a real time series once more NDEP permits are transcribed ",
      "(see data/raw/ndep/injection_pressure_rate_history.csv)."
    )
  ),
  well_production = list(
    title = "Well production/injection operating snapshots (TFT reports)",
    caption = paste0(
      "Mean flow and wellhead pressure across the 13 production/injection wells reported in each NDEP TFT Compliance Report's Table 2. ",
      .FIELD_MEAN_NOTE, " Two report dates exist today: 2025-07-09 and 2026-04-07."
    )
  ),
  conductivity = list(
    title = "Steamboat Creek specific conductance (stream loggers)",
    caption = "Monthly mean specific conductance (25C-corrected, sc_25c) at the two HOBO/Onset stream conductivity loggers (SBRR upstream control, SBGG downstream), deployed starting 2026-07-15 -- the real-time chloride-discharge proxy central to this project's own conductivity workstream."
  ),
  field_chemistry = list(
    title = "Field parameters at monitoring wells/outlets (U230 rounds)",
    caption = "Monthly mean pH, temperature, and specific conductance at real named monitoring wells, domestic wells, and injection/outlet taps sampled during NDEP's U230 field rounds (Aug 2025-May 2026). Single-visit steaming-ground survey points are excluded. Legend is suppressed here (29 real sites) -- see data/derived/monthly_indicator_timeline/monthly_indicator_timeline.csv for the full per-site, per-month values behind this figure."
  ),
  tracer_ratios = list(
    title = "Conservative tracer ratios (Cl/B, Na/Cl), monthly means",
    caption = "Monthly mean Cl/B and Na/Cl ratios, thermal end-member samples (Sorey & Colvard 1992 + FIELD) vs. all other background/non-thermal samples on file. A flat ratio over time supports a pressure-driven explanation; a shifting ratio supports fluid mixing. Not a causal claim about the 2025 eruption on its own."
  ),
  water_level_stmgid_regional = list(
    title = "Depth to water: STMGID regional monitoring wells (continuous)",
    caption = "Continuous, multi-year water-level record at STMGID MW3/MW10 -- in the wider South Truckee Meadows basin, not inside the Steamboat field itself. Included as the only real continuous water-level reference on file; shown separately from the shorter, field-specific series below because of the very different time span and geographic relevance."
  ),
  water_level_u230_field_wells = list(
    title = "Depth to water: Steamboat-field monitoring wells (2025 U230 rounds)",
    caption = "Depth-to-water readings at three real Steamboat-field monitoring wells (Herz Domestic, Herz Deep, NDOT), measured during each NDEP U230 field-sampling round in 2025 -- a short, real series, not yet a multi-year baseline."
  )
)

#' Build a real, monthly-resolution indicator table spanning the
#' available post-eruption record.
#'
#' @param con DBI connection
#' @param start,end Date range (character or Date), default
#'   2025-01-01 through today -- the window with real multi-indicator
#'   coverage (see this file's header comment for why).
build_monthly_indicator_timeline <- function(con,
                                              start = "2025-01-01",
                                              end = Sys.Date(),
                                              out_dir = "output/figures/monthly_indicator_timeline",
                                              derived_dir = "data/derived/monthly_indicator_timeline") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

  start <- as.Date(start)
  end <- as.Date(end)

  source("scripts/analysis/conservative_tracer_ratios.R")
  tracer_result <- tryCatch(compute_tracer_ratios(con), error = function(e) NULL)

  pieces <- list(
    .monthly_injection_pressure(con),
    .monthly_well_production(con),
    .monthly_conductivity(con),
    .monthly_field_chemistry(con),
    .monthly_tracer_ratios(tracer_result$wide),
    .monthly_water_levels(con)
  )
  pieces <- Filter(Negate(is.null), pieces)

  if (length(pieces) == 0) {
    message("[MONTHLY TIMELINE] No indicator data found at all -- nothing to build.")
    return(invisible(NULL))
  }

  timeline <- dplyr::bind_rows(pieces) %>%
    dplyr::filter(month >= start, month <= end) %>%
    dplyr::select(month, indicator, metric, site, value, n) %>%
    dplyr::arrange(indicator, metric, site, month)

  readr::write_csv(timeline, file.path(derived_dir, "monthly_indicator_timeline.csv"))

  coverage <- timeline %>%
    dplyr::group_by(indicator) %>%
    dplyr::summarise(n_months = dplyr::n_distinct(month),
                      first_month = min(month), last_month = max(month), .groups = "drop")
  message("[MONTHLY TIMELINE] Indicator coverage (", start, " to ", end, "):")
  for (i in seq_len(nrow(coverage))) {
    message("  - ", coverage$indicator[i], ": ", coverage$n_months[i], " month(s), ",
            coverage$first_month[i], " to ", coverage$last_month[i])
  }

  eruption_date <- as.Date("2025-06-03")

  ## Builds and saves one figure for a given (indicator, data, key,
  ## meta) combination -- used directly for every indicator except
  ## water_level, which calls this once per subgroup instead.
  .wrap_text <- function(x, width = 95) paste(strwrap(x, width = width), collapse = "\n")

  .build_one_figure <- function(df_ind, key, meta) {
    n_metrics <- dplyr::n_distinct(df_ind$metric)
    n_sites <- dplyr::n_distinct(df_ind$site)

    p_ind <- ggplot(df_ind, aes(x = month, y = value, color = site)) +
      geom_vline(xintercept = eruption_date, linetype = "dashed", color = "firebrick", alpha = 0.7) +
      geom_line(na.rm = TRUE) +
      geom_point(size = 1.3, na.rm = TRUE) +
      labs(
        title = meta$title,
        subtitle = .wrap_text("Dashed red line = 2025-06-03 Lower Sinter Terrace eruption (Lindsey et al. 2026). Assembly/visualization only -- no cross-correlation or causal analysis yet."),
        caption = .wrap_text(meta$caption),
        x = NULL, y = "Value (see metric facet label / axis)",
        color = "Site/group"
      ) +
      theme_minimal() +
      theme(plot.caption = ggplot2::element_text(hjust = 0, size = 8))

    if (n_metrics > 1) {
      p_ind <- p_ind + facet_wrap(~metric, scales = "free_y", ncol = 1)
    }

    # Every figure keeps a real legend per the 2026-10-04 request; very
    # busy legends (field_chemistry's 29 real sites) are suppressed
    # specifically (not just shrunk) since even a multi-column legend
    # at that cardinality is unreadable -- the caption above points to
    # the full per-site CSV instead.
    if (n_sites > 20) {
      p_ind <- p_ind + theme(legend.position = "none")
    } else {
      n_legend_cols <- if (n_sites > 8) 3 else 1
      p_ind <- p_ind +
        theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 7)) +
        guides(color = guide_legend(ncol = n_legend_cols))
    }

    fig_height <- if (n_metrics > 1) 3 * n_metrics + 1 else 6
    fig_path <- file.path(out_dir, paste0("monthly_indicator_timeline_", key, ".png"))
    ggsave(fig_path, p_ind, width = 9, height = fig_height, dpi = 150)
    p_ind
  }

  plots <- list()
  for (ind in unique(timeline$indicator)) {
    df_ind <- dplyr::filter(timeline, indicator == ind)

    if (ind == "water_level") {
      # Split into the two site groups defined above instead of one
      # combined figure (2026-10-04, per direct user feedback that
      # STMGID's continuous multi-year record and the three short 2025
      # U230-round wells don't belong together).
      for (grp_name in names(.WATER_LEVEL_GROUPS)) {
        grp_sites <- .WATER_LEVEL_GROUPS[[grp_name]]
        df_grp <- dplyr::filter(df_ind, site %in% grp_sites)
        if (nrow(df_grp) == 0) next
        key <- paste0("water_level_", grp_name)
        plots[[key]] <- .build_one_figure(df_grp, key, .FIGURE_META[[key]])
      }
    } else {
      plots[[ind]] <- .build_one_figure(df_ind, ind, .FIGURE_META[[ind]])
    }
  }

  message("[MONTHLY TIMELINE] Wrote ", nrow(timeline), " rows across ", length(pieces),
          " indicator source(s) to ", derived_dir, " and ", length(plots),
          " separate figure(s) to ", out_dir)

  invisible(list(timeline = timeline, coverage = coverage, plots = plots))
}
