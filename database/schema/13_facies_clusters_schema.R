# 13_facies_clusters_schema.R
# ------------------------------------------------------------
# Persisted storage for scripts/analysis/cluster_hydrochemical_facies.R's
# results. Previously this analysis was pure in-R/ggplot -- cluster
# assignments existed only as console messages and in-memory objects
# when a notebook called run_facies_clustering(con), with no database
# table, no GeoPackage layer, and no record of which method/k/
# agreement-score produced a given result. Built per explicit user
# request (Session 33) so facies assignments can be overlaid in ArcGIS
# against digitized fault traces the same way chloride_points already
# supports ArcGIS-side interpolation.
#
# Facies_Cluster_Runs   -- one row per time the clustering is run and
#                          persisted (register_facies_clusters()), not
#                          per sample. Every call creates a NEW run
#                          rather than overwriting a prior one -- this
#                          mirrors the versioned-run pattern already
#                          used for PHREEQC_Solutions, so re-running
#                          after new chemistry arrives keeps history
#                          instead of silently replacing it.
# Facies_Cluster_Assignments -- one row per clustered sample per run.
# ------------------------------------------------------------

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Facies_Cluster_Runs (
  run_id INTEGER PRIMARY KEY,
  run_date TEXT NOT NULL,
  method TEXT NOT NULL,             -- e.g. 'ward_hierarchical'
  k INTEGER NOT NULL,
  silhouette_selected INTEGER,      -- 1 if k was chosen by silhouette width, 0 if overridden
  mclust_agreement_pct REAL,        -- row-wise best-match agreement vs. the independent Gaussian-mixture cross-check
  n_samples_clustered INTEGER,
  core_analytes TEXT,               -- comma-separated, e.g. 'Na,K,Ca,Mg,Cl,SO4,Alkalinity'
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Facies_Cluster_Assignments (
  run_id INTEGER NOT NULL,
  sample_id INTEGER NOT NULL,
  location_id INTEGER,
  facies_cluster INTEGER NOT NULL,        -- Ward hierarchical cluster label
  facies_cluster_mclust INTEGER,          -- independent Gaussian-mixture cross-check label
  UNIQUE (run_id, sample_id),
  FOREIGN KEY (run_id) REFERENCES Facies_Cluster_Runs(run_id)
);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_facies_assignments_run ON Facies_Cluster_Assignments(run_id);
")

message("[SCHEMA] Facies_Cluster_Runs / Facies_Cluster_Assignments ready.")
