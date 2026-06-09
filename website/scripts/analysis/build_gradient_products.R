library(DBI)
library(dplyr)
library(sf)

build_gradient_products <- function(con) {
  
  message("[GRADIENT] Building visualization-ready products")
  
  grad <- dbGetQuery(con, "SELECT * FROM Hydraulic_Gradients")
  
  # ✅ filter again (lightweight)
  grad <- grad %>%
    filter(
      distance_m <= 1500,
      abs(gradient) >= 0.001
    )
  
  # ✅ rebuild geometry from wells (reuse export logic)
  wells <- dbGetQuery(con, "
    SELECT well_id, latitude, longitude
    FROM Wells
  ")
  
  grad <- grad %>%
    left_join(wells, by = c("well_id_1" = "well_id")) %>%
    rename(lat1 = latitude, lon1 = longitude) %>%
    left_join(wells, by = c("well_id_2" = "well_id")) %>%
    rename(lat2 = latitude, lon2 = longitude)
  
  pts1 <- st_as_sf(grad, coords = c("lon1","lat1"), crs = 4326)
  pts2 <- st_as_sf(grad, coords = c("lon2","lat2"), crs = 4326)
  
  pts1 <- st_transform(pts1, 32611)
  pts2 <- st_transform(pts2, 32611)
  
  c1 <- st_coordinates(pts1)
  c2 <- st_coordinates(pts2)
  
  scale_factor <- 200
  
  geom <- lapply(seq_len(nrow(grad)), function(i) {
    
    dx <- c2[i,1] - c1[i,1]
    dy <- c2[i,2] - c1[i,2]
    mag <- abs(grad$gradient[i])
    
    ux <- dx / sqrt(dx^2 + dy^2)
    uy <- dy / sqrt(dx^2 + dy^2)
    
    end <- c(
      c1[i,1] + ux * mag * scale_factor,
      c1[i,2] + uy * mag * scale_factor
    )
    
    st_linestring(rbind(c1[i,], end))
  })
  
  grad_sf <- st_sf(
    grad,
    geometry = st_sfc(geom, crs = 32611)
  )
  
  grad_sf$geom_wkt <- st_as_text(grad_sf$geometry)
  
  dbWriteTable(
    con,
    "Gradient_Vectors_Scaled",
    st_drop_geometry(grad_sf),
    overwrite = TRUE
  )
  return(grad_sf)
}