# `data/raw/phreeqc/` — PHREEQC Model Configuration (User-Editable)

## What this is

Three plain CSVs that let a user run a real (not synthetic) PHREEQC
mixing, inverse, or gas-phase model **without editing R code** — add
or toggle a row, re-run the pipeline. This is deliberately the *only*
way these three model modes ever run against real data automatically
— they never guess which real samples are meaningful end-members, so
a human fills in real `sample_id`s here.

## Files

- **`mixing_config.csv`** — columns for two-end-member conservative
  Cl-mixing runs (thermal `sample_id`, meteoric `sample_id`, run
  label, `enabled`). Auto-created header-only on first pipeline run if
  missing; a real row currently exists (thermal = sample 816/SBF_0001,
  meteoric = sample 829/Boyd Domestic Well) — see
  `notebooks/07_historical_context_sorey1992.qmd` for what that real
  run found.
- **`inverse_config.csv`** — target/end-member `sample_id`s + candidate
  mineral phases for `INVERSE_MODELING` mass-transfer runs.
- **`gas_phase_config.csv`** — CO2/H2S `GAS_PHASE` degassing-equilibrium
  run configuration.

## Running

```r
source("scripts/phreeqc/run_phreeqc_analysis.R")
run_phreeqc_mixing_from_config(con)      # or _inverse_from_config() / _gas_phase_from_config()
```

Each function reads its CSV and runs every row with `enabled = TRUE`.
Wired into `run_pipeline.R` as `RUN_ANALYSIS$phreeqc_mixing` /
`_inverse` / `_gas_phase` (each default `FALSE` — opt-in only, since
these call an external PHREEQC executable per row).

## Known limitations

- Real mixing/inverse configuration currently uses a
  typical/representative end-member pair, not a real-time-paired
  validation (the same posture Sorey & Colvard's own 820/6 mg/L Cl
  split used) — see the notebook for the exact caveat.
- `demo_mixing_model()`/`demo_inverse_model()`/`demo_gas_phase()`
  (in `scripts/phreeqc/10-12_*.R`) self-test against synthetic data
  and don't read these CSVs at all — don't confuse a synthetic
  self-test result with a real config-driven run.
