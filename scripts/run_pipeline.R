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
library(rmarkdown)

# ============================
# CONFIGURATION
# ============================

if (basename(getwd()) == "scripts") setwd("..")

DB_DEMO <- "database/geochem_demo.sqlite"
DB_PROD <- "database/geochem_operational.sqlite"

# ============================================================
# PIPELINE ENTRY POINT / QUICK START
# ============================================================
# Sourcing this script interactively (e.g. from the RStudio console)
# asks three quick questions -- which database to target, which
# ingestion profile to run, and whether to rebuild the website --
# then runs unattended. Non-interactive runs (Rscript, CI) skip the
# prompts and default to a safe DEMO rebuild with all working
# sources enabled.
#
# Every ingest step behind these choices is designed to be safe to
# re-run: sources that already exist are skipped or left untouched
# (file-level tracking tables, coordinate/natural-key anti_joins, or
# a UNIQUE-indexed Data_Sources.name -- see each
# scripts/ingest/ingest_*.R for its specific mechanism), so running
# with the same choices twice in a row should insert nothing new the
# second time.
#
# To skip the prompts entirely and run with fixed choices (e.g. from
# another script, or to override just one thing), set MODE,
# RUN_INGEST, and/or BUILD_WEBSITE directly before sourcing this
# file -- any of the three already set will be left alone below.
# ============================================================

pipeline_menu <- function() {
  mode_choice <- utils::menu(
    c("DEMO -- rebuild a throwaway demo database from scratch (safe, always starts empty)",
      "OPERATIONAL -- update the real project database, preserving existing data"),
    title = "\nWhich database should this run target?"
  )
  mode <- if (mode_choice == 2) "OPERATIONAL" else "DEMO"  # 0 (cancelled) or 1 -> safe default

  profile_choice <- utils::menu(
    c("All available sources (recommended)",
      "Core chemistry only (NDEP, field, lab, isotopes -- skip loggers/USGS/weather/photos)",
      "Skip ingestion entirely -- just rebuild views, QC, and exports from what is already in the database"),
    title = "\nWhich data sources should be ingested?"
  )
  if (profile_choice == 0) profile_choice <- 1  # cancelled -> safe default

  website_choice <- utils::menu(
    c("No (faster -- rebuild separately later with rmarkdown::render_site if needed)",
      "Yes, rebuild the website too"),
    title = "\nRebuild the documentation website after this run?"
  )

  list(mode = mode, profile = profile_choice, build_website = identical(website_choice, 2L))
}

# Named by profile_choice above. flux (Cl-discharge transects) is now on
# in the chemistry-bearing presets: data/raw/discharge/stream_discharge.xlsx
# had two columns both literally named "transect_id" per sheet, a
# source-spreadsheet defect resolved 2026-09-05 -- see ingest_flux.R for
# which one is authoritative and why. The file itself is still just a
# header-only template with no populated rows yet, so this currently
# ingests 0 rows; it's wired in now so real transect data starts flowing
# the moment it's entered, without needing another pipeline-code change.
profile_presets <- list(
  `1` = list(ndep = TRUE, field = TRUE, logger = TRUE, conductivity = TRUE, ndwr = TRUE,
             lab = TRUE, isotope = TRUE, flux = TRUE, usgs = TRUE, usgs_historic_chem = TRUE,
             noaa_weather = TRUE, image_locations = TRUE, ndep_prr = TRUE,
             monitor_well_locations = TRUE, promote_ndep_staged = TRUE, well_network = TRUE, well_logs = TRUE),
  `2` = list(ndep = TRUE, field = TRUE, logger = FALSE, conductivity = FALSE, ndwr = FALSE,
             lab = TRUE, isotope = TRUE, flux = TRUE, usgs = FALSE, usgs_historic_chem = FALSE,
             noaa_weather = FALSE, image_locations = FALSE, ndep_prr = FALSE,
             monitor_well_locations = TRUE, promote_ndep_staged = TRUE, well_network = TRUE, well_logs = TRUE),
  `3` = list(ndep = FALSE, field = FALSE, logger = FALSE, conductivity = FALSE, ndwr = FALSE,
             lab = FALSE, isotope = FALSE, flux = FALSE, usgs = FALSE, usgs_historic_chem = FALSE,
             noaa_weather = FALSE, image_locations = FALSE, ndep_prr = FALSE,
             monitor_well_locations = FALSE, promote_ndep_staged = FALSE, well_network = FALSE, well_logs = FALSE)
)

