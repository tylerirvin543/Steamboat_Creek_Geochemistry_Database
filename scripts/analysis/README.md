# scripts/analysis/

Derived-analysis and statistics scripts that run *after* ingestion --
none of these write raw source data, they all read from
core tables/views and either write derived tables/views back to the
database or produce a plot/report object for a notebook to use.

| Script | What it does |
|---|---|
| `create_analysis_views.R` | Creates the project's core SQL views (`vw_sample_master`, `vw_major_ions`, `vw_temperature_timeseries`, `vw_isotope_pairs`, etc.) that every downstream analysis/export script reads from instead of the raw tables directly. Run near the start of every pipeline call. |
| `calc_gradients.R` | Computes pairwise hydraulic/temperature gradients between locations for the gradient system. |
| `build_gradient_products.R` | Wraps `calc_gradients.R`'s output into the `Hydraulic_Gradients` table used by the GIS export and pipeline report. |
| `build_isotope_pairs.R` | Builds delta-18O/delta-D isotope pairs for the mixing-diagram figure and `vw_isotope_pairs`. |
| `build_temp_gradient_links.R` | Links temperature-logger time series into gradient-style pairs for thermal-gradient analysis. |
| `build_analysis_products.R` | Orchestrates the thermal/gradient "analysis product" build steps in one call (`build_thermal_summary()`, etc.), consumed by `run_pipeline.R`. |
| `data_availability.R` | Builds the horizontal "data availability through time" Gantt-style chart (one bar per data source, earliest-to-latest dated record) -- writes `data/derived/data_availability/data_availability.csv` and `output/figures/data_availability_timeline.png`. Runs unconditionally (no `RUN_INGEST`/`RUN_ANALYSIS` flag) since it's read-only reporting. |
| `isotope_mixing_plot.R` | Builds the d18O-vs-dD isotope mixing diagram (`Figures/d18O_dD.jpeg`). |
| `cluster_hydrochemical_facies.R` | Unsupervised hydrochemical facies clustering (Ward hierarchical + silhouette-selected k, cross-checked against `mclust`) on the 7 core major ions. `run_facies_clustering(con)` is the entry point; used live in notebooks `07`/`08` and persisted via `register_facies_clusters.R`. |
| `register_facies_clusters.R` | Persists `run_facies_clustering()`'s result into `Facies_Cluster_Runs`/`Facies_Cluster_Assignments` (one row per run + one row per clustered sample) so cluster labels survive across sessions and can back a GeoPackage layer. Wired into `run_pipeline.R` as `RUN_ANALYSIS$facies_clusters` (opt-in). |
| `facies_depth_map.R` | Maps facies-cluster membership against well depth/completion interval for a Steamboat-field-focused view. |
| `barometric_efficiency.R` | Computes real barometric efficiency (Sorey's level-vs-pressure regression, and a first-differenced form) for every well with continuous water level overlapping the real barometric-pressure record, plus `classify_aquifer_type()` which derives `Wells.aquifer_type` from the real BE result against Steamboat's own historical BE range. Wired into `run_pipeline.R` as `RUN_ANALYSIS$aquifer_classification`. |
| `well_completion_profile.R` | `plot_well_completion_profile()` -- a completion-interval (screened/perforated interval) inventory chart, explicitly distinct from lithology (which is a separate, mostly-unpopulated table). Flags wells with an unusually long open interval as `long_open_interval` (likely multi-zone). |
| `sampling_frequency/` | A self-contained sub-workstream (own README/notebook) for the Cl-sampling-frequency statistical question -- see that folder and `notebooks/01_conductivity_temporal_structure.qmd`. |
