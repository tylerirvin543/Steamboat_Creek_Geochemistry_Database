# `data/raw/historical/` — Digitized Historical-Literature Chemistry

## What this is

Chemistry, gas, and site-identity data manually transcribed from
historical USGS/academic literature (not from any live agency
download), extending this project's own field/NDEP record decades
into the past.

## Files

- **`sorey1992_table1_chemistry.csv`** — Table 1 of Sorey & Colvard
  (1992, USGS Administrative Report for the BLM), 9 features,
  1950-1991 chemistry (Cl, HCO3→`Alkalinity`, SiO2 under a distinct
  `SiO2` code — see the file's own header comment for why it's kept
  separate from this project's `Si` element code — TWH/TDH temperature,
  Na-K-Ca geothermometer estimate). Transcribed directly from
  `docs/literature/Sorey_StmbtSprgsHSActivity_1992.pdf` via
  `pdftotext -layout` (the report has a real, if OCR-noisy, text
  layer). Ingested by `scripts/ingest/ingest_historical_sorey1992.R`.
- **`historical_data.xlsx`** — an earlier/independent historical
  compilation (predates the Sorey & Colvard transcription above);
  check its own sheet headers before assuming overlap or duplication
  with the Sorey CSV.
- **`mariner_janik_1995_table1_chemistry.csv`** — Table 1 of Mariner &
  Janik (1995), 75 samples (1991-1994), read from rendered page images
  (not `pdftotext`, which scrambles this particular table's layout).
  Ingested by `scripts/ingest/ingest_mariner_janik_1995.R`. Includes a
  `match_type` column recording how confidently each row's site name
  was resolved to an existing `Wells`/`Locations` row (several are
  tentative or unmatched — check this column before trusting a
  site-identity join at face value).

## Ingestion behavior

Both historical-chemistry ingest scripts create real, coordinate-less
**provisional** `Wells`/`Locations` rows for any site name that can't
be confidently resolved to an existing entity, rather than dropping
that chemistry — consistent with this project's standing "never guess
an identity, but don't strand real data either" rule. See
`notebooks/07_historical_context_sorey1992.qmd` for the full
well/site cross-reference table and every resolved-vs-unresolved
identity decision.

## Known limitations

- Several site names in both sources remain genuinely unresolved
  (e.g. Sorey & Colvard's stratigraphic test wells, several Mariner &
  Janik domestic/background comparison sites) — flagged, not guessed.
- Appendix G of Sorey & Colvard (per-station 1988-89 stream discharge/
  chloride-flux data) was deliberately **not** transcribed — the raw
  table is visibly OCR-misaligned (values shifted relative to
  station-name rows); the aggregate discharge numbers already used
  elsewhere in this project are the report's own synthesized output,
  not derived from re-parsing this table.
