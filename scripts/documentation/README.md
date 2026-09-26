# scripts/documentation/

| Script | What it does |
|---|---|
| `create_table_descriptions.R` | Generates a plain-language description for every table/column in the schema (introspects `sqlite_master`/`PRAGMA table_info`), used to keep the rendered documentation website's Data page accurate without hand-maintaining a separate data dictionary. |
