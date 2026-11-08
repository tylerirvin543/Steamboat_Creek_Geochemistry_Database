# ============================================================
# apply_location_coordinate_corrections.R
#
# Applies human-reviewed coordinate corrections to existing Locations rows.
#
# Why this exists: ingest_field.R only inserts a Location the first time an
# external_station_code is seen and never updates it afterwards, and
# data/raw/field/locations.xlsx is often open in Excel (so it cannot be edited
# safely). A small corrections table records the decision, the evidence and the
# old value, and this function re-applies it on every run (a database rebuild
# restores the old field coordinate, then this puts the correction back).
#
# Input: data/raw/field/location_coordinate_corrections.csv
#   external_station_code, latitude, longitude, coordinate_source,
#   coordinate_uncertainty_m, old_latitude, old_longitude, reason
#
# Guard: a row is applied only while the stored coordinate still equals the
# recorded old coordinate (within 1 m), so a later manual fix is never
# overwritten. Idempotent: once applied, the stored coordinate equals the new
# one and nothing changes.
# ============================================================
library(DBI); library(dplyr); library(readr)

apply_location_coordinate_corrections <- function(con, csv = "data/raw/field/location_coordinate_corrections.csv") {
  if (!file.exists(csv)) { message("[LOCATION CORRECTIONS] no corrections file; nothing to do"); return(invisible(0L)) }
  cr <- read_csv(csv, show_col_types = FALSE, col_types = cols(.default = col_character()))
  cr <- cr |> mutate(across(c(latitude, longitude, coordinate_uncertainty_m, old_latitude, old_longitude), as.numeric))
  hav <- function(la1, lo1, la2, lo2) {
    r <- 6371000; p <- pi / 180; a <- sin((la2 - la1) * p / 2)^2 + cos(la1 * p) * cos(la2 * p) * sin((lo2 - lo1) * p / 2)^2
    2 * r * asin(sqrt(a))
  }
  n_applied <- 0L
  for (i in seq_len(nrow(cr))) {
    x <- cr[i, ]
    cur <- dbGetQuery(con, "SELECT location_id, latitude, longitude, notes FROM Locations WHERE external_station_code = ?",
                      params = list(x$external_station_code))
    if (!nrow(cur)) { warning("Location ", x$external_station_code, " not found; correction skipped"); next }
    if (hav(cur$latitude, cur$longitude, x$latitude, x$longitude) < 1) next
    if (hav(cur$latitude, cur$longitude, x$old_latitude, x$old_longitude) > 1) {
      warning(x$external_station_code, ": stored coordinate no longer matches the recorded old value; correction not applied")
      next
    }
    note <- sprintf("[Coordinate corrected: old %.6f, %.6f -> new %.6f, %.6f. %s]", x$old_latitude, x$old_longitude, x$latitude, x$longitude, x$reason)
    dbExecute(con, "UPDATE Locations SET latitude = ?, longitude = ?, coord_key = ?, coordinate_source = ?, coordinate_uncertainty_m = ?,
                    notes = CASE WHEN notes IS NULL OR notes = '' THEN ? ELSE notes || ' ' || ? END
                    WHERE location_id = ?",
              params = list(x$latitude, x$longitude, paste0(x$latitude, "_", x$longitude), x$coordinate_source,
                            x$coordinate_uncertainty_m, note, note, cur$location_id))
    # A well that points at this Location and still carries the old coordinate moves with it
    nw <- dbExecute(con, "UPDATE Wells SET latitude = ?, longitude = ?, coordinate_source = ?, coordinate_uncertainty_m = ?
                    WHERE location_id = ? AND latitude IS NOT NULL
                      AND ABS((latitude - ?) * 111320) < 1.5 AND ABS((longitude - ?) * 85000) < 1.5",
              params = list(x$latitude, x$longitude, x$coordinate_source, x$coordinate_uncertainty_m, cur$location_id,
                            x$old_latitude, x$old_longitude))
    if (nw > 0) message(sprintf("[LOCATION CORRECTIONS]   %d linked Wells row(s) moved too", nw))
    n_applied <- n_applied + 1L
    message(sprintf("[LOCATION CORRECTIONS] %s moved %.0f m (source: %s, +/-%g m)", x$external_station_code,
                    hav(x$old_latitude, x$old_longitude, x$latitude, x$longitude), x$coordinate_source, x$coordinate_uncertainty_m))
  }
  invisible(n_applied)
}
