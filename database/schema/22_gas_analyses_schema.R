# ============================================================
# 22_gas_analyses_schema.R
#
# Purpose:
# First real raw field/lab gas-chemistry table in this project. Stores
# free-gas (fumarole/fissure) compositions, carbon isotopes, and noble-
# gas ratios from the April 2026 UCSB (T. Fischer, K. Mtili, P.
# Ruprecht) Lower Sinter Terrace fissure gas sampling campaign
# (data/raw/gas(new)/..., see ingest_fischer_gas_data.R). This is
# distinct from the pre-existing PHREEQC_Gas_Phase_* tables
# (08_phreeqc_schema.R), which store PHREEQC-*modeled* GAS_PHASE
# equilibria output, not real field/lab measurements.
#
# One row per real sample (wide, not long) -- mirrors the source
# spreadsheet's own natural shape (one row per Giggenbach-bottle
# sample, one column per analyte/ratio) rather than forcing it into
# this project's long-format Lab_Analyses table, since gas analytes
# (mol% of a closed 100% system) and noble-gas isotope ratios aren't a
# natural fit for Lab_Analyses's per-analyte-row/mg-L convention.
#
# Sourced after 01-21.
# ============================================================

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Gas_Analyses (
  gas_analysis_id INTEGER PRIMARY KEY,
  sample_label TEXT NOT NULL UNIQUE,
  location_id INTEGER REFERENCES Locations(location_id),
  collection_date TEXT,
  field_temp_c REAL,

  -- Normalized dry gas composition, mole percent (sums to ~100).
  co2_mol_pct REAL,
  he_mol_pct REAL,
  h2_mol_pct REAL,
  ar_mol_pct REAL,
  o2_mol_pct REAL,
  n2_mol_pct REAL,
  ch4_mol_pct REAL,
  co_mol_pct REAL,
  h2s_mol_pct REAL,
  total_mol_pct REAL,

  -- Carbon isotopes (Picarro, Fischer Volatiles Lab, UCSB).
  d13c_permil REAL,
  d13c_error_permil REAL,

  -- Noble-gas ratios (P. Barry lab, WHOI).
  he3_he4_r_ra REAL,
  he4_ne20 REAL,
  ne20_ne22 REAL,
  ne21_ne22 REAL,
  ar40_ar36 REAL,
  x_value REAL,
  rc_ra REAL,

  lab TEXT DEFAULT 'Fischer Volatiles Lab (UCSB, gas GC/QMS + C-isotope Picarro); P. Barry noble-gas lab (WHOI)',
  collected_by TEXT DEFAULT 'T. Fischer, K. Mtili, with P. Ruprecht',
  data_quality_flag TEXT CHECK (data_quality_flag IN ('ok', 'air_contaminated_suspect')) DEFAULT 'ok',
  source TEXT DEFAULT 'Fischer/Ruprecht UCSB Lower Sinter Terrace gas sampling, April 2026',
  notes TEXT
);
")
