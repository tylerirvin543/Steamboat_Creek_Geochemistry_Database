# scripts/templates/

Diagram/template generators -- none of these touch the database; they
produce standalone reference images or a blank data-entry template.

| Script | What it does |
|---|---|
| `create_flux_template.R` | Generates the blank stream-discharge/transect Excel template (`data/raw/discharge/stream_discharge.xlsx`'s header structure) for field data entry. |
| `database_diagram.R` | A standalone poster-style database architecture diagram (`DiagrammeR`/`DiagrammeRsvg`/`rsvg`), renders to `steamboat_poster_workflow.png`. Not wired into `run_pipeline.R` -- run manually when the schema changes enough to warrant a new diagram. |
| `temp_diagram.R` | A smaller temperature/logger-network-focused diagram variant. |

Note: two PNGs referenced in the project's "Key Figures" list
(`steamboat_database_architecture_diagram.png`,
`steamboat_poster_database_diagram.png`) are dated well before this
folder's current scripts and are not reproducible from anything here --
likely made by hand before the current schema existed. Left as
historical artifacts rather than deleted.
