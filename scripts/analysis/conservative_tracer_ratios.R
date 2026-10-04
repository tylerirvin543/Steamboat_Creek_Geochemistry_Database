## scripts/analysis/conservative_tracer_ratios.R
##
## Computes conservative-tracer ratios (Cl/B, Na/Cl, Li/Cl, SiO2/Cl)
## per sample, for the pressure-driven-vs-fluid-migration question
## flagged in AGENTS.md ("Session 43" / docs/action_items_for_user.md
## item 8). Stable ratios over time at a site support a pressure-driven
## reading (same source fluid, just more/less of it); shifting ratios
## support fluid mixing / plumbing reorganization. This script computes
## the ratios only -- it makes no causal claim about the eruption.
##
## Per the 2026-10-04 plan decision: both the curated thermal
## end-member set (Sorey & Colvard 1992 + FIELD, excluding Cox and the
## SBRR/SBBV creek mixing points -- the same scoping already used in
## notebooks/07's Cl/B t-test) AND background/domestic samples are
## included, clearly labeled via `sample_group`, rather than excluding
## one population. `sample_group` itself stays a short internal code
## ("thermal_endmember" / "background_or_other") used for filtering
## logic; `sample_group_label` is the human-readable version used in
## every plot legend (2026-10-04, per direct user feedback that the
## raw code name didn't say what the group actually is).
##
## 2026-10-04 (continued): also screens every background/domestic
## well/site for a real drift toward the thermal reference band over
## time (see flag_thermal_drift()) -- a screening step for human
## review, not a confirmatory test or a causal claim.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

## Human-readable labels for sample_group, used in every legend/caption
## instead of the raw internal code value.
.sample_group_labels <- c(
  thermal_endmember = "Thermal end-member (Sorey & Colvard 1992 + FIELD)",
  background_or_other = "Background / non-thermal (NDEP, domestic wells, creeks)"
)

## Sampling_Events/Samples.collection_time mixes Unix-epoch-seconds,
## MM/DD/YYYY H:MM, and ISO YYYY-MM-DD formats across sources (same
## class of dual-format issue documented project-wide, e.g.
## notebooks/07's own `.parse_any_date()`). Reuses that exact logic
## rather than a naive as.Date()/Excel-serial fallback, which silently
## produced nonsense dates (e.g. year 1539981) for Unix-epoch-second
## values on first attempt here.
.parse_any_date_ratios <- function(x) {
  num <- suppressWarnings(as.numeric(x))
  out <- as.Date(rep(NA, length(x)))
  is_num <- !is.na(num) & !grepl("[A-Za-z]", x)
  out[is_num] <- as.Date(as.POSIXct(num[is_num], origin = "1970-01-01", tz = "UTC"))
  rem <- !is_num
  out[rem] <- suppressWarnings(as.Date(x[rem], format = "%m/%d/%Y %H:%M"))
  rem2 <- rem & is.na(out)
  out[rem2] <- suppressWarnings(as.Date(x[rem2], format = "%Y-%m-%d"))
  out
}

