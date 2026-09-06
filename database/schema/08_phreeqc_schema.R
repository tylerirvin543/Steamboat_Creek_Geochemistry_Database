#08_phreeqc_schema
#
# PHREEQC geochemical modeling tables: derived SOLUTION input rows,
# speciation/saturation-index results, temperature-sweep geothermometry,
# convergence-failure logging, mixing models, inverse modeling, and gas
# phase equilibria. Additive/idempotent -- CREATE TABLE IF NOT EXISTS
# throughout, safe to re-source on an existing database. Sourced after
# 01-07 both at initial connection and in run_pipeline.R's DEMO reset
# block (see run_pipeline.R).
#
# Column choices for PHREEQC_Solutions mirror database/schema/
# lab_analyte_map.R's clean `analyte` values (Ca, Mg, Na, K, Cl, SO4,
# NO3, F, Br, Alkalinity, Si, B, Li, Sr, Fe, Mn, As) rather than raw
# PHREEQC species names -- Alkalinity (not HCO3) and Si (not SiO2) are
# deliberate: that's what this project's Lab_Analyses.analyte actually
# stores (see scripts/ingest/ingest_lab.R), and
# scripts/phreeqc/utils_phreeqc.R's format_solution_block() translates
# to the right PHREEQC directive (Alkalinity -> "as HCO3", Si -> "as SiO2").

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R or an interactive session with `con` already connected.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# ------------------------------------------------------------
# Chemistry_Parameters -- enabled (was a disabled stub in
# 01_define_schema.R). Populated from lab_analyte_map.R below so
# PHREEQC element names / charges / molar masses are queryable as a
# live table, not just an R object other scripts have to re-source.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Chemistry_Parameters (
  parameter TEXT PRIMARY KEY,
  phreeqc_name TEXT,
  charge INTEGER,
  molar_mass REAL,
  role TEXT
);
")

if (dbGetQuery(con, "SELECT COUNT(*) n FROM Chemistry_Parameters")$n == 0) {
  source("database/schema/lab_analyte_map.R")
  cp <- data.frame(
    parameter = lab_analyte_map$analyte,
    phreeqc_name = lab_analyte_map$phreeqc_name,
    charge = lab_analyte_map$charge,
    molar_mass = lab_analyte_map$molar_mass,
    role = lab_analyte_map$category,
    stringsAsFactors = FALSE
  )
  cp <- cp[!duplicated(cp$parameter), ]
  dbAppendTable(con, "Chemistry_Parameters", cp)
  message("[SCHEMA] Chemistry_Parameters populated from lab_analyte_map.R (", nrow(cp), " rows)")
}

