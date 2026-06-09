# --------------------------------------------------
# Master update script: ALL DATA SOURCES
# --------------------------------------------------

library(DBI)
library(RSQLite)

con <- dbConnect(SQLite(), "database/geochem_sampling.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# NDEP
source("scripts/ingest/ingest_ndep.R")

# Field data
source("scripts/ingest/ingest_field.R")

# Lab data
source("scripts/ingest/ingest_lab.R")

# sensor data
source("scripts/ingest/ingest_temperature_loggers.R")

# QC
source("scripts/qc/qc_checks.R")
run_qc_checks(con)

dbDisconnect(con)

message("Database update complete.")