assign_nearest_station <- function(temp, usgs_meta) {
  
  library(data.table)
  
  temp_dt <- as.data.table(temp)[, .(logger_id, latitude, longitude)]
  usgs_dt <- unique(as.data.table(usgs_meta)[, .(station_id, latitude, longitude)])
  
  temp_dt <- temp_dt[!is.na(latitude) & !is.na(longitude)]
  usgs_dt <- usgs_dt[!is.na(latitude) & !is.na(longitude)]
  
  # cross join
  temp_dt[, key := 1]
  usgs_dt[, key := 1]
  
  pairs <- merge(temp_dt, usgs_dt, by = "key", allow.cartesian = TRUE)
  pairs[, key := NULL]
  
  # distance
  pairs[, dist := sqrt((latitude.x - latitude.y)^2 + (longitude.x - longitude.y)^2)]
  
  # nearest station
  mapping <- pairs[, .SD[which.min(dist)], by = logger_id]
  
  return(mapping[, .(logger_id, station_id)])
}