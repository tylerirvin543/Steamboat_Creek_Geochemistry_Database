#02_define_validators
library(checkmate)
library(DBI)

validate_locations <- function(df) {
  assert_names(names(df), must.include =
                 c("name", "latitude", "longitude", "site_type"))
  assert_numeric(df$latitude, lower = -90, upper = 90)
  assert_numeric(df$longitude, lower = -180, upper = 180)
  TRUE
}

validate_samples <- function(df, con) {
  locs <- dbGetQuery(con, "SELECT location_id FROM Locations")$location_id
  events <- dbGetQuery(con, "SELECT event_id FROM Sampling_Events")$event_id
  assert_subset(df$location_id, locs)
  assert_subset(df$event_id, events)
  TRUE
}