# ------------------------------------------------------------
# PHREEQC_Solutions -- one row per sample, the direct input to
# scripts/phreeqc/utils_phreeqc.R's format_solution_block(). Built by
# scripts/phreeqc/08_build_phreeqc_tables.R's build_phreeqc_solutions(con).
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Solutions (
  solution_id INTEGER PRIMARY KEY,
  sample_id INTEGER UNIQUE,
  temperature REAL,
  pH REAL,
  Ca REAL, Mg REAL, Na REAL, K REAL,
  Cl REAL, SO4 REAL, Alkalinity REAL, Si REAL,
  NO3 REAL, F REAL, Br REAL, B REAL, Li REAL, Sr REAL,
  Fe REAL, Mn REAL, [As] REAL,
  d18O REAL, dD REAL,
  units TEXT DEFAULT 'mg/L',
  charge_balance REAL,
  completeness_flag TEXT,
  built_at TEXT,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")

# ------------------------------------------------------------
# PHREEQC_Results -- long-format speciation/SI output, one row per
# sample x parameter x thermodynamic database. Mirrors the IGNIS
# project's phreeqc_results table.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Results (
  result_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  run_date TEXT,
  parameter TEXT,
  value REAL,
  db_file TEXT,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_phreeqc_results_sample ON PHREEQC_Results(sample_id, db_file);")

# ------------------------------------------------------------
# PHREEQC_Temp_Sweep -- REACTION_TEMPERATURE sweep output for
# multicomponent mineral-equilibration geothermometry (Reed & Spycher
# 1984 approach).
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Temp_Sweep (
  sweep_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  temperature_C REAL,
  parameter TEXT,
  value REAL,
  db_file TEXT,
  run_date TEXT,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_phreeqc_sweep_sample ON PHREEQC_Temp_Sweep(sample_id, db_file);")

# ------------------------------------------------------------
# PHREEQC_Run_Failures -- samples that failed to converge with every
# thermodynamic database tried, so they're visible in QC instead of
# silently vanishing from downstream SI results/plots.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Run_Failures (
  failure_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  location_name TEXT,
  site_type TEXT,
  reason TEXT,
  logged_at TEXT,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")
dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS idx_phreeqc_failures_sample ON PHREEQC_Run_Failures(sample_id);")

# ------------------------------------------------------------
# Mixing models (Phase 3): two-end-member conservative-tracer fractions
# (pure R) plus PHREEQC MIX-block predicted-vs-observed comparisons.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Mixing_Runs (
  mixing_run_id INTEGER PRIMARY KEY,
  run_date TEXT,
  thermal_end_member_id INTEGER,
  meteoric_end_member_id INTEGER,
  tracer TEXT,
  notes TEXT,

  FOREIGN KEY (thermal_end_member_id) REFERENCES Samples(sample_id),
  FOREIGN KEY (meteoric_end_member_id) REFERENCES Samples(sample_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Mixing_Fractions (
  mixing_run_id INTEGER NOT NULL,
  sample_id INTEGER NOT NULL,
  tracer TEXT,
  mixing_fraction_thermal REAL,
  observed_value REAL,
  predicted_value_if_conservative REAL,

  FOREIGN KEY (mixing_run_id) REFERENCES PHREEQC_Mixing_Runs(mixing_run_id),
  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id),
  UNIQUE(mixing_run_id, sample_id, tracer)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Mixing_Results (
  mixing_run_id INTEGER NOT NULL,
  sample_id INTEGER,
  mixing_fraction_thermal REAL,
  parameter TEXT,
  predicted_value REAL,
  observed_value REAL,
  db_file TEXT,
  run_date TEXT,

  FOREIGN KEY (mixing_run_id) REFERENCES PHREEQC_Mixing_Runs(mixing_run_id),
  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")

# ------------------------------------------------------------
# Inverse modeling (Phase 4): INVERSE_MODELING mixing + mass-transfer
# solutions. A single inverse-model run can return several equally
# valid mole-transfer solutions -- solution_number distinguishes them.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Inverse_Models (
  inverse_model_id INTEGER PRIMARY KEY,
  run_date TEXT,
  target_sample_id INTEGER,
  candidate_phases TEXT,
  uncertainty_pct REAL,
  db_file TEXT,
  notes TEXT,

  FOREIGN KEY (target_sample_id) REFERENCES Samples(sample_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Inverse_End_Members (
  inverse_model_id INTEGER NOT NULL,
  end_member_sample_id INTEGER NOT NULL,

  FOREIGN KEY (inverse_model_id) REFERENCES PHREEQC_Inverse_Models(inverse_model_id),
  FOREIGN KEY (end_member_sample_id) REFERENCES Samples(sample_id),
  UNIQUE(inverse_model_id, end_member_sample_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Inverse_Results (
  inverse_model_id INTEGER NOT NULL,
  solution_number INTEGER,
  component TEXT,
  component_type TEXT CHECK (component_type IN ('end_member_mixing_fraction', 'phase_mole_transfer')),
  value REAL,

  FOREIGN KEY (inverse_model_id) REFERENCES PHREEQC_Inverse_Models(inverse_model_id)
);
")

# ------------------------------------------------------------
# Gas phase (Phase 5): GAS_PHASE equilibria (open/fixed-pressure or
# fixed-volume), relevant to CO2/H2S degassing on ascent/boiling.
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Gas_Phase_Runs (
  gas_run_id INTEGER PRIMARY KEY,
  run_date TEXT,
  gas_components TEXT,
  gas_phase_type TEXT CHECK (gas_phase_type IN ('fixed_pressure', 'fixed_volume')),
  total_pressure_atm REAL,
  volume_liters REAL,
  db_file TEXT,
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Gas_Phase_Results (
  gas_run_id INTEGER NOT NULL,
  sample_id INTEGER NOT NULL,
  gas_component TEXT,
  moles_gas REAL,
  partial_pressure_atm REAL,
  resulting_pH REAL,
  db_file TEXT,
  run_date TEXT,

  FOREIGN KEY (gas_run_id) REFERENCES PHREEQC_Gas_Phase_Runs(gas_run_id),
  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")

message("[SCHEMA] PHREEQC schema (08_phreeqc_schema.R) ready.")
