#03_ingest_ndep_raw
library(DBI)
library(RSQLite)

con <- dbConnect(SQLite(), "geochem_sampling.sqlite")

ndep_raw <- read.csv(
  "data/ndep_export.csv",
  stringsAsFactors = FALSE
)

dbWriteTable(
  con,
  "Staging_NDEP_WQ",
  ndep_raw,
  append = TRUE
)

dbDisconnect(con)