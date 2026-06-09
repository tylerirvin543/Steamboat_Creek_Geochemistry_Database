Laboratory Data Ingestion
================

## Purpose

This folder contains raw laboratory chemistry outputs.

Lab files are expected to be in wide format and are normalized during
ingestion.

------------------------------------------------------------------------

## Supported Formats

- ICP-MS elemental tables
- General chemistry tables (anions, alkalinity, TDS)
- `<` and `>` qualifiers are supported

------------------------------------------------------------------------

## Rules

- Do not edit raw lab outputs
- Place files directly in this folder
- Unit conversion occurs during ingestion

------------------------------------------------------------------------

## Ingestion Behavior

- Raw lab files are archived
- Chemistry is converted to canonical units
- Data are linked to samples via `sample_code`
- Errors are reported explicitly

Lab ingestion never creates locations or events.