if (!exists("MODE") || !exists("RUN_INGEST") || !exists("BUILD_WEBSITE")) {
  if (interactive()) {
    .pipeline_choices <- pipeline_menu()
    if (!exists("MODE")) MODE <- .pipeline_choices$mode
    if (!exists("RUN_INGEST")) RUN_INGEST <- profile_presets[[as.character(.pipeline_choices$profile)]]
    if (!exists("BUILD_WEBSITE")) BUILD_WEBSITE <- .pipeline_choices$build_website
  } else {
    message("[QUICK START] Non-interactive session -- defaulting to MODE=", "DEMO", ", all working sources, no website build.")
    if (!exists("MODE")) MODE <- "DEMO"
    if (!exists("RUN_INGEST")) RUN_INGEST <- profile_presets[["1"]]
    if (!exists("BUILD_WEBSITE")) BUILD_WEBSITE <- FALSE
  }
}

# RUN_ANALYSIS is a small, separate flag list (not folded into RUN_INGEST)
# for derived-modeling stages that are not data ingestion. PHREEQC calls an
# external executable per sample and can be slow, so it defaults to FALSE
# and must be explicitly opted into -- set RUN_ANALYSIS <- list(phreeqc = TRUE)
# before sourcing this file to enable it for a given run. Mixing/inverse/
# gas-phase modeling are not run automatically at all (see
# scripts/phreeqc/run_phreeqc_analysis.R) since they require the caller to
# name real end-member sample_ids, which should never be guessed.
if (!exists("RUN_ANALYSIS")) RUN_ANALYSIS <- list(phreeqc = FALSE)

DB_PATH <- if (MODE == "DEMO") DB_DEMO else DB_PROD

message("\n[QUICK START] Mode: ", MODE, " | Website rebuild: ", BUILD_WEBSITE)

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
source("database/schema/02_conductivity_schema.R")
source("database/schema/03_weather_schema.R")
source("database/schema/04_photo_location_schema.R")
source("database/schema/05_well_network_schema.R")
source("database/schema/06_facility_areas_schema.R")
source("database/schema/07_well_logs_schema.R")
source("database/schema/08_phreeqc_schema.R")

source("scripts/ingest/helpers/parse_datetime.R")
source("scripts/ingest/helpers/update_geometry.R")
source("scripts/ingest/helpers/compute_specific_conductance.R")

source("scripts/analysis/create_analysis_views.R")
source("scripts/analysis/calc_gradients.R")

source("scripts/ingest/create_gis_views.R")
source("scripts/ingest/export_geopackage.R")

source("scripts/qc/validate_database.R")
source("scripts/qc/qc_data_integrity_checks.R")
source("scripts/qc/qc_conductivity_checks.R")
source("scripts/qc/audit_sample_duplicates.R")
source("scripts/qc/create_qc_views.R")

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

source("scripts/phreeqc/utils_phreeqc.R")
source("scripts/phreeqc/08_build_phreeqc_tables.R")
source("scripts/phreeqc/09_run_phreeqc.R")
source("scripts/phreeqc/10_run_phreeqc_mixing.R")
source("scripts/phreeqc/11_run_phreeqc_inverse.R")
source("scripts/phreeqc/12_run_phreeqc_gas_phase.R")
source("scripts/phreeqc/run_phreeqc_analysis.R")

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
source("database/schema/02_conductivity_schema.R")
source("database/schema/03_weather_schema.R")
source("database/schema/04_photo_location_schema.R")
source("database/schema/05_well_network_schema.R")
source("database/schema/06_facility_areas_schema.R")
source("database/schema/07_well_logs_schema.R")
source("database/schema/08_phreeqc_schema.R")
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

