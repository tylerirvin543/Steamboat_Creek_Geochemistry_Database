plot_logger_qc <- function(con) {

library(ggplot2)

logger_ts <- dbGetQuery(con, "
SELECT
  tl.logger_name,
  o.timestamp,
  o.temperature
FROM Temperature_Observations o
JOIN Temperature_Loggers tl ON o.logger_id = tl.logger_id;
")

ggplot(logger_ts, aes(timestamp, temperature)) +
  geom_line() +
  facet_wrap(~logger_name, scales = "free_x") +
  labs(
    title = "Temperature Logger Time Series",
    x = "Time",
    y = "Temperature (°C)"
  )
########################
temp_compare <- dbGetQuery(con, "
SELECT
  s.collection_time,
  f.value - o.temperature AS temp_diff
FROM Samples s
JOIN Field_Measurements f
  ON s.sample_id = f.sample_id
 AND f.parameter = 'temperature'
JOIN Temperature_Loggers tl
  ON s.location_id = tl.location_id
JOIN Temperature_Observations o
  ON tl.logger_id = o.logger_id
WHERE ABS(julianday(o.timestamp) - julianday(s.collection_time)) <
      1.0/24.0;
")

ggplot(temp_compare, aes(collection_time, temp_diff)) +
  geom_point() +
  geom_hline(yintercept = 0, linetype = "dashed") +
  labs(
    title = "Field minus Logger Temperature",
    y = "Δ Temperature (°C)"
  )
}