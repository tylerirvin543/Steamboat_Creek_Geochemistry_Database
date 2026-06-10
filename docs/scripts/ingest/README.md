Data Ingestion Workflow
================

## Overview

This folder contains all scripts responsible for ingesting raw data into
the SQLite database.

Each data source has its own adapter: - `ingest_ndep.R` -
`ingest_field.R` - `ingest_lab.R`

All adapters follow the same principles: - Validate first - Archive raw
inputs - Insert relational data - Wipe working templates only on success

------------------------------------------------------------------------

## Run Order

``` r
source("scripts/ingest/ingest_ndep.R")
source("scripts/ingest/ingest_field.R")
source("scripts/ingest/ingest_lab.R")
```

Or simply:

``` r
source("scripts/ingest/update_all_data.R")
```

------------------------------------------------------------------------

\##Validation & Errors

Invalid parameter names halt ingestion Missing sample codes halt
ingestion No database writes occur if validation fails Templates are not
wiped on failure

Error messages indicate:

which file which column which row(s)

------------------------------------------------------------------------

## Archiving

Raw Excel inputs are archived to:

data/processed/\*\_archive/YYYYMMDD_HHMM/

Nothing is ever lost or overwritten.

## After Ingestion

After ingestion completes successfully:

QC checks are run automatically Modeling scripts may be executed
