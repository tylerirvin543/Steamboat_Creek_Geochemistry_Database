#05_field_data_entry
library(DBI)
library(RSQLite)

locations <- read_excel("field/locations.xlsx")
events <- read_excel("field/sampling_events.xlsx")
samples <- read_excel("field/samples.xlsx")
field_meas <- read_excel("field/field_measurements.xlsx")


con <- dbConnect(SQLite(), "geochem_sampling.sqlite")

dbExecute(con, "
INSERT INTO Sampling_Events (date, purpose, observer)
VALUES ('2026-03-15', 'baseline', 'T. Irvin');
")

dbDisconnect(con)