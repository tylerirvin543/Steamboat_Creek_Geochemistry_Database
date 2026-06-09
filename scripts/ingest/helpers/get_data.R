get_temp_data <- function(con) {
  df <- dbGetQuery(con, "
    SELECT
      t.logger_id,
      m.station_id,   -- ✅ added
      l.coord_key,
      l.latitude,
      l.longitude,
      datetime(t.timestamp, 'unixepoch') AS time,
      t.temperature
    FROM Temperature_Observations t
    JOIN Temperature_Loggers lg ON t.logger_id = lg.logger_id
    JOIN Locations l ON lg.location_id = l.location_id
    LEFT JOIN Logger_Station_Map m ON t.logger_id = m.logger_id
  ")
  
  return(df)
}

get_usgs_data <- function(con) {
  dbGetQuery(con, "
    SELECT
      u.station_id,
      u.datetime,
      u.value * 0.0283168 AS discharge_m3_s,
      s.latitude,
      s.longitude
    FROM USGS_Timeseries u
    JOIN USGS_Stations s
      ON u.station_id = s.station_id
    WHERE u.parameter_code = '60'
  ")
}

get_sample_data <- function(con) {
  dbGetQuery(con, "
    SELECT
      s.sample_id,
      s.location_id,
      datetime(s.collection_time, 'unixepoch') AS sample_time,
      l.latitude,
      l.longitude
    FROM Samples s
    JOIN Locations l ON s.location_id = l.location_id
  ")
}