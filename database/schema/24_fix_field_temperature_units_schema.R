# ============================================================
# 24_fix_field_temperature_units_schema.R
#
# Purpose:
# One-time, idempotent retroactive fix for a real, substantial bug found
# 2026-10-25: this project's Fluke field thermometer reports in
# Fahrenheit, correctly labeled "F"/"deg F" in Field_Measurements.units
# -- but nothing downstream (build_phreeqc_solutions() in
# scripts/phreeqc/08_build_phreeqc_tables.R, and every other direct
# consumer of Field_Measurements.value) ever checked the units column
# before treating the raw number as Celsius. This means every PHREEQC
# SOLUTION block, saturation index, mixing/reaction-path titration, and
# the gas-informed parent-fluid steam-loss calculation built from a
# "F"-unit Field_Measurements row has been using a temperature roughly
# 1.8x too high.
#
# Confirmed, not guessed: SBRR's own real continuous creek-temperature
# logger reads 10.8-27.5 C seasonally; its "F"-labeled field reading of
# 59.36 converts to 15.2 C (matches), not 59.36 C (a physically
# implausible open-creek temperature). Five of the other six affected
# samples cross-check the same way against their own co-located
# temperature loggers.
#
# scripts/ingest/ingest_field.R is fixed at the real point of entry
# (converts F/deg F to C before insert, going forward) -- this file
# retroactively corrects the 68 + 18 already-ingested rows (two
# different raw-unit spellings, "F" from the original Fluke-thermometer
# ingest and "deg F" from the later U230-compiled-OCR batch, both the
# same underlying bug). Naturally idempotent: after the first run,
# every affected row's units becomes "deg C", which no longer matches
# this migration's own WHERE clause.
#
# Sourced after 01-23.
# ============================================================

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

n_before <- dbGetQuery(con, "
  SELECT COUNT(*) n FROM Field_Measurements
  WHERE parameter = 'temperature' AND lower(trim(units)) IN ('f', 'deg f', 'degf')
")$n[1]

if (n_before > 0) {
  dbExecute(con, "
    UPDATE Field_Measurements
    SET value = (value - 32) * 5.0 / 9.0,
        units = 'deg C'
    WHERE parameter = 'temperature' AND lower(trim(units)) IN ('f', 'deg f', 'degf')
  ")
  message("[24_fix_field_temperature_units] Converted ", n_before,
          " Field_Measurements temperature row(s) from Fahrenheit to Celsius.")
} else {
  message("[24_fix_field_temperature_units] No Fahrenheit-labeled temperature rows found -- already corrected or none exist.")
}
