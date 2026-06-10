# ============================================================
# calc_gradients.R (REFACTORED)
# ============================================================

library(DBI)
library(dplyr)
library(sf)

calc_gradients <- function(con, max_distance = 2000) {
  
  message("---- Calculating hydraulic gradients ----")
  
  # ==================================================
  # 1. LOAD DATA
  # ==================================================
  
  df <- dbGetQuery(con, "
    SELECT 
      well_id,
      timestamp,
      hydraulic_head,
      latitude,
      longitude,
      coord_key
    FROM vw_hydraulic_head_clean
  ")
  
  if (nrow(df) == 0) {
    stop("No hydraulic head data available.")
  }
  
  # ==================================================
  # 2. PROJECT TO METERS
  # ==================================================
  
  wells_sf <- st_as_sf(
    df,
    coords = c("longitude", "latitude"),
    crs = 4326
  ) |>
    st_transform(32611)
  
  coords <- st_coordinates(wells_sf)
  
  wells_df <- wells_sf |>
    st_drop_geometry() |>
    mutate(
      x = coords[,1],
      y = coords[,2]
    )
  
  # ==================================================
  # 3. BUILD WELL PAIRS
  # ==================================================
  
  message("  → Building well pairs (by timestamp)...")
  
  pairs <- inner_join(
    wells_df,
    wells_df,
    by = "timestamp",
    suffix = c("_1", "_2"),
    relationship = "many-to-many"
  ) |>
    filter(
      well_id_1 < well_id_2,
      coord_key_1 != coord_key_2
    )
  
  message("  → Candidate pairs: ", nrow(pairs))
  
  # ==================================================
  # 4. DISTANCE + FILTER
  # ==================================================
  
  pairs <- pairs |>
    mutate(
      dx = x_2 - x_1,
      dy = y_2 - y_1,
      distance_m = sqrt(dx^2 + dy^2)
    ) |>
    filter(
      distance_m > 0,
      distance_m <= max_distance
    )
  
  message("  → Pairs within distance threshold: ", nrow(pairs))
  
  if (nrow(pairs) == 0) {
    warning("No valid well pairs within distance threshold.")
    return(data.frame())
  }
  
  # ==================================================
  # 5. GRADIENT + DIRECTION
  # ==================================================
  
  pairs <- pairs |>
    mutate(
      head_diff = hydraulic_head_1 - hydraulic_head_2,
      gradient  = head_diff / distance_m,
      direction_deg = (atan2(dy, dx) * 180 / pi + 360) %% 360,
      gradient_class = case_when(
        abs(gradient) < 0.001 ~ "low",
        abs(gradient) < 0.01  ~ "moderate",
        TRUE                  ~ "high"
      )
    )
  
  # ==================================================
  # 6. BUILD LINE GEOMETRY (CLEAN + MINIMAL)
  # ==================================================
  
  geom_list <- lapply(seq_len(nrow(pairs)), function(i) {
    st_linestring(matrix(
      c(
        pairs$x_1[i], pairs$y_1[i],
        pairs$x_2[i], pairs$y_2[i]
      ),
      ncol = 2,
      byrow = TRUE
    ))
  })
  
  result_sf <- st_as_sf(
    pairs,
    geometry = st_sfc(geom_list, crs = 32611)
  )
  
  # ==================================================
  # 7. FINAL OUTPUT (LEAN)
  # ==================================================
  
  result <- result_sf |>
    dplyr::select(
      timestamp,
      well_id_1,
      well_id_2,
      coord_key_1,
      coord_key_2,
      distance_m,
      head_diff,
      gradient,
      gradient_class,
      direction_deg,
      geometry
    )
  
  message("✅ Gradient vectors created: ", nrow(result))
  
  return(result)
}