run_step(RUN_INGEST$conductivity, "CONDUCTIVITY LOGGERS", {
  source("scripts/ingest/ingest_conductivity.R")
  ingest_conductivity(con)
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

run_step(RUN_INGEST$usgs_historic_chem, "USGS HISTORIC CHEMISTRY", {
  source("scripts/ingest/ingest_usgs_historic_chemistry.R")
  ingest_usgs_historic_chemistry(con)
})

run_step(RUN_INGEST$noaa_weather, "NOAA WEATHER", {
  source("scripts/ingest/ingest_noaa_weather.R")
  ingest_noaa_weather(con)
})

run_step(RUN_INGEST$image_locations, "IMAGE LOCATIONS (EXIF GPS)", {
  source("scripts/ingest/ingest_image_locations.R")
  ingest_image_locations(con)
})

run_step(RUN_INGEST$ndep_prr, "NDEP PUBLIC RECORDS REQUEST (PILOT)", {
  # NOTE: this only stages rows into Staging_NDEP_WQ. Promoting staged
  # rows into Samples/Lab_Analyses (once a station has a confirmed
  # location in data/raw/ndep/PRR/staged_ndep_location_map.csv) is a
  # deliberately separate, manual step -- see
  # scripts/ingest/promote_staged_ndep.R -- not run automatically here.
  source("scripts/ingest/ingest_ndep_prr.R")
  ingest_ndep_prr(con)
})

run_step(RUN_INGEST$promote_ndep_staged, "PROMOTE STAGED NDEP CHEMISTRY", {
  # Promotes any Staging_NDEP_WQ row whose station now has a resolved
  # lat/lon in staged_ndep_location_map.csv (e.g. Eich Well) into
  # Samples/Lab_Analyses. Idempotent: only rows with promoted_at IS
  # NULL are touched, and re-running with no newly-resolved stations
  # promotes nothing further. See scripts/ingest/promote_staged_ndep.R.
  source("scripts/ingest/promote_staged_ndep.R")
  promote_staged_ndep(con)
})

run_step(RUN_INGEST$monitor_well_locations, "LITERATURE-SOURCED MONITOR WELL LOCATIONS", {
  # Registers wells identified from literature (currently: Klein et
  # al. 2007's Fig. 1 monitor-well network) that carry no chemistry of
  # their own, so promote_staged_ndep()'s pipeline doesn't apply to
  # them. Idempotent: keyed on Locations.external_station_code
  # (UNIQUE), existing rows are left untouched. See
  # scripts/ingest/register_monitor_well_locations.R and
  # data/raw/ndwr/klein2007_monitor_well_locations.csv.
  source("scripts/ingest/register_monitor_well_locations.R")
  register_monitor_well_locations(con)
})

run_step(RUN_INGEST$well_network, "DHAKAL WELL/PORT FLOW NETWORK", {
  # Registers Wells/Well_Aliases/Sampling_Ports/Production_Port_Links/
  # Port_Injection_Links rows for the Dhakal et al. (2025) production
  # well -> port -> injection well flow network. Idempotent: only adds
  # new rows, never updates existing ones. See
  # scripts/ingest/register_well_network.R and
  # data/raw/wells/dhakal_well_network.csv /
  # data/raw/wells/well_aliases.csv.
  source("scripts/ingest/register_well_network.R")
  register_well_network(con)
  # Coordinate matches (currently NBMG Geothermal_Wells) are a separate,
  # independently-reviewed claim from network topology -- see
  # scripts/ingest/register_well_coordinates.R for provenance details.
  source("scripts/ingest/register_well_coordinates.R")
  register_well_coordinates(con)
  # Second, independent coordinate source: ArcGIS satellite-overlay
  # digitization of the Dhakal figure (data/raw/arcgis/*.shp). Same
  # never-overwrite idempotency -- only fills wells still missing a
  # coordinate after the NBMG pass above.
  register_well_coordinates(con, coords_csv = "data/raw/wells/dhakal_wells_arcgis.csv")
  source("scripts/ingest/register_facility_areas.R")
  register_facility_areas(con)

run_step(RUN_INGEST$well_logs, "WELL LOG PDFs", {
  # Stages NDWR "WELL DRILLER'S REPORT" PDFs (data/raw/ndwr/Ormat_well_logs/)
  # into Well_Log_Documents -- most have no extractable text (OCR
  # blocked in this sandbox, per earlier sessions), so this mostly
  # captures whatever an NDWR log-number cross-reference can supply
  # (owner, PLSS location, coordinates, completion date) rather than
  # full drillers-report detail. Idempotent on (file_path, file_hash).
  # See scripts/ingest/ingest_well_logs.R.
  source("scripts/ingest/ingest_well_logs.R")
  ingest_well_logs(con)
  # Promotion to Wells/Water_Level_Observations requires a human-
  # confirmed log_number -> well_name mapping (identity is NOT
  # guessed from an NDWR cross-references bare "ORMAT" owner name) --
  # see data/raw/ndwr/well_log_document_map.csv (currently empty; no
  # confident matches established yet).
  promote_well_log_documents(con)
  # 2026-09-05 (session 11): none of the 7 real Steamboat logs cleared
  # the bar for a confident name match after cross-checking NBMG dates
  # AND locations together (see AGENTS.md) -- rather than leaving this
  # real coordinate/depth/water-level data stranded in staging, give
  # each a provisional Wells row so it's visible/mappable while staying
  # unambiguous that it isn't a confirmed identity match.
  register_provisional_well_logs(con)
})
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
# PHREEQC GEOCHEMICAL MODELING (speciation, SI, geothermometry)
# ============================================================

message("\n==============================")
message(" PHREEQC GEOCHEMICAL MODELING")
message("==============================")

if (isTRUE(RUN_ANALYSIS$phreeqc)) {
  message("[PHREEQC] Building PHREEQC_Solutions from Lab_Analyses + Field_Measurements + Isotope_Analyses")
  build_phreeqc_solutions(con)
  message("[PHREEQC] Running speciation + saturation index pipeline")
  run_phreeqc_pipeline(con)
} else {
  message("[PHREEQC] Skipping (RUN_ANALYSIS$phreeqc = FALSE). Run manually via scripts/phreeqc/run_phreeqc_analysis.R for speciation, temperature-sweep geothermometry, mixing, inverse modeling, or gas-phase modes.")
}


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

message("\n[QC] Validating database relationships")
validate_database(con)

message("\n[QC] Running integrity checks")
run_qc_checks(con)

message("\n[QC] Running conductivity-specific checks")
run_conductivity_qc_checks(con)

message("\n[QC] Building QC views")
create_qc_views(con)

message("\n[QC] Auditing duplicate samples")
audit_sample_duplicates(con)

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_qc_created_at
ON QC_Issues(created_at)
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_qc_time_type
ON QC_Issues(created_at, issue_type)
")

# ============================================================
# QC REPORT GENERATION STAGE
# ============================================================

message("\n==============================")
message(" REPORT GENERATION")
message("==============================")

# ------------------------------------------------------------
# ✅ Define root-relative output (pipeline is in scripts/)
# ------------------------------------------------------------
report_dir <- file.path("output", "reports", MODE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# ✅ Create timestamp for versioning
# ------------------------------------------------------------
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# ------------------------------------------------------------
# ✅ Build versioned filename
# ------------------------------------------------------------
report_filename <- paste0("pipeline_report_", MODE, "_", timestamp, ".html")
# rmarkdown::render() intermittently reports the output directory as
# missing when output_file itself contains a directory path, even
# right after dir.create() succeeds -- pass output_dir + a bare
# filename separately instead. report_output (full path) is kept
# for the later file.copy() to pipeline_report_latest.html.
report_output <- file.path(report_dir, report_filename)

message("[REPORT] Rendering pipeline report")

# ------------------------------------------------------------
# ✅ Render report
# ------------------------------------------------------------
tryCatch({
  
  rmarkdown::render(
    input = file.path("scripts", "pipeline_report.Rmd"),  # relative to project root, where the whole script runs from after the top-of-file wd fixup -- was "../reports/pipeline_report.Rmd", which (a) escaped the project root entirely (blocked by the sandbox) and (b) pointed at a nonexistent top-level reports/ dir
    output_file = report_filename,
    output_dir = normalizePath(report_dir),
    params = list(
      db_path = DB_PATH,
      run_time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      mode = MODE
    ),
    envir = new.env(parent = globalenv()),   # ✅ clean environment
    quiet = TRUE
  )
  
  # ----------------------------------------------------------
  # ✅ Also create "latest" symlink / copy
  # ----------------------------------------------------------
  latest_path <- file.path(report_dir, "pipeline_report_latest.html")
  file.copy(report_output, latest_path, overwrite = TRUE)
  
  message("✅ Report generated: ", normalizePath(report_output))
  
}, error = function(e) {
  warning("[REPORT] Failed to render report: ", e$message)
})


# ============================================================
# EXPORT STAGE
# ============================================================

message("\n==============================")
message(" EXPORT STAGE")
message("==============================")

message("\n[EXPORT] Computing data availability across all sources")
# Read-only reporting: which sources have data, over what date range.
# Always runs (not gated by RUN_INGEST) since it just reflects whatever
# is currently in the database. See scripts/analysis/data_availability.R.
source("scripts/analysis/data_availability.R")
build_data_availability_outputs(con)

message("\n[EXPORT] Creating GIS views")
create_gis_views(con)

message("\n[EXPORT] Writing GeoPackage")
export_geopackage(con, mode = MODE)

# ============================================================
# WEBSITE EXPORT
# ============================================================

# 2026-09-06: docs/data/*.csv (read by the Rmd chunks below at render
# time) live inside the same output_dir that rmarkdown::render_site()
# actively cleans on every call -- any file under docs/ with no
# corresponding source in website/ gets deleted as "orphaned" the
# moment render_site() runs, even mid-pipeline. Wrapped in a function
# and called both immediately before AND immediately after
# build_website() below so the charts render against real data *and*
# the CSVs still exist afterward for direct download / the next run.
export_website_data_files <- function(con) {
  # output/ is gitignored (rebuildable scratch space), but docs/ is
  # the published GitHub Pages root -- any figure a website page
  # embeds has to live under docs/, or it 404s on the live site even
  # though it renders fine locally. Copy figures referenced by the
  # website out of output/figures/ into docs/figures/ here.
  dir.create("docs/figures", recursive = TRUE, showWarnings = FALSE)
  if (file.exists("output/figures/data_availability_timeline.png")) {
    file.copy("output/figures/data_availability_timeline.png",
               "docs/figures/data_availability_timeline.png", overwrite = TRUE)
  }
  message("\n[EXPORT] Writing website CSV outputs")
  
  dir.create("docs/data", recursive = TRUE, showWarnings = FALSE)
  
  write.csv(
    dbGetQuery(con, "
      SELECT timestamp, data_source, measurements_inserted
      FROM Ingest_Run_Log
      ORDER BY timestamp
    "),
    "docs/data/ingest_log.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT logger_id, timestamp, temperature
      FROM Temperature_Observations
    "),
    "docs/data/temp_sample.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT 
        w.well_id,
        w.well_name,
        w.ndwr_site_id,
        w.well_role,
        w.latitude,
        w.longitude,
        w.mid_screen_depth,
        w.total_depth,
        w.basin_name
      FROM Wells w
      WHERE w.latitude IS NOT NULL AND w.longitude IS NOT NULL
    "),
    "docs/data/well_sample.csv",
    row.names = FALSE
  )
  
  # 2026-09-05 (session 11): the website leaflet maps previously showed
  # only Wells with a bare "Well: <id>" popup, and had no springs/seeps/
  # other Locations layer at all. This adds real names + site types for
  # both, so data.Rmd/results.Rmd can render meaningful labels.
  write.csv(
    dbGetQuery(con, "
      SELECT
        location_id,
        name,
        external_station_code,
        site_type,
        latitude,
        longitude
      FROM Locations
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    "),
    "docs/data/locations_sample.csv",
    row.names = FALSE
  )
  
  # 2026-09-06: leaflet maps on data.Rmd/results.Rmd previously showed only
  # Wells and springs/seeps Locations -- no way to see where the temperature
  # or conductivity loggers themselves physically sit, including whether any
  # are co-located (e.g. SBRR has both a temperature and a conductivity
  # logger at the same coordinate). These two exports make that visible.
  write.csv(
    dbGetQuery(con, "
      SELECT t.logger_id, t.logger_name, t.status, l.latitude, l.longitude, l.name AS location_name
      FROM Temperature_Loggers t
      JOIN Locations l ON t.location_id = l.location_id
      WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL
    "),
    "docs/data/temp_logger_locations.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT c.logger_id, c.logger_name, c.role, c.status, l.latitude, l.longitude, l.name AS location_name
      FROM Conductivity_Loggers c
      JOIN Locations l ON c.location_id = l.location_id
      WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL
    "),
    "docs/data/cond_logger_locations.csv",
    row.names = FALSE
  )
  
  tables <- dbListTables(con)
  
  table_counts <- lapply(tables, function(t) {
    n <- tryCatch(
      dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", t))$n,
      error = function(e) NA
    )
    
    data.frame(
      table = t,
      n_rows = n
    )
  }) %>%
    bind_rows()
  
  write.csv(
    table_counts,
    "docs/data/table_counts.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT data_source as source,
             SUM(measurements_inserted) as n
      FROM Ingest_Run_Log
      GROUP BY data_source
    "),
    "docs/data/source_summary.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT 
        DATE(timestamp, 'unixepoch') as date,
        COUNT(*) as n
      FROM Temperature_Observations
      GROUP BY date
    "),
    "docs/data/temp_density.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT 
        COUNT(DISTINCT sample_id) as samples,
        COUNT(*) as analyses
      FROM Lab_Analyses
    "),
    "docs/data/chem_summary.csv",
    row.names = FALSE
  )
  
  write.csv(
    dbGetQuery(con, "
      SELECT 
        logger_id,
        COUNT(*) as observations,
        MIN(timestamp) as start_time,
        MAX(timestamp) as end_time
      FROM Temperature_Observations
      GROUP BY logger_id
    "),
    "docs/data/logger_summary.csv",
    row.names = FALSE
  )
  
  dir.create("output/qc", recursive = TRUE, showWarnings = FALSE)
  
  write.csv(
    dbReadTable(con, "QC_Issues"),
    "output/qc/qc_issues_full.csv",
    row.names = FALSE
  )
}

export_website_data_files(con)

# ============================================================
# WEBSITE BUILD STAGE
# ============================================================

message("\n==============================")
message(" WEBSITE BUILD")
message("==============================")

build_website <- function() {
  
  if (!dir.exists("website")) {
    stop("[WEBSITE] website directory not found")
  }
  
  dir.create("docs", showWarnings = FALSE)
  
  # 2026-09-06: docs/literature/ (user-maintained source PDFs, never
  # regenerated from anything) suffered the exact same render_site()
  # cleanup bug already documented above for docs/data/ and docs/figures/
  # -- since it has no counterpart file in website/'s own input tree,
  # render_site() deleted the whole folder mid-render, permanently losing
  # ~15 untracked reference PDFs the one time this ran without this
  # guard. Unlike data/figures, there is no database or output/ copy to
  # regenerate literature PDFs from, so this backs the folder up to a
  # temp directory beforehand and restores it verbatim afterward --
  # deliberately living inside build_website() itself (not just in the
  # RUN_INGEST-gated caller below) so this protection applies no matter
  # how/where this function gets called from.
  lit_dir <- "docs/literature"
  lit_backup <- NULL
  if (dir.exists(lit_dir)) {
    lit_backup_parent <- file.path(tempdir(), paste0("docs_literature_backup_", format(Sys.time(), "%Y%m%d%H%M%S")))
    dir.create(lit_backup_parent, recursive = TRUE, showWarnings = FALSE)
    file.copy(lit_dir, lit_backup_parent, recursive = TRUE)
    lit_backup <- file.path(lit_backup_parent, "literature")
  }
  
  message("[WEBSITE] Rendering site from 'website/' → 'docs/'")
  
  start_time <- Sys.time()
  
  tryCatch({
    
    rmarkdown::render_site("website")
    
    elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)
    
    message("✅ Website built successfully (", elapsed, " sec)")
    
  }, error = function(e) {
    warning("[WEBSITE] Build failed: ", e$message)
  })
  
  # Restore docs/literature/ if render_site() swept it (it always does,
  # since nothing in website/ references it) -- see comment above.
  if (!is.null(lit_backup)) {
    dir.create(lit_dir, recursive = TRUE, showWarnings = FALSE)
    file.copy(list.files(lit_backup, full.names = TRUE), lit_dir, recursive = TRUE, overwrite = TRUE)
  }
}

if (BUILD_WEBSITE) {
  build_website()
  # See export_website_data_files()'s definition above for why this
  # runs a second time here: render_site() deletes docs/data/*.csv
  # as part of its own cleanup, so the CSVs need rewriting once more
  # after the build completes, not just before it.
  export_website_data_files(con)
} else {
  message("[WEBSITE] Skipping build")
}

# ============================================================
# CLEANUP
# ============================================================

dbDisconnect(con)

message("\n==============================")
message(" PIPELINE COMPLETE ✅")
message("==============================\n")
