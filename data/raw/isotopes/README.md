# `data/raw/isotopes/` — Stable Isotope Analyses (δ18O/δD)

## What this is

`Isotope_Data_Steamboat_05_26.xlsx` — laboratory stable-isotope
(δ18O, δD) results for field-collected spring/well/creek samples,
supporting the isotope-mixing analysis referenced in `AGENTS.md`
("isotope figure improvement is an immediate priority") and
`Figures/d18O_dD.jpeg`.

## File format

Wide-format Excel export, one row per sample, linked to
`Sampling_Events`/`Samples` via the sample's `external_sample_id`
(the same identifier scheme field/lab chemistry uses).

## Ingestion behavior

`scripts/ingest/ingest_isotopes.R` (`RUN_INGEST$isotope`) parses this
file and inserts into `Isotope_Analyses`, linked to the same
`Samples` row as any co-located lab chemistry for that sample —
deliberately the *same* sample identity, not a parallel one, so a
δ18O/δD value and its Cl/major-ion chemistry are always a one-line
join apart (`vw_isotopes_gis` and related views rely on this).
Idempotent on `(sample_id, isotope)`.

## Known limitations

- Isotope coverage currently exists for only a small number of real
  field samples (the same handful of FIELD thermal samples chemistry
  is available for) — not yet a dense time series.
