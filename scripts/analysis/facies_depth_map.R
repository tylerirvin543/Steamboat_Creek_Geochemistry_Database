# ============================================================
# facies_depth_map.R
#
# plot_facies_depth_map()
#
# Spatial overlay of the facies clusters (from
# cluster_hydrochemical_facies.R) onto a Steamboat-area map, with point
# size showing an APPROXIMATE reservoir/completion depth -- NOT a real
# screened-interval-vs-cluster geologic model (that would need a 3D
# framework this project does not have yet, see the README's Leapfrog
# scoping section). "Approximate depth" here is deliberately defined
# by a documented fallback order, not a single always-available field,
# since real depth data is genuinely sparse:
#   1. midpoint(top_perforation, bottom_perforation) if both exist --
#      the actual screened/open-hole interval, the best available
#      proxy for feed depth.
#   2. total_depth if no perforation interval is recorded.
#   3. NA (shown as an unfilled/hollow point, not silently dropped) --
#      most PW2-x/PW3-x ArcGIS-digitized wells and every Locations-only
#      (non-Wells) entity (Eich, Soccer Field, Boyd, Jeppson, Rogers,
#      Curti, Steinhardt) have no depth on record at all as of
#      2026-09-26 -- a real, stated data gap, not a plotting bug.
# A sample's facies cluster is taken as that well's majority
# (most-frequent) cluster across its own repeat samples, since this is
# a per-well spatial summary, not a per-sample one.
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

plot_facies_depth_map <- function(con, facies_result,
                                   bbox = c(lon_min = -119.80, lon_max = -119.71,
                                            lat_min = 39.355, lat_max = 39.415)) {
  library(ggrepel)

  d <- facies_result$data
  d$clean_name <- sub(" \\(Mariner.*\\)$", "", d$location_name)

  per_well_cluster <- d %>%
    dplyr::count(clean_name, facies_cluster, name = "n_samples") %>%
    dplyr::group_by(clean_name) %>%
    dplyr::slice_max(n_samples, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup()

  coords <- d %>%
    dplyr::distinct(clean_name, location_id) %>%
    dplyr::left_join(
      dbGetQuery(con, "SELECT location_id, latitude, longitude FROM Locations"),
      by = "location_id"
    )

  wells_depth <- dbGetQuery(con, "
    SELECT well_name, total_depth, top_perforation, bottom_perforation
    FROM Wells
  ") %>%
    dplyr::mutate(
      depth_ft = dplyr::case_when(
        !is.na(top_perforation) & !is.na(bottom_perforation) ~ (top_perforation + bottom_perforation) / 2,
        !is.na(total_depth) ~ total_depth,
        TRUE ~ NA_real_
      ),
      depth_source = dplyr::case_when(
        !is.na(top_perforation) & !is.na(bottom_perforation) ~ "screened interval midpoint",
        !is.na(total_depth) ~ "total depth (no perforation data)",
        TRUE ~ NA_character_
      )
    ) %>%
    dplyr::select(clean_name = well_name, depth_ft, depth_source)

  map_data_all <- per_well_cluster %>%
    dplyr::left_join(coords, by = "clean_name") %>%
    dplyr::left_join(wells_depth, by = "clean_name") %>%
    dplyr::filter(!is.na(latitude))

  n_outside_bbox <- sum(map_data_all$longitude < bbox["lon_min"] | map_data_all$longitude > bbox["lon_max"] |
                          map_data_all$latitude < bbox["lat_min"] | map_data_all$latitude > bbox["lat_max"])

  map_data <- map_data_all %>%
    dplyr::filter(longitude >= bbox["lon_min"], longitude <= bbox["lon_max"],
                  latitude >= bbox["lat_min"], latitude <= bbox["lat_max"])

  message("[facies_map] Cropped to the Steamboat Hills field bounding box: ", nrow(map_data),
          " of ", nrow(map_data_all), " wells/locations shown (",
          n_outside_bbox, " background creek/regional stations fall outside this box and are excluded from the map).")

  message("[facies_map] ", nrow(map_data), " wells/locations with coordinates plotted; ",
          sum(!is.na(map_data$depth_ft)), " have an approximate depth (",
          sum(map_data$depth_source == "screened interval midpoint", na.rm = TRUE),
          " from a real screened interval, ",
          sum(map_data$depth_source == "total depth (no perforation data)", na.rm = TRUE),
          " from total depth only); ",
          sum(is.na(map_data$depth_ft)), " have no depth on record (shown hollow).")

  map_data$has_depth <- !is.na(map_data$depth_ft)

  caption_txt <- paste(
    "Depth is a coarse proxy (screened-interval midpoint, then total depth,",
    "then unknown), not a 3D geologic model -- see the README Leapfrog scoping section."
  )

  p <- ggplot(map_data, aes(x = longitude, y = latitude)) +
    geom_point(data = subset(map_data, has_depth),
               aes(color = facies_cluster, size = depth_ft), alpha = 0.85) +
    geom_point(data = subset(map_data, !has_depth),
               aes(color = facies_cluster), shape = 1, size = 3, stroke = 1.1) +
    ggrepel::geom_text_repel(aes(label = clean_name), size = 2.6, max.overlaps = 25, seed = 5820) +
    scale_size_continuous(name = "Approx. depth (ft)\n(screened interval\nmidpoint or total depth)",
                           range = c(2, 9)) +
    coord_fixed(ratio = 1.3) +
    labs(x = "Longitude", y = "Latitude", color = "Facies cluster",
         title = "Hydrochemical facies clusters mapped onto well/location positions",
         subtitle = "Point size = approximate reservoir/completion depth where known; hollow points have no depth on record",
         caption = caption_txt) +
    theme_minimal()

  list(plot = p, data = map_data)
}
