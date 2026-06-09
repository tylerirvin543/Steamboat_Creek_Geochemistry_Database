# ============================================================
# run_pipeline.R
#
# Purpose:
# Master orchestration script for the hydrothermal data system.
# This script is designed to be the single entry point for executing the entiredata workflow,
# from raw ingestion to final exports.
#
# Executes:
#  - Database setup
#  - Data ingestion (multi-source)
#  - Derived analysis (hydraulic head, gradients)
#  - QA/QC validation and audits
#  - GIS export (GeoPackage)
#  - Website data export (CSV)
#
# Design Principles:
#  - Fully reproducible
#  - Single database (source of truth)
#  - Clear stage-based execution
#  - Transparent logging for debugging
#
# ============================================================
# 
# ============================
# LOAD LIBRARIES
# ============================
library(DBI)
library(RSQLite)
library(dplyr)

# ============================
# CONFIGURATION
# ============================

if (basename(getwd()) == "scripts") setwd("..")

DB_DEMO <- "database/geochem_demo.sqlite"
DB_PROD <- "database/geochem_operational.sqlite"

MODE <- "DEMO"   # DEMO | OPERATIONAL
DB_PATH <- if (MODE == "DEMO") DB_DEMO else DB_PROD

RUN_INGEST <- list(
  ndep   = TRUE,
  field  = TRUE,
  logger = TRUE,
  ndwr   = TRUE,
  lab    = TRUE,
  isotope  = TRUE,
  flux   = FALSE,
  usgs   = TRUE
)

# ============================
# CONNECT DATABASE
# ============================

message("\n==============================")
message(" STARTING PIPELINE")
message("==============================")

dir.create("database", recursive = TRUE, showWarnings = FALSE)

message("\n[SETUP] Connecting to database:")
message("  Path: ", DB_PATH)
message("  Mode: ", MODE)

con <- dbConnect(SQLite(), DB_PATH)
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ============================
# LOAD CORE COMPONENTS
# ============================

message("\n[SETUP] Loading schema + helpers")

source("database/schema/01_define_schema.R")

source("scripts/ingest/helpers/parse_datetime.R")
source("scripts/ingest/helpers/update_geometry.R")

source("scripts/analysis/create_analysis_views.R")
source("scripts/analysis/calc_gradients.R")

source("scripts/ingest/create_gis_views.R")
source("scripts/ingest/export_geopackage.R")

source("scripts/qc/validate_database.R")
source("scripts/qc/qc_data_integrity_checks.R")
source("scripts/qc/audit_sample_duplicates.R")

message("\n[SETUP] Loading time-series alignment helpers")

source("scripts/ingest/helpers/align_timeseries.R")
source("scripts/ingest/helpers/get_data.R")
source("scripts/ingest/helpers/temp_flow.R")
source("scripts/ingest/helpers/sample_flow.R")
source("scripts/ingest/helpers/sample_flux.R")
source("scripts/ingest/helpers/nearest_station.R")

message("\n[SETUP] Loading advanced analysis helpers")

source("scripts/analysis/build_gradient_products.R")
source("scripts/analysis/build_temp_gradient_links.R")
source("scripts/analysis/build_isotope_pairs.R")
source("scripts/analysis/build_analysis_products.R")

# optional
source("scripts/ingest/helpers/interpolate_timeseries.R")
source("scripts/ingest/helpers/lag_analysis.R")

# ============================
# DEMO RESET
# ============================

if (MODE == "DEMO") {
  
  message("\n[RESET] DEMO mode → rebuilding database")
  
  dbDisconnect(con)
  unlink(DB_PATH)
  
  con <- dbConnect(SQLite(), DB_PATH)
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  
  source("database/schema/01_define_schema.R")
}

# ============================================================
# INGEST STAGE
# ============================================================

message("\n==============================")
message(" INGEST STAGE")
message("==============================")

run_step <- function(flag, name, expr) {
  if (flag) {
    message("\n[INGEST] ---- ", name, " ----")
    start_time <- Sys.time()
    
    force(expr)
    
    end_time <- Sys.time()
    message("[INGEST] Completed ", name,
            " (", round(difftime(end_time, start_time, units = "secs"), 1), " sec)")
  } else {
    message("\n[INGEST] Skipping ", name)
  }
}

