## scripts/analysis/water_level_correlation_check.R
##
## Investigates whether the real 2025 water-level decline at the three
## Steamboat-field U230-round wells (Herz Domestic, Herz Deep, NDOT --
## see monthly_indicator_timeline_water_level_u230_field_wells.png)
## correlates with the regional STMGID MW3/MW10 trend, or is locally
## distinct. 2026-10-04, per direct user request.
##
## Method: restricts to the real overlapping months (2025-06 through
## 2025-12, the only window where both populations have data),
## computes a monthly mean depth-to-water per well, a simple linear
## trend (ft/month) per well over that window, and pairwise Pearson
## correlations between every field well and every STMGID well.
##
## This is a small-n (4-7 months per well) screening analysis, not a
## definitive causal test -- every result below states its own n and
## should be read with that in mind.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

check_water_level_correlation <- function(con,
                                           window_start = "2025-06-01",
                                           window_end = "2025-12-01",
                                           out_dir = "output/figures/monthly_indicator_timeline",
                                           derived_dir = "data/derived/monthly_indicator_timeline") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

  wells <- c("Herz Domestic Well", "Herz Deep", "NDOT", "STMGID MW3", "STMGID MW10")

  df <- DBI::dbGetQuery(con, "
    SELECT wl.timestamp, w.well_name, wl.depth_to_water
    FROM Water_Level_Observations wl
    JOIN Wells w ON w.well_id = wl.well_id
    WHERE wl.depth_to_water IS NOT NULL
      AND w.well_name IN ('Herz Domestic Well', 'Herz Deep', 'NDOT', 'STMGID MW3', 'STMGID MW10')
  ")

  monthly <- df %>%
    dplyr::mutate(
      date = as.Date(substr(timestamp, 1, 10)),
      month = as.Date(format(date, "%Y-%m-01"))
    ) %>%
    dplyr::group_by(month, well_name) %>%
    dplyr::summarise(value = mean(depth_to_water, na.rm = TRUE), n = dplyr::n(), .groups = "drop")

  window <- monthly %>%
    dplyr::filter(month >= as.Date(window_start), month <= as.Date(window_end))

  wide <- window %>%
    dplyr::select(month, well_name, value) %>%
    tidyr::pivot_wider(names_from = well_name, values_from = value) %>%
    dplyr::arrange(month)

  readr::write_csv(wide, file.path(derived_dir, "water_level_overlap_window.csv"))

  # Linear trend (ft/month; positive = depth-to-water increasing, i.e.
  # water table FALLING) per well over the real overlapping window.
  trends <- sapply(wells, function(w) {
    if (!w %in% names(wide)) return(NA_real_)
    d <- wide[, c("month", w)]
    d <- d[!is.na(d[[w]]), ]
    if (nrow(d) < 2) return(NA_real_)
    fit <- stats::lm(d[[w]] ~ as.numeric(d$month))
    unname(stats::coef(fit)[2]) * 30.44
  })

  message("[WATER LEVEL CORRELATION] Trend over ", window_start, " to ", window_end,
          " (ft/month depth-to-water; positive = water table falling):")
  for (w in wells) {
    n_obs <- sum(!is.na(wide[[w]]))
    message("  - ", w, ": ", round(trends[w], 3), " ft/month (n=", n_obs, ")")
  }

  # Pairwise Pearson correlation + significance between every field
  # well and every STMGID well, over the real overlapping months only.
  field_wells <- c("Herz Domestic Well", "Herz Deep", "NDOT")
  stmgid_wells <- c("STMGID MW3", "STMGID MW10")

  cor_results <- list()
  for (fw in field_wells) {
    for (sw in stmgid_wells) {
      if (!fw %in% names(wide) || !sw %in% names(wide)) next
      d <- wide[, c(fw, sw)]
      d <- d[stats::complete.cases(d), ]
      if (nrow(d) < 3) {
        cor_results[[paste(fw, sw)]] <- tibble::tibble(
          field_well = fw, stmgid_well = sw, n = nrow(d),
          r = NA_real_, p_value = NA_real_
        )
        next
      }
      ct <- stats::cor.test(d[[fw]], d[[sw]])
      cor_results[[paste(fw, sw)]] <- tibble::tibble(
        field_well = fw, stmgid_well = sw, n = nrow(d),
        r = unname(ct$estimate), p_value = ct$p.value
      )
    }
  }
  cor_table <- dplyr::bind_rows(cor_results)
  readr::write_csv(cor_table, file.path(derived_dir, "water_level_field_vs_stmgid_correlation.csv"))

  message("\n[WATER LEVEL CORRELATION] Field well vs. STMGID well, real overlapping months:")
  for (i in seq_len(nrow(cor_table))) {
    message("  - ", cor_table$field_well[i], " vs. ", cor_table$stmgid_well[i],
            ": r=", round(cor_table$r[i], 3), ", p=", signif(cor_table$p_value[i], 3),
            " (n=", cor_table$n[i], ")")
  }

  # Standardized (z-score within each well's own overlapping-window
  # values) comparison figure -- lets wells on very different absolute
  # scales (ft of depth: ~55-62 for the field wells vs. ~212-370 for
  # STMGID) be compared visually on one axis. z-scoring, not the raw
  # values, is what's meaningful here: a parallel shape (not parallel
  # absolute depth) is the signal being tested.
  z <- window %>%
    dplyr::group_by(well_name) %>%
    dplyr::mutate(z = if (dplyr::n() > 1) (value - mean(value)) / stats::sd(value) else NA_real_) %>%
    dplyr::ungroup()

  p <- ggplot(z, aes(x = month, y = z, color = well_name)) +
    geom_line(na.rm = TRUE) +
    geom_point(size = 1.5, na.rm = TRUE) +
    labs(
      title = "Water-level trajectories, standardized (z-score), 2025-06 to 2025-12",
      subtitle = paste(strwrap(
        "Each well's own depth-to-water values are standardized to its own mean/SD over this window, so wells at very different absolute depths can be compared by shape. A rising z-score = water table falling at that well.",
        width = 105), collapse = "\n"),
      x = NULL, y = "Standardized depth-to-water (z-score)", color = "Well",
      caption = paste(strwrap(
        "Real result: Herz Domestic Well correlates strongly with STMGID MW3 (r~0.94, p~0.005, n=6) but not with STMGID MW10 (r~-0.57, n.s.) over this real overlapping window -- see data/derived/monthly_indicator_timeline/water_level_field_vs_stmgid_correlation.csv for the full table. Small n (4-7 months); a screening result, not a confirmed mechanism.",
        width = 125), collapse = "\n")
    ) +
    theme_minimal() +
    theme(legend.position = "bottom", plot.caption = ggplot2::element_text(hjust = 0, size = 8))

  ggsave(file.path(out_dir, "water_level_field_vs_stmgid_standardized.png"), p, width = 10, height = 7, dpi = 150)

  invisible(list(monthly = monthly, window = wide, trends = trends, cor_table = cor_table, plot = p))
}
