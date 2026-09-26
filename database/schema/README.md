# database/schema/ -- folder index

Numbered, additive schema files, sourced in order (both at initial
connection and in the DEMO-mode reset block in `run_pipeline.R`). Each
uses `CREATE TABLE IF NOT EXISTS` plus explicit `ALTER TABLE`
migrations for anything added to an existing table after the fact --
never a destructive `DROP`/recreate on a table that might already hold
real data (the one exception, `Well_Lithology`'s `NOT NULL` removal,
is documented inline in `07_well_logs_schema.R` since SQLite can't
drop a column constraint via `ALTER TABLE`).

| File | Adds |
|---|---|
| `01_define_schema.R` | The core schema: `Locations`, `Wells`, `Sampling_Events`, `Samples`, `Lab_Analyses`, `Field_Measurements`, `Isotope_Analyses`, `Temperature_Loggers`/`Observations`, `Water_Level_Observations`, `Data_Sources`, and the additive migrations accumulated for each (coordinate provenance columns, `coord_key`, etc.). |
| `02_conductivity_schema.R` | `Conductivity_Loggers`/`Conductivity_Observations` (the HOBO/Onset EC-logger workstream). |
| `02_define_validators.R` | Shared validation helper functions used across ingest scripts (not a table-creating file, despite the `02_` prefix). |
| `03_weather_schema.R` | `Weather_Stations`/`Weather_Observations` (long-format, any parameter -- NOAA daily weather and, later, hourly barometric pressure both land here). |
| `04_photo_location_schema.R` | `Photo_Location_Candidates`, `Photo_Location_QC`, `Field_Observations`, plus `Locations.coordinate_source`/`coordinate_uncertainty_m`. |
| `05_well_network_schema.R` | `Well_Aliases`, `Sampling_Ports`, `Production_Port_Links`, `Port_Injection_Links`, `vw_production_to_port`/`vw_port_to_injection`/`vw_well_flow_network`, `Wells.well_role`. |
| `06_facility_areas_schema.R` | `Facility_Areas` (the project's first polygon-geometry table) + `Sampling_Ports` coordinate columns. |
| `07_well_logs_schema.R` | `Well_Log_Documents`, `Well_Lithology`, later extended with `alt_file_path`/`alt_file_hash` (dual-scan tracking) and the `Well_Lithology.well_id` NOT-NULL-removal table rebuild. |
| `08_phreeqc_schema.R` | The full `PHREEQC_*` table family (`Solutions`, `Results`, `Temp_Sweep`, `Run_Failures`, `Mixing_*`, `Inverse_*`, `Gas_Phase_*`) plus `Chemistry_Parameters`. |
| `09_ndom_wells_schema.R` | 8 new `Wells` identifier columns (`ndom_permit`, `api_number`, etc.), `NDOM_Well_Records` staging table, and the one-time feet-to-meters `elevation_m` migration (later extended to also cover `Locations.elevation_m`). |
| `10_ndwr_stream_flow_schema.R` | `Stream_Flow_Observations` (daily manual discharge, cfs, at gauged creek sites). |
| `11_fault_traces_schema.R` | `Fault_Traces`/`Alteration_Zones` -- structure-only, waiting on digitized data (see `docs/action_items_for_user.md`). |
| `12_earthquake_schema.R` | `Earthquake_Events` (real USGS FDSN catalog, pre-computed distance to the Steamboat field). |
| `13_facies_clusters_schema.R` | `Facies_Cluster_Runs`/`Facies_Cluster_Assignments` (persists `run_facies_clustering()`'s output). |
| `14_aquifer_classification_schema.R` | `Wells.aquifer_type`/`aquifer_type_basis` (derived from real barometric efficiency). |
| `15_well_deviation_surveys_schema.R` | `Well_Deviation_Surveys` (self-seeds 4 real rows for well 83C-6ST1 from Akerley et al. 2021). |
| `lab_analyte_map.R` | Not a schema file -- the raw-lab-parameter-name -> standard-analyte-code mapping table (`charge`, `molar_mass`, `phreeqc_name`, `conversion_factor` per analyte) used by `ingest_lab.R` and `build_phreeqc_solutions()`. |
| `ndep_analyte_map.R` | Same role as `lab_analyte_map.R`, specific to NDEP's own raw parameter-name conventions (`CHARACTERISTICNAME`), including the CaCO3-vs-HCO3-basis `conversion_factor` fix from Session 15. |
