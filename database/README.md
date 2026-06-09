Database Design and Schema
================
Tyler Irvin

## Overview

The SQLite database (`geochem_sampling.sqlite`) stores all authoritative
geochemical observations used in this project.

All data ingestion (NDEP, field, lab) feeds into the same core schema.

------------------------------------------------------------------------

## Core Tables

### Authoritative Tables

- `Locations`
- `Sampling_Events`
- `Samples`
- `Field_Measurements`
- `Lab_Analyses`
- `Chemistry_Parameters`
- `Data_Sources`

### Derived Tables

- `QC_Summary`
- `PHREEQC_Solutions` (created later)
- Modeling outputs (speciation, inverse models)

------------------------------------------------------------------------

## Relational Structure

- Each **Sample** belongs to:
  - one `Location`
  - one `Sampling_Event`
- Field and lab measurements reference `Samples`
- NDEP and field locations coexist but are **not forced to match**

Foreign keys are enforced via:

``` sql
PRAGMA foreign_keys = ON;

External Identifiers
To preserve provenance, the Samples table stores:

external_event_id
external_station_code
external_sample_id
```

These allow reconstruction of original data sources without polluting
the relational model.

Rebuild Philosophy The database can be rebuilt at any time from raw
inputs using ingestion scripts. Modeling outputs should never be
manually edited or relied upon as permanent data.

------------------------------------------------------------------------

# 3. 📄 `scripts/ingest/README.Rmd`

📍 **Location**
