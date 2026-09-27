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

# ------------------------------------------------------------
# MIGRATION (2026-09-27): k-means added as a third cross-check
# alongside hierarchical (Ward)/mclust -- see
# scripts/analysis/cluster_hydrochemical_facies.R. Additive
# ALTER TABLE ADD COLUMN, same idempotent dbListFields()-check
# pattern used elsewhere in this project; never a destructive
# CREATE TABLE rewrite. Old runs simply have NULL in these new
# columns (correct -- they predate this method).
# ------------------------------------------------------------
run_cols <- dbListFields(con, "Facies_Cluster_Runs")
if (!"kmeans_agreement_pct_hc" %in% run_cols) {
  message("[MIGRATION] Facies_Cluster_Runs missing kmeans_agreement_pct_hc -- adding.")
  dbExecute(con, "ALTER TABLE Facies_Cluster_Runs ADD COLUMN kmeans_agreement_pct_hc REAL")
}
if (!"kmeans_agreement_pct_mclust" %in% run_cols) {
  message("[MIGRATION] Facies_Cluster_Runs missing kmeans_agreement_pct_mclust -- adding.")
  dbExecute(con, "ALTER TABLE Facies_Cluster_Runs ADD COLUMN kmeans_agreement_pct_mclust REAL")
}

assignment_cols <- dbListFields(con, "Facies_Cluster_Assignments")
if (!"facies_cluster_kmeans" %in% assignment_cols) {
  message("[MIGRATION] Facies_Cluster_Assignments missing facies_cluster_kmeans -- adding.")
  dbExecute(con, "ALTER TABLE Facies_Cluster_Assignments ADD COLUMN facies_cluster_kmeans INTEGER")
}

message("[SCHEMA] Facies_Cluster_Runs / Facies_Cluster_Assignments ready.")
