# ============================================================
# 23_reaction_path_schema.R
#
# Purpose:
# A real, forward PHREEQC REACTION-path (titration) model, built as the
# complement to the project's existing PHREEQC_Inverse_* tables
# (08_phreeqc_schema.R). Every real inverse-modeling attempt against
# SBW_0001 (the real across-creek Lower Sinter Terrace well showing a
# clear deviation from the fissure+SBRR conservative-mixing curve) finds
# zero feasible solutions within PHREEQC's automatic mass-balance search
# -- see ROADMAP.md Section 1/2 (2026-10-25). Rather than keep tuning the
# inverse solver, this schema stores a FORWARD titration: mix the two
# known real end-members at a known fraction, then explicitly step
# calcite/dolomite mass transfer (both dissolution and precipitation
# directions) and see what the resulting chemistry trajectory looks
# like -- a better-posed question than asking the solver to search
# blindly, and directly comparable against a real target sample's
# observed chemistry.
#
# Two tables, long-format, mirroring the existing
# PHREEQC_Mixing_Runs/PHREEQC_Mixing_Results pattern:
#   - PHREEQC_Reaction_Path_Runs: one row per titration run (end-members,
#     mixing fraction, candidate phases, step range, database, target).
#   - PHREEQC_Reaction_Path_Steps: one row per (run, step, parameter) --
#     reaction_progress_mol is the net cumulative moles of the combined
#     phase mixture added (negative = net precipitation/removal), so a
#     run with multiple steps naturally reads as a titration curve.
#
# Sourced after 01-22.
# ============================================================

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Reaction_Path_Runs (
  run_id INTEGER PRIMARY KEY,
  run_date TEXT NOT NULL,
  target_sample_id INTEGER,
  thermal_sample_id INTEGER NOT NULL,
  meteoric_sample_id INTEGER NOT NULL,
  mixing_fraction_thermal REAL NOT NULL,
  mixing_fraction_source TEXT,
  phases TEXT NOT NULL,
  step_min_mol REAL NOT NULL,
  step_max_mol REAL NOT NULL,
  n_steps INTEGER NOT NULL,
  db_file TEXT,
  convergence_status TEXT,
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Reaction_Path_Steps (
  run_id INTEGER NOT NULL REFERENCES PHREEQC_Reaction_Path_Runs(run_id),
  step_index INTEGER NOT NULL,
  reaction_progress_mol REAL NOT NULL,
  parameter TEXT NOT NULL,
  value REAL,
  PRIMARY KEY (run_id, step_index, parameter)
);
")
