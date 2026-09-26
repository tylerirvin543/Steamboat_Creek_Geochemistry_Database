# 14_aquifer_classification_schema.R
# ------------------------------------------------------------
# Additive migration: Wells.aquifer_type / aquifer_type_basis.
#
# A well's barometric efficiency (BE) is a real, physically grounded
# signal for whether it taps a confined or unconfined aquifer -- an
# ideal unconfined (water-table) well shows BE near 0 (the atmosphere
# loads the well and the water table equally, canceling out), while a
# confined well shows a real, non-zero BE because the confining layer
# isolates the aquifer from directly equilibrating with atmospheric
# pressure. This project's own White (1968) citation reports a real,
# site-specific range for confined behavior at Steamboat itself
# (BE 0.2-1.18 across different vents on the main terrace) -- used
# here as the classification threshold instead of an arbitrary
# textbook cutoff, so the label is grounded in this exact system's
# own historical data, not a generic rule.
#
# Populated by scripts/analysis/barometric_efficiency.R's
# classify_aquifer_type(), which only fills a well's aquifer_type
# when real BE evidence exists for it (never guessed for the other
# ~200 wells with no water-level/pressure overlap) -- see that
# script's header for the exact thresholds. Re-running is allowed to
# refresh a well's OWN prior barometric-efficiency-derived label
# (aquifer_type_basis already says so), but never overwrites a label
# set by any other method/source.
# ------------------------------------------------------------

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

.wells_cols <- dbGetQuery(con, "PRAGMA table_info(Wells)")$name

if (!"aquifer_type" %in% .wells_cols) {
  dbExecute(con, "
    ALTER TABLE Wells ADD COLUMN aquifer_type TEXT
    CHECK (aquifer_type IN ('confined', 'unconfined', 'semi-confined_leaky', 'unknown'))
    DEFAULT 'unknown'
  ")
  message("[SCHEMA] Added Wells.aquifer_type (migration).")
}

if (!"aquifer_type_basis" %in% .wells_cols) {
  dbExecute(con, "ALTER TABLE Wells ADD COLUMN aquifer_type_basis TEXT")
  message("[SCHEMA] Added Wells.aquifer_type_basis (migration).")
}

message("[SCHEMA] Wells.aquifer_type / aquifer_type_basis ready.")
