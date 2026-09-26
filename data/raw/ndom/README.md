# `data/raw/ndom/` — Nevada Division of Minerals Well-Permit Records

## What this is

`Ormat Steamboat Wells.xlsx` — the official Nevada Division of
Minerals (NDOM) state permit record for every Ormat Steamboat well (49
rows): Permit #, API #, BLM Lease Number, Well Type (Obs/Ind-Prod/
Ind-Inj/TG), Status (In Use/Shut-In), Spud/Completion dates, Total
Depth, UTM Easting/Northing (NAD83 UTM Zone 11N / EPSG:26911), and
Elevation (feet). Received directly from an NDOM contact (Keith
Hayes), not a public bulk download — if this file is ever missing
after a fresh clone, it needs to be requested from NDOM again, not
re-derived from another source.

## Ingestion behavior

`scripts/ingest/ingest_ndom_wells.R` (`ingest_ndom_wells(con)`, wired
into `run_pipeline.R` as `RUN_INGEST$ndom_wells`) converts each row's
UTM to WGS84 lat/lon, resolves the well name to an existing `Wells`
row (exact match, a short table of confirmed spelling variants, or an
existing `Well_Aliases` row), and fills coordinate/elevation/
total_depth/well_role/identifier columns **only when the existing
field is currently NULL** — never overwrites. Elevation is converted
feet→meters at ingest time (`* 0.3048`), consistent with every other
elevation source in this project. Idempotent on `NDOM_Well_Records.permit`.

## Known limitations

- **6 real coordinate discrepancies** between NDOM's permit-of-record
  coordinate and this project's existing (NBMG/ArcGIS-sourced)
  coordinate for the same well are logged, not silently resolved, to
  `data/derived/ndom_coordinate_discrepancies.csv` — worth a manual
  review, since NDOM is the official record and these gaps
  (166-573 m) are large relative to this project's usual ~50-75 m
  uncertainty.
- Two NDOM rows (Well Type `TG`, permits 0273/0275) had no UTM
  coordinate at all in the source file and were renamed `TG-1`/`TG-3`
  before matching, per an explicit user decision (a literal well_name
  of `"1"`/`"3"` was judged too generic/collision-prone).