run_step(RUN_INGEST$ndep, "NDEP", {
  source("scripts/ingest/ingest_ndep.R")
})

run_step(RUN_INGEST$field, "FIELD", {
  source("scripts/ingest/ingest_field.R")
  ingest_field(con)
})

run_step(RUN_INGEST$logger, "TEMPERATURE LOGGERS", {
  source("scripts/ingest/ingest_temperature_loggers.R")
  ingest_temperature_loggers(con)
})

run_step(RUN_INGEST$ndwr, "NDWR WELLS + WATER LEVELS", {
  source("scripts/ingest/ingest_ndwr.R")
  
  ingest_ndwr(
    con,
    "data/raw/ndwr/PV_NDWR_SiteData_2026_05_31.xlsx",
    "data/raw/ndwr/PV_NDWR_WaterLevelData_2026_05_31.xlsx"
  )
  
  ingest_ndwr(
    con,
    "data/raw/ndwr/TM_NDWR_SiteData_2026_05_31.xlsx",
    "data/raw/ndwr/TM_NDWR_WaterLevelData_2026_05_31.xlsx"
  )
})

run_step(RUN_INGEST$lab, "LAB", {
  source("scripts/ingest/ingest_lab.R")
  ingest_lab(con)
})

run_step(RUN_INGEST$isotope, "ISOTOPES", {
  source("scripts/ingest/ingest_isotopes.R")
  ingest_isotopes(con)
})

run_step(RUN_INGEST$flux, "FLUX", {
  source("scripts/ingest/ingest_flux.R")
  ingest_flux(con)
})

run_step(RUN_INGEST$usgs, "USGS", {
  source("scripts/ingest/ingest_usgs.R")
  ingest_usgs(con)
})

# ============================================================
# PROCESSING STAGE (PHASE 1: CORE SQL VIEWS)
# ============================================================

message("\n==============================")
message(" PROCESSING STAGE (CORE)")
message("==============================")

message("\n[PROCESS] Updating geometry")
update_location_geometry(con)

# ------------------------------------------------------------
# ✅ Build ONLY core, dependency-free views first
# ------------------------------------------------------------
message("\n[PROCESS] Creating base analysis views")

create_analysis_views(con)   # safe: builds core + placeholders


# ============================================================
# TIMESERIES ALIGNMENT (R-BASED)
# ============================================================

message("\n==============================")
message(" TIMESERIES ALIGNMENT (R)")
message("==============================")

message("\n[ALIGN] Building temperature-flow relationships")

start_time <- Sys.time()
build_temp_flow(con)
message("[ALIGN] temp_flow completed in ",
        round(difftime(Sys.time(), start_time, units = "secs"), 1), " sec")

message("\n[ALIGN] Building sample-flow relationships")

start_time <- Sys.time()
build_sample_flow(con)
message("[ALIGN] sample_flow completed in ",
        round(difftime(Sys.time(), start_time, units = "secs"), 1), " sec")

message("\n[ALIGN] Building sample hydrochem flux")

start_time <- Sys.time()
build_sample_flux(con)
message("[ALIGN] sample_flux completed in ",
        round(difftime(Sys.time(), start_time, units = "secs"), 1), " sec")


# ============================================================
# ✅ PROCESSING STAGE (PHASE 2: FLOW-DEPENDENT VIEWS)
# ============================================================

message("\n==============================")
message(" PROCESSING STAGE (FLOW-DEPENDENT)")
message("==============================")

# ------------------------------------------------------------
# ✅ NOW rebuild ONLY the view(s) that depend on alignment
# ------------------------------------------------------------

