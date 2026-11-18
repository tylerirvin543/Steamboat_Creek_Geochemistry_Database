# Map of SBS/SBW/SBF locations over the thermal layer (NBMG drone survey, O. Callahan; the same survey used by Lindsey and others, 2026).
# The thermal layer is a georeferenced layout export (EPSG:26911) with yellow analyst outlines drawn into the pixels.
library(ggplot2)
build_proposal_location_map <- function(con, out = "output/figures/manuscript/proposal_location_map.png") {
  r <- terra::rast("data/raw/IR/Callahan_2025/thermalmap_lowersinterter.tif")
  loc <- DBI::dbGetQuery(con, "select name, longitude, latitude from Locations where name in ('SBF_0001','SBF_0002','SBW_0003','SBS_0001','SBS_0002','SBS_0006','SBW_0001','SBW_0002')")
  loc <- rbind(loc, data.frame(name = "New hot spring (Sept 2026)", longitude = -119.7398, latitude = 39.3804))
  pts <- sf::st_transform(sf::st_as_sf(loc, coords = c("longitude", "latitude"), crs = 4326), 26911)
  xy <- sf::st_coordinates(pts); loc$x <- xy[, 1]; loc$y <- xy[, 2]
  e <- terra::ext(min(loc$x) - 40, max(loc$x) + 60, min(loc$y) - 40, max(loc$y) + 40)
  rc <- terra::aggregate(terra::crop(r, e), 3, fun = "mean")
  a <- terra::as.array(rc) / 255; a[is.na(a)] <- 1
  ex <- as.vector(terra::ext(rc))
  loc$group <- ifelse(grepl("^SBF|^SBW_0003", loc$name), "Fumarole / capped pipe", ifelse(grepl("^SBS|New", loc$name), "Spring or seep", "Well"))
  loc$label <- sub(" \\(Sept 2026\\)", "", loc$name)
  p <- ggplot() +
    annotation_raster(a, ex[1], ex[2], ex[3], ex[4], interpolate = TRUE) +
    geom_point(data = loc, aes(x, y, shape = group, fill = group), size = 3.4, color = "white", stroke = 0.9) +
    ggrepel::geom_label_repel(data = loc, aes(x, y, label = label), size = 3, min.segment.length = 0, box.padding = 0.4, label.size = 0.15, max.overlaps = Inf, seed = 11) +
    scale_shape_manual(values = c("Fumarole / capped pipe" = 24, "Spring or seep" = 21, "Well" = 22), name = NULL) +
    scale_fill_manual(values = c("Fumarole / capped pipe" = "#d95f02", "Spring or seep" = "#1b9e77", "Well" = "#7570b3"), name = NULL) +
    coord_fixed(xlim = ex[1:2], ylim = ex[3:4], expand = FALSE) +
    labs(x = "Easting (m, EPSG:26911)", y = "Northing (m)") +
    theme_minimal(base_size = 9) + theme(legend.position = "bottom")
  w <- 6.2; h <- w * diff(ex[3:4]) / diff(ex[1:2]) + 0.9
  ggsave(out, p, width = w, height = min(h, 8.5), dpi = 200, bg = "white")
  invisible(loc)
}
