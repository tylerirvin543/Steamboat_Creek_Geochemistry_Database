# Quality Control (QC)

This folder contains non-destructive quality control checks applied
after data ingestion.

## What QC Does

- Identifies missing or invalid metadata
- Flags impossible or out-of-range measurements
- Detects duplicate or conflicting records
- Checks temporal integrity of sensor data
- Summarizes QC results in tables and reports

## What QC Does Not Do

- Does not modify raw data
- Does not delete database records
- Does not enforce modeling decisions

## Outputs

- CSV files in `qc_reports/` for audit trails
- Summary rows appended to `QC_Summary`
- Console output for immediate review
``