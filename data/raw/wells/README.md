# `data/raw/wells/` — Hand-Maintained Well-Network & Coordinate CSVs

## What this is

Small, human-curated CSVs that encode real well-identity, coordinate,
and production→port→injection network decisions made across many
sessions — this is the project's single most important "provenance
trail" folder, since a well's coordinate or role is often the product
of comparing multiple disagreeing sources (NBMG, NDWR, NDOM, ArcGIS
digitization) and picking the best-supported one, not a simple
one-source lookup.

## Files

- **`dhakal_well_network.csv`** — well_name, well_role
  (production/injection/monitor/domestic/unknown), port_name,
  valid_from/valid_to, source, notes. Transcribed from Dhakal et al.
  (2025) Figure 5 (the 2024 production→port→injection flow diagram).
  Read by `scripts/ingest/register_well_network.R`.
- **`dhakal_well_coordinates.csv`**, **`dhakal_wells_arcgis.csv`** —
  well_name, latitude, longitude, `coordinate_source`,
  `coordinate_uncertainty_m`, notes. Two independent coordinate
  sources (NBMG statewide database; ArcGIS satellite-overlay
  digitization) for Dhakal-diagram wells, applied in that order by
  `scripts/ingest/register_well_coordinates.R` — NBMG's higher-
  confidence coordinates are always tried first and never overwritten
  by the ArcGIS pass.
- **`sorey1992_nbmg_resolved_wells.csv`** — wells/springs from Sorey &
  Colvard (1992) resolved to real NBMG-sourced identities/coordinates
  (`83A-6`, `Cox I-1`, `GS-5`, the Table 8 stratigraphic test wells,
  etc.), read by `ingest_historical_sorey1992.R`.
- **`sorey1992_perforation_data.csv`** — real 1990-era casing/screened-
  interval data for CPI/SB GEO wells, from Sorey & Colvard's Tables
  6/7, filling previously-100%-empty `Wells.top_perforation`/
  `bottom_perforation` fields (fill-only-if-NULL, never overwrites).
- **`well_aliases.csv`** — well_name, alias, alias_type
  (`dhakal_diagram`/`uic_permit`/`historical_gs_number`/`ndwr_permit`/
  `other`), source, notes. Every script that resolves a well by name
  (`register_well_network.R`, `register_well_coordinates.R`,
  `ingest_ndom_wells.R`) checks this table before deciding a name is
  genuinely new — this is what lets e.g. `IW-5`/`PW2-1`/`PW2-x` (no
  space) resolve to their canonical `Wells` row instead of creating a
  duplicate.

## Editing these files

Add a well/port assignment, coordinate, or alias by adding a row —
never delete another editor's row without checking `notes` first (a
"tentative"/"flagged" row usually means a specific, documented
uncertainty, not an oversight). Re-run
`register_well_network(con)`/`register_well_coordinates(con)` after
editing; both are idempotent (a manually-corrected database value is
never clobbered by a re-run).

## Known limitations

- Not every well in `dhakal_well_network.csv` has a coordinate yet
  (role/port assignment and coordinate resolution are tracked as
  separate, independently-sourced facts) — check `Wells.latitude IS
  NULL` for the current gap list.
