# scripts/leapfrog/

Exports this project's well data into Leapfrog Geo's plain-CSV input
format (collar / survey / interval tables), for building a 3D geologic
model of the Steamboat field. Entirely optional and read-only against
the database (no ingestion, no schema writes) -- see README.md's
"Planned: Leapfrog 3D geologic model export" section for the full
design rationale and open decisions.

| Script | What it does |
|---|---|
| `export_leapfrog.R` | `export_leapfrog(con, out_dir = ...)` -- writes `collar.csv` (UTM Zone 11N / EPSG:26911, matching this project's other UTM-based exports), `survey.csv` (a real deviation survey from `Well_Deviation_Surveys` when one exists, e.g. well 83C-6ST1; an assumed-vertical two-point trace otherwise -- flagged per-well, never silently assumed), `interval.csv` (completion/perforation interval, explicitly labeled as *not* lithology), and `lithology.csv` (only `well_id`-confirmed `Well_Lithology` rows -- candidate/pending rows are excluded, never guessed into the export). Wired into `run_pipeline.R` as `RUN_ANALYSIS$leapfrog_export` (default `FALSE`). |

Real fault traces and alteration zones are a separate, not-yet-built
extension -- see `database/schema/11_fault_traces_schema.R` and
`scripts/ingest/ingest_fault_traces.R` (structure-only, waiting on a
digitized shapefile) and `docs/action_items_for_user.md` for the
current status.
