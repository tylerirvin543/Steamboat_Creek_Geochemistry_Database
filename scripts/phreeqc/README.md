# scripts/phreeqc/

PHREEQC geochemical-modeling integration. All scripts here read real
chemistry from `Lab_Analyses`/`Field_Measurements` (via
`get_phreeqc_eligible()`), shell out to a real PHREEQC executable
(`system2()`), and parse its text output back into the database. See
`notebooks/06_phreeqc_geochemical_modeling.qmd` for the full narrative
reference (architecture, real speciation/SI results, geothermometer
divergence discussion) and `notebooks/08_statistical_synthesis.qmd` for
the equations these implement paired with formal statistics on the
output.

| Script | What it does |
|---|---|
| `utils_phreeqc.R` | Shared utilities: `SOLUTION`-block generation from a sample's real chemistry (`format_solution_block()`, including the boron-exclusion guard), the database registry (LLNL/SIT/Pitzer/phreeqc.dat/WATEQ4F with temperature/TDS-based auto-recommendation), `system2()` execution, `SELECTED_OUTPUT` parsing, fluid-type classification, activity-based Na/K geothermometers, and automated interpretation text. Everything else in this folder sources from here. |
| `08_build_phreeqc_tables.R` | `build_phreeqc_solutions(con)` -- builds `PHREEQC_Solutions` (one row per sample with the chemistry needed for a `SOLUTION` block, real charge balance computed via `lab_analyte_map.R`) and `get_phreeqc_eligible(con)` (which samples have enough data to actually run, and why the rest don't). |
| `09_run_phreeqc.R` | `run_phreeqc_pipeline()` -- the main speciation/SI batch run, with per-sample fallback-database retry and `PHREEQC_Run_Failures` logging; `run_phreeqc_multi()`; `view_phreeqc_results()`; `run_phreeqc_temp_sweep()` (25-300°C multicomponent geothermometry). |
| `10_run_phreeqc_mixing.R` | Two-end-member conservative Cl mixing (pure-R fraction calculation + PHREEQC `MIX`-block predicted-vs-observed comparison). `demo_mixing_model()` is the synthetic self-test; real runs are driven by `data/raw/phreeqc/mixing_config.csv`. |
| `11_run_phreeqc_inverse.R` | PHREEQC `INVERSE_MODELING` (mixing + mineral mass-transfer). `demo_inverse_model()` self-test; real runs via `data/raw/phreeqc/inverse_config.csv`. |
| `12_run_phreeqc_gas_phase.R` | CO2/H2S `GAS_PHASE` degassing equilibria. `demo_gas_phase()` self-test; real runs via `data/raw/phreeqc/gas_phase_config.csv`. |
| `13_gas_geothermometry.R` | D'Amore & Panichi (1980) multicomponent CO2-H2-H2S-CH4 gas geothermometer, cross-validated against real published Mariner & Janik (1995) values. Not wired into `run_pipeline.R` -- a standalone capability, called directly. |
| `14_gas_mixing.R` | Forward/inverse two-end-member gas mixing (conservative N2/Ar ratio). Not wired into `run_pipeline.R`. |
| `run_phreeqc_analysis.R` | Single entry point: `run_phreeqc_analysis_pipeline(con, mode = ...)`; `demo_phreeqc_analysis()` runs all three synthetic self-tests; `should_rerun_phreeqc()`/`record_phreeqc_run_state()` back the auto-rerun-only-if-something-changed logic `run_pipeline.R` uses; `run_phreeqc_mixing_from_config()`/`_inverse_from_config()`/`_gas_phase_from_config()` are the CSV-config-driven runners for the three optional modes above. |