if (dbExistsTable(con, "sample_flow")) {
  
  message("[PROCESS] Creating vw_sample_with_flow (post-alignment)")
  
  dbExecute(con, "DROP VIEW IF EXISTS vw_sample_with_flow")
  
  dbExecute(con, "
    CREATE VIEW vw_sample_with_flow AS
    SELECT * FROM sample_flow
  ")
  
  message("✅ vw_sample_with_flow ready")
  
} else {
  stop("sample_flow missing — cannot build vw_sample_with_flow")
}

# ============================================================
# HYDRAULIC GRADIENTS
# ============================================================

message("\n[PROCESS] Computing hydraulic gradients")
obs_count <- dbGetQuery(con, "
  SELECT COUNT(*) n FROM Water_Level_Observations
")$n

grad_count <- if (dbExistsTable(con, "Hydraulic_Gradients")) {
  dbGetQuery(con, "SELECT COUNT(*) n FROM Hydraulic_Gradients")$n
} else {
  0
}

if (grad_count == 0 || grad_count < obs_count) {
  
  message("[PROCESS] Recomputing gradients (new data detected)")
  
  grad <- calc_gradients(con)
  
  dbWriteTable(
    con,
    "Hydraulic_Gradients",
    grad,
    overwrite = TRUE
  )
  
  dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_grad_time
ON Hydraulic_Gradients(timestamp)
")
  
  dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_grad_wells
ON Hydraulic_Gradients(well_id_1, well_id_2)
")
  
  dbExecute(con, "
CREATE VIEW IF NOT EXISTS vw_hydraulic_gradients AS
SELECT * FROM Hydraulic_Gradients
")
  
} else {
  
  message("[PROCESS] Gradients up-to-date — skipping")
  
  grad <- dbReadTable(con, "Hydraulic_Gradients")
}

dbExecute(con, "
CREATE VIEW IF NOT EXISTS vw_hydraulic_gradients AS
SELECT * FROM Hydraulic_Gradients
")

message("  → Stored ", nrow(grad), " gradient vectors")

# ============================================================
# ADVANCED ANALYSIS PRODUCTS
# ============================================================

message("\n==============================")
message(" ADVANCED ANALYSIS PRODUCTS")
message("==============================")

run_analysis_step <- function(name, expr) {
  message("\n[ANALYSIS] ---- ", name, " ----")
  start_time <- Sys.time()
  
  tryCatch({
    force(expr)
    elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)
    message("[ANALYSIS] Completed ", name, " (", elapsed, " sec)")
  }, error = function(e) {
    warning("[ANALYSIS] Failed ", name, ": ", e$message)
  })
}

run_analysis_step("Gradient Vector Products", {
  build_gradient_products(con)
})

run_analysis_step("Temperature + Gradient Link", {
  build_temp_gradient_links(con)
})

run_analysis_step("Isotope Pairs", {
  build_isotope_pairs(con)
})

run_analysis_step("Integrated Analysis Products", {
  build_analysis_products(con)
})

# ============================================================
# QA / QC STAGE
# ============================================================

message("\n==============================")
message(" QA / QC STAGE")
message("==============================")

message("\n[QC] Running integrity checks")
run_qc_checks(con)

message("\n[QC] Validating database relationships")
validate_database(con)

message("\n[QC] Auditing duplicate samples")
audit_sample_duplicates(con)

# ============================================================
# EXPORT STAGE
# ============================================================

message("\n==============================")
message(" EXPORT STAGE")
message("==============================")

message("\n[EXPORT] Creating GIS views")
create_gis_views(con)

message("\n[EXPORT] Writing GeoPackage")
export_geopackage(con, mode = MODE)

# ============================================================
# WEBSITE EXPORT
# ============================================================

message("\n[EXPORT] Writing website CSV outputs")

dir.create("website/data", recursive = TRUE, showWarnings = FALSE)

write.csv(
  dbGetQuery(con, "
    SELECT timestamp, data_source, measurements_inserted
    FROM Ingest_Run_Log
    ORDER BY timestamp
  "),
  "website/data/ingest_log.csv",
  row.names = FALSE
)

write.csv(
  dbGetQuery(con, "
    SELECT logger_id, timestamp, temperature
    FROM Temperature_Observations
  "),
  "website/data/temp_sample.csv",
  row.names = FALSE
)

write.csv(
  dbGetQuery(con, "
    SELECT 
      w.well_id,
      w.ndwr_site_id,
      w.latitude,
      w.longitude,
      w.mid_screen_depth,
      w.total_depth,
      w.basin_name
    FROM Wells w
  "),
  "website/data/well_sample.csv",
  row.names = FALSE
)

# ============================================================
# CLEANUP
# ============================================================

dbDisconnect(con)

message("\n==============================")
message(" PIPELINE COMPLETE ✅")
message("==============================\n")
