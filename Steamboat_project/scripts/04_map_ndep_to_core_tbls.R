#04_map_ndep_to_core_tbls
library(DBI)
library(dplyr)
library(RSQLite)

con <- dbConnect(SQLite(), "geochem_sampling.sqlite")

# Register data source
dbExecute(con, "
INSERT INTO Data_Sources (name, citation, url)
VALUES (
  'Nevada DEP Water Quality Portal',
  'Nevada Division of Environmental Protection',
  'https://nevadawaterquality.ndep.nv.gov'
);
")

source_id <- dbGetQuery(con,
                        "SELECT source_id FROM Data_Sources WHERE name LIKE 'Nevada DEP%'"
)$source_id[1]

ndep <- dbReadTable(con, "Staging_NDEP_WQ")

# Locations
locations <- ndep %>%
  distinct(station_name, latitude, longitude) %>%
  transmute(
    name = station_name,
    latitude,
    longitude,
    site_type = "background",
    notes = "Imported from NDEP"
  )

dbWriteTable(con, "Locations", locations, append = TRUE)

# Events
events <- ndep %>%
  distinct(station_name, sample_date) %>%
  transmute(
    date = sample_date,
    purpose = "historical",
    observer = "NDEP",
    weather_conditions = NA
  )

dbWriteTable(con, "Sampling_Events", events, append = TRUE)

dbDisconnect(con)
