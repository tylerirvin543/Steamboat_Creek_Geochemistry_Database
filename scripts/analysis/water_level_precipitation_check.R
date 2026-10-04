## scripts/analysis/water_level_precipitation_check.R
##
## Checks whether NOAA precipitation data helps explain the real
## STMGID MW3 seasonal water-level pattern identified in
## water_level_correlation_check.R as correlating with the Steamboat-
## field wells (Herz Domestic Well, NDOT). 2026-10-04, per direct user
## request.
##
## Honest headline limitation, confirmed before any statistics were
## run: real NOAA PRCP data on file only begins 2025-10-17 -- there is
## a complete gap for 2025-06-01 through 2025-10-16, which is most of
## the window (2025-06 to 2025-12) where the MW3/field-well decline
## was identified. This script can only test the back half of that
## window (2025-10-17 to 2025-12-31), not the full recession.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(zoo)
  library(ggplot2)
})

check_water_level_precipitation <- function(con,
                                             start = "2025-10-01",
                                             end = "2025-12-31",
                                             out_dir = "output/figures/monthly_indicator_timeline",
                                             derived_dir = "data/derived/monthly_indicator_timeline") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

  prcp_coverage <- DBI::dbGetQuery(con, "SELECT MIN(date) AS first_date, MAX(date) AS last_date FROM Weather_Observations WHERE parameter = 'PRCP'")
  message("[WATER LEVEL vs PRECIPITATION] Real PRCP data on file: ", prcp_coverage$first_date,
          " to ", prcp_coverage$last_date, ". No precipitation data exists before ",
          prcp_coverage$first_date, " -- this check can only cover the portion of the ",
          "2025-06 to 2025-12 water-level correlation window that overlaps real PRCP data.")

  prcp <- DBI::dbGetQuery(con, sprintf("
    SELECT date, SUM(value) AS prcp_in
    FROM Weather_Observations
    WHERE parameter = 'PRCP' AND date BETWEEN '%s' AND '%s'
    GROUP BY date
  ", start, end))
  prcp$date <- as.Date(prcp$date)

  wl <- DBI::dbGetQuery(con, sprintf("
    SELECT wl.timestamp, w.well_name, wl.depth_to_water
    FROM Water_Level_Observations wl
    JOIN Wells w ON w.well_id = wl.well_id
    WHERE w.well_name IN ('STMGID MW3', 'STMGID MW10')
      AND wl.timestamp BETWEEN '%s' AND '%s'
  ", start, end))
  wl$date <- as.Date(substr(wl$timestamp, 1, 10))

  wl_daily <- wl %>%
    dplyr::group_by(date, well_name) %>%
    dplyr::summarise(depth = mean(depth_to_water, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = well_name, values_from = depth)

  merged <- wl_daily %>%
    dplyr::left_join(prcp, by = "date") %>%
    dplyr::mutate(prcp_in = dplyr::coalesce(prcp_in, 0)) %>%
    dplyr::arrange(date)

  readr::write_csv(merged, file.path(derived_dir, "water_level_vs_precipitation_daily.csv"))

  merged <- merged %>%
    dplyr::mutate(
      d_mw3 = c(NA, diff(`STMGID MW3`)),
      d_mw10 = c(NA, diff(`STMGID MW10`)),
      prcp_3d = zoo::rollsum(prcp_in, 3, fill = NA, align = "right")
    )

  ct_mw3_sameday <- stats::cor.test(merged$prcp_in, merged$d_mw3)
  ct_mw10_sameday <- stats::cor.test(merged$prcp_in, merged$d_mw10)

  message("\n[WATER LEVEL vs PRECIPITATION] Same-day precip vs. next-day depth change (negative = water rising on/after a rain day):")
  message("  - STMGID MW3:  r=", round(unname(ct_mw3_sameday$estimate), 3), ", p=", signif(ct_mw3_sameday$p.value, 3))
  message("  - STMGID MW10: r=", round(unname(ct_mw10_sameday$estimate), 3), ", p=", signif(ct_mw10_sameday$p.value, 3))

  # The single largest real storm in the record (2025-12-21 to 12-26)
  # is the one genuine natural experiment available -- report its
  # well-by-well response directly rather than relying only on a
  # correlation coefficient dominated by that one event.
  storm <- merged %>% dplyr::filter(date >= as.Date("2025-12-19"), date <= as.Date("2025-12-29"))
  storm_summary <- tibble::tibble(
    well = c("STMGID MW3", "STMGID MW10"),
    depth_before = c(storm[[1, "STMGID MW3"]], storm[[1, "STMGID MW10"]]),
    depth_min_during = c(min(storm$`STMGID MW3`, na.rm = TRUE), min(storm$`STMGID MW10`, na.rm = TRUE)),
    max_drop_ft = c(
      storm[[1, "STMGID MW3"]] - min(storm$`STMGID MW3`, na.rm = TRUE),
      storm[[1, "STMGID MW10"]] - min(storm$`STMGID MW10`, na.rm = TRUE)
    )
  )
  readr::write_csv(storm_summary, file.path(derived_dir, "water_level_december_storm_response.csv"))
  message("\n[WATER LEVEL vs PRECIPITATION] Dec 2025 storm (~", round(sum(prcp$prcp_in[prcp$date >= as.Date("2025-12-19") & prcp$date <= as.Date("2025-12-26")], na.rm=TRUE), 1),
          " in over 2025-12-19 to 12-26) response:")
  for (i in seq_len(nrow(storm_summary))) {
    message("  - ", storm_summary$well[i], ": depth dropped ~", round(storm_summary$max_drop_ft[i], 2),
            " ft (water table rose) during/after the storm")
  }

  p <- ggplot(merged, aes(x = date)) +
    geom_col(aes(y = prcp_in * 20), fill = "steelblue", alpha = 0.5) +
    geom_line(aes(y = `STMGID MW3` - min(`STMGID MW3`, na.rm = TRUE), color = "STMGID MW3")) +
    geom_line(aes(y = `STMGID MW10` - min(`STMGID MW10`, na.rm = TRUE), color = "STMGID MW10")) +
    scale_y_continuous(
      name = "Depth to water, relative to window minimum (ft)",
      sec.axis = sec_axis(~ . / 20, name = "Daily precipitation (in)")
    ) +
    labs(
      title = "Daily precipitation vs. STMGID water levels, Oct-Dec 2025",
      subtitle = paste(strwrap(
        "Blue bars = daily precipitation (Reno-area NOAA stations). Lines = depth to water at each well, relative to its own minimum over this window (rising line = water table falling).",
        width = 105), collapse = "\n"),
      x = NULL, color = "Well",
      caption = paste(strwrap(
        "No precipitation data exists before 2025-10-17, so this cannot test the 2025-06 to 2025-10 portion of the water-level decline. Within the available window, the one real storm (2025-12-21 to 12-26) visibly lowered MW10's depth to water but produced no comparable response at MW3 -- see data/derived/monthly_indicator_timeline/water_level_december_storm_response.csv.",
        width = 130), collapse = "\n")
    ) +
    theme_minimal() +
    theme(legend.position = "bottom", plot.caption = ggplot2::element_text(hjust = 0, size = 8))

  ggsave(file.path(out_dir, "water_level_vs_precipitation.png"), p, width = 10, height = 7, dpi = 150)

  invisible(list(merged = merged, storm_summary = storm_summary,
                 cor_mw3 = ct_mw3_sameday, cor_mw10 = ct_mw10_sameday, plot = p))
}