## For every background/domestic feature (well/site) with >= 3 finite
## observations of a given ratio spanning >= 180 days, fits a simple
## log10(value) ~ date trend and checks whether it is moving TOWARD the
## thermal-endmember reference band (median of the thermal_endmember
## group for that ratio) rather than away from it. This is a screening
## step only -- a loose p < 0.1 threshold, explicitly not a
## confirmatory test -- flagged results need a human look (does the
## drift make geochemical sense, or is it a small-n artifact?), not an
## automatic "this well is becoming thermal" conclusion.
flag_thermal_drift <- function(long_ratios, min_n = 3, min_span_days = 180, p_threshold = 0.1) {
  thermal_ref <- long_ratios %>%
    dplyr::filter(sample_group == "thermal_endmember", value > 0) %>%
    dplyr::group_by(ratio) %>%
    dplyr::summarise(thermal_median = stats::median(value), .groups = "drop")

  bg <- long_ratios %>%
    dplyr::filter(sample_group == "background_or_other", value > 0) %>%
    dplyr::group_by(feature, ratio) %>%
    dplyr::filter(dplyr::n() >= min_n,
                  as.numeric(diff(range(date))) >= min_span_days) %>%
    dplyr::ungroup()

  if (nrow(bg) == 0) {
    return(tibble::tibble(
      feature = character(), ratio = character(), n = integer(),
      date_start = as.Date(character()), date_end = as.Date(character()),
      slope = double(), p_value = double(),
      distance_start = double(), distance_end = double(),
      drifting_toward_thermal = logical()
    ))
  }

  groups <- split(bg, list(bg$feature, bg$ratio), drop = TRUE)

  results <- lapply(groups, function(dat) {
    ratio_name <- dat$ratio[1]
    thermal_median <- thermal_ref$thermal_median[thermal_ref$ratio == ratio_name]
    if (length(thermal_median) == 0 || is.na(thermal_median) || thermal_median <= 0) {
      return(NULL)
    }

    fit <- tryCatch(stats::lm(log10(value) ~ as.numeric(date), data = dat), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    coefs <- summary(fit)$coefficients
    if (nrow(coefs) < 2) return(NULL)

    date_range <- range(dat$date)
    pred <- stats::predict(fit, newdata = data.frame(date = date_range))

    thermal_log <- log10(thermal_median)
    distance_start <- abs(pred[1] - thermal_log)
    distance_end <- abs(pred[2] - thermal_log)

    tibble::tibble(
      feature = dat$feature[1],
      ratio = ratio_name,
      n = nrow(dat),
      date_start = date_range[1],
      date_end = date_range[2],
      slope = coefs[2, 1],
      p_value = coefs[2, 4],
      distance_start = distance_start,
      distance_end = distance_end,
      drifting_toward_thermal = (distance_end < distance_start) & (coefs[2, 4] < p_threshold)
    )
  })

  dplyr::bind_rows(results)
}

compute_tracer_ratios <- function(con,
                                   out_dir = "output/figures/tracer_ratios",
                                   derived_dir = "data/derived/tracer_ratios") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

  raw <- DBI::dbGetQuery(con, "
    SELECT s.sample_id, l.name AS feature, s.collection_time, s.data_source,
           la.analyte, la.value
    FROM Lab_Analyses la
    JOIN Samples s ON s.sample_id = la.sample_id
    JOIN Locations l ON l.location_id = s.location_id
    WHERE la.analyte IN ('Cl','B','Na','Li','SiO2','Si')
  ")

  if (nrow(raw) == 0) {
    message("[TRACER RATIOS] No Cl/B/Na/Li/SiO2 rows found -- skipping.")
    return(invisible(NULL))
  }

  # Prefer the SiO2 analyte code where both SiO2 and Si exist for a
  # sample (SiO2 is this project's historical-literature code; Si is
  # the routine lab element code -- not assumed mass-equivalent, see
  # AGENTS.md Session 27). Collapse to a single 'SiO2_any' column,
  # keeping track of which code supplied it.
  raw <- raw %>%
    dplyr::mutate(analyte = ifelse(analyte == "Si", "SiO2_any",
                             ifelse(analyte == "SiO2", "SiO2_any", analyte)))

  wide <- raw %>%
    dplyr::group_by(sample_id, feature, collection_time, data_source, analyte) %>%
    dplyr::summarise(value = dplyr::first(value), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = analyte, values_from = value)

  wide <- wide %>%
    dplyr::mutate(
      date = .parse_any_date_ratios(collection_time),
      year = as.integer(format(date, "%Y")),
      # Same thermal-endmember scoping already established in
      # notebooks/07's Cl/B t-test: Sorey & Colvard 1992 + FIELD,
      # excluding Cox and the SBRR/SBBV creek mixing points.
      sample_group = dplyr::case_when(
        data_source %in% c("Sorey & Colvard 1992", "FIELD") &
          !grepl("Cox", feature) & !feature %in% c("SBRR", "SBBV") ~ "thermal_endmember",
        TRUE ~ "background_or_other"
      ),
      sample_group_label = unname(.sample_group_labels[sample_group]),
      Cl_B = ifelse(!is.na(Cl) & !is.na(B) & B > 0, Cl / B, NA_real_),
      Na_Cl = ifelse(!is.na(Na) & !is.na(Cl) & Cl > 0, Na / Cl, NA_real_),
      Li_Cl = if ("Li" %in% names(.)) ifelse(!is.na(Li) & !is.na(Cl) & Cl > 0, Li / Cl, NA_real_) else NA_real_,
      SiO2_Cl = if ("SiO2_any" %in% names(.)) ifelse(!is.na(SiO2_any) & !is.na(Cl) & Cl > 0, SiO2_any / Cl, NA_real_) else NA_real_
    )

  readr::write_csv(wide, file.path(derived_dir, "tracer_ratios_by_site.csv"))

  long_ratios <- wide %>%
    dplyr::select(sample_id, feature, date, year, data_source, sample_group, sample_group_label,
                   Cl_B, Na_Cl, Li_Cl, SiO2_Cl) %>%
    tidyr::pivot_longer(cols = c(Cl_B, Na_Cl, Li_Cl, SiO2_Cl),
                         names_to = "ratio", values_to = "value") %>%
    dplyr::filter(is.finite(value))

  if (nrow(long_ratios) == 0) {
    message("[TRACER RATIOS] Wrote ", nrow(wide), " sample rows but 0 finite ratio values -- skipping figure.")
    return(invisible(list(wide = wide)))
  }

  drift_flags <- flag_thermal_drift(long_ratios)
  readr::write_csv(drift_flags, file.path(derived_dir, "thermal_drift_flags.csv"))
  n_flagged <- sum(drift_flags$drifting_toward_thermal, na.rm = TRUE)
  message("[TRACER RATIOS] Screened ", nrow(drift_flags), " feature/ratio combination(s) with >=3 ",
          "samples spanning >=180 days; ", n_flagged, " flagged as drifting toward the thermal band. ",
          "This is a screening step for human review, not a confirmed finding.")

  flagged_pairs <- drift_flags %>%
    dplyr::filter(drifting_toward_thermal) %>%
    dplyr::arrange(p_value) %>%
    dplyr::slice_head(n = 8) # label only the most significant drifts; full set is in thermal_drift_flags.csv

  plot_points <- long_ratios %>% dplyr::filter(value > 0)

  p <- ggplot(plot_points, aes(x = date, y = value, color = sample_group_label)) +
    geom_point(alpha = 0.6, na.rm = TRUE) +
    scale_y_log10() +
    facet_wrap(~ratio, scales = "free_y") +
    labs(
      title = "Conservative tracer ratios over time (log scale)",
      subtitle = paste(strwrap(
        "Each point is one real water sample's Cl/B, Na/Cl, Li/Cl, or SiO2/Cl ratio. A flat ratio over time at a given site is more consistent with a pressure-driven change (same source fluid); a shifting ratio is more consistent with fluid mixing or plumbing reorganization.",
        width = 110), collapse = "\n"),
      x = NULL, y = "Ratio (log10 scale)", color = "Sample group",
      caption = paste(strwrap(paste0(
        "Black outline/yellow fill + labels = the top 8 (of 16 screened) background/non-thermal sites flagged as drifting toward ",
        "the thermal reference band over time (screening only -- see data/derived/tracer_ratios/thermal_drift_flags.csv for the full list). ",
        "Not a causal claim about the 2025 eruption on its own."
      ), width = 130), collapse = "\n")
    ) +
    theme_minimal() +
    theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1), legend.position = "bottom",
          plot.caption = ggplot2::element_text(hjust = 0))

  if (nrow(flagged_pairs) > 0) {
    flagged_points <- plot_points %>%
      dplyr::inner_join(flagged_pairs %>% dplyr::select(feature, ratio), by = c("feature", "ratio"))

    label_points <- flagged_points %>%
      dplyr::group_by(feature, ratio) %>%
      dplyr::filter(date == max(date)) %>%
      dplyr::ungroup()

    p <- p +
      geom_line(data = flagged_points, aes(x = date, y = value, group = feature),
                color = "black", linewidth = 0.6, inherit.aes = FALSE) +
      geom_point(data = flagged_points, aes(x = date, y = value), color = "black",
                 shape = 21, fill = "yellow", size = 2, inherit.aes = FALSE) +
      ggrepel::geom_text_repel(data = label_points, aes(x = date, y = value, label = feature),
                                inherit.aes = FALSE, size = 2.8, color = "black",
                                max.overlaps = Inf)
  }

  ggsave(file.path(out_dir, "tracer_ratios_by_site.png"), p, width = 11, height = 8, dpi = 150)

  message("[TRACER RATIOS] Wrote ", nrow(wide), " sample rows (",
          sum(wide$sample_group == "thermal_endmember"), " thermal end-member) to ", derived_dir,
          " and figure to ", out_dir)

  invisible(list(wide = wide, long_ratios = long_ratios, drift_flags = drift_flags, plot = p))
}
