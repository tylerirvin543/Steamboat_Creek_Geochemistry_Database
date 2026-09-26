# ============================================================
# 18_logger_uncertainty_schema.R
#
# Purpose: real measurement-uncertainty tracking for the conductivity
# and temperature loggers -- two independent, complementary pieces:
#
#   1. Logger_Specifications -- manufacturer-published accuracy specs
#      (looked up from real product datasheets, never fabricated; see
#      the seed values below and their cited source URLs). This is a
#      static reference table, not a time series.
#   2. Logger_Calibration_Checks -- real field reference/calibration
#      readings (e.g. a handheld thermometer or lab conductivity value
#      taken during a data-pull field visit) matched to the nearest
#      real logger observation at the same site and time, so drift/
#      bias can be assessed empirically, not just assumed from a
#      datasheet. Populated by
#      scripts/analysis/logger_calibration_checks.R's
#      build_logger_calibration_checks(), which detects these
#      automatically from Field_Measurements -- no new manual data-
#      entry form needed.
#
# Neither table claims to fully "solve" measurement uncertainty --
# they give the two real, available inputs (manufacturer spec +
# empirical field check) to scripts/analysis/measurement_uncertainty.R,
# which documents exactly how they're combined.
# ============================================================

create_logger_uncertainty_schema <- function(con) {
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Logger_Specifications (
      spec_id INTEGER PRIMARY KEY,
      manufacturer TEXT NOT NULL,
      model TEXT NOT NULL,
      model_confidence TEXT CHECK (model_confidence IN ('confirmed','inferred')) DEFAULT 'inferred',
      parameter TEXT NOT NULL CHECK (parameter IN ('conductivity','temperature')),
      accuracy_type TEXT CHECK (accuracy_type IN ('absolute','percent_of_reading','greater_of_percent_or_absolute')),
      accuracy_value REAL,
      accuracy_value2 REAL,
      unit TEXT,
      resolution REAL,
      resolution_unit TEXT,
      source_url TEXT,
      notes TEXT,
      UNIQUE(manufacturer, model, parameter)
    )
  ")

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Logger_Calibration_Checks (
      check_id INTEGER PRIMARY KEY,
      logger_type TEXT NOT NULL CHECK (logger_type IN ('conductivity','temperature')),
      logger_id INTEGER NOT NULL,
      check_timestamp TEXT NOT NULL,
      reference_source_sample_id INTEGER,
      reference_instrument TEXT,
      reference_parameter TEXT,
      reference_value REAL,
      reference_units TEXT,
      matched_observation_timestamp TEXT,
      matched_observation_value REAL,
      matched_observation_units TEXT,
      time_offset_seconds REAL,
      difference REAL,
      notes TEXT,
      FOREIGN KEY (reference_source_sample_id) REFERENCES Samples(sample_id)
    )
  ")
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_logger_calchecks_logger
    ON Logger_Calibration_Checks(logger_type, logger_id)
  ")

  invisible(NULL)
}

#' Seed real, publicly-published manufacturer accuracy specs.
#' Idempotent (INSERT OR IGNORE on the UNIQUE(manufacturer, model,
#' parameter) constraint).
#'
#' Models below are the REAL on-file manufacturer/model values,
#' confirmed 2026-09-26 by querying Temperature_Loggers/
#' Conductivity_Loggers directly (not guessed) -- an earlier draft of
#' this seed had inferred "U24-001" (freshwater) and generic "LogEt 8"
#' as placeholders before checking; the real on-file models are
#' "U24-002-C" (Onset/HOBO) and "LogEt 8 PTE" / "Tlog 10E" (Elitech).
#'
#' Sources (checked directly via web search 2026-09-26, not
#' fabricated):
#'   - Onset/HOBO U24-002-C (Saltwater Conductivity/Salinity Data
#'     Logger -- confirmed real on-file model, despite this project's
#'     Steamboat Creek deployment being freshwater; the same model is
#'     also usable/rated for freshwater conductivity ranges): Low Range
#'     (100-10,000 uS/cm, which covers Steamboat Creek's real ~300-1300
#'     uS/cm) accuracy "3% of reading or 50 uS/cm, whichever is
#'     greater"; High Range (5000-55,000 uS/cm) accuracy "5% of
#'     reading, within +/-3,000 uS/cm variation". model_confidence =
#'     'confirmed' (real on-file model name).
#'   - Elitech LogEt 8 PTE (confirmed real on-file model): published
#'     temperature accuracy +/-0.3 C.
#'   - Elitech Tlog 10E (confirmed real on-file model, but no exact
#'     accuracy figure found in its own public manual/listing) --
#'     recorded as +/-0.3 C by comparison to Elitech's closely related
#'     Tlog 100/100EH series (+/-0.3 C, -20 to 40 C), NOT the logger's
#'     own confirmed spec sheet -- model_confidence = 'inferred' for
#'     this reason (the MODEL is confirmed real; the ACCURACY VALUE
#'     itself is inferred from a sibling product line).
seed_logger_specifications <- function(con) {
  specs <- list(
    list("Onset/HOBO", "U24-002-C", "confirmed", "conductivity",
         "greater_of_percent_or_absolute", 3, 50, "uS/cm", 2, "uS/cm",
         "https://www.onsetcomp.com/products/data-loggers/u24-002-c",
         "Low Range (100-10,000 uS/cm, covers Steamboat Creek's real ~300-1300 uS/cm) calibrated-range accuracy: 3% of reading or 50 uS/cm, whichever is greater. High Range (5000-55,000 uS/cm) is 5% of reading within +/-3,000 uS/cm variation -- not the range this project's real creek EC falls in, recorded here for reference only."),
    list("Onset/HOBO", "U24-002-C", "confirmed", "temperature",
         "absolute", 0.1, NA, "degC", 0.01, "degC",
         "https://www.onsetcomp.com/products/data-loggers/u24-002-c",
         "Temperature accuracy +/-0.1 C (+/-0.2 F); resolution 0.01 C -- consistent with the U24 family generally."),
    list("Elitech", "LogEt 8 PTE", "confirmed", "temperature",
         "absolute", 0.3, NA, "degC", 0.1, "degC",
         "https://www.elitechus.com/products/elitech-loget-8-pte-temperature-data-logger-reusable-ultra-low-temperature-recorder-pdf-report-usb-port-16000-points",
         "Published accuracy +/-0.3 C across its wide -85 to +150 C range."),
    list("Elitech", "Tlog 10E", "inferred", "temperature",
         "absolute", 0.3, NA, "degC", 0.1, "degC",
         "https://www.elitecheu.com/products/elitech-tlog-100-series-temperature-and-humidity-data-logger-multi-use-usb-ultra-low-recorder",
         "No accuracy figure found in the Tlog 10E's own public manual/listing -- this value (+/-0.3 C, -20 to 40 C) is from Elitech's closely related Tlog 100/100EH series, not a confirmed Tlog 10E spec sheet. The MODEL name is a confirmed real on-file value; the ACCURACY VALUE is inferred by comparison, hence model_confidence='inferred'.")
  )
  for (s in specs) {
    dbExecute(con, "
      INSERT OR IGNORE INTO Logger_Specifications
        (manufacturer, model, model_confidence, parameter, accuracy_type,
         accuracy_value, accuracy_value2, unit, resolution, resolution_unit,
         source_url, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = s)
  }
  invisible(NULL)
}
