# ============================================================
# register_facies_clusters.R
#
# register_facies_clusters(con, facies_result)
#
# Persists the output of run_facies_clustering(con)
# (scripts/analysis/cluster_hydrochemical_facies.R) into
# Facies_Cluster_Runs / Facies_Cluster_Assignments
# (database/schema/13_facies_clusters_schema.R). Does NOT change the
# clustering algorithm itself -- this is purely a "write the existing
# result to the database" step, so cluster_hydrochemical_facies.R
# stays the single source of truth for the actual statistics.
#
# Every call creates a brand-new run_id (never updates/overwrites a
# prior run) -- see the schema file's header for why. Idempotent in
# the sense that calling it twice with the same facies_result just
# creates two runs (both real, both kept); if that's not wanted,
# check run_facies_clustering()'s output for changes before calling.
#
# Usage:
#   source("scripts/analysis/cluster_hydrochemical_facies.R")
#   source("scripts/analysis/register_facies_clusters.R")
#   fc <- run_facies_clustering(con)
#   register_facies_clusters(con, fc)
# ============================================================

library(DBI)
library(dplyr)

register_facies_clusters <- function(con, facies_result, notes = NA_character_) {
  d <- facies_result$data

  # kmeans_agreement_pct_hc/_mclust are new (2026-09-27, the k-means
  # third cross-check) -- NA_real_ if facies_result predates that
  # addition (an older in-memory result without those list elements),
  # so this stays backward-compatible rather than erroring.
  run_row <- data.frame(
    run_date = as.character(Sys.time()),
    method = "ward_hierarchical",
    k = facies_result$k,
    silhouette_selected = 1L,
    mclust_agreement_pct = facies_result$agreement_pct,
    kmeans_agreement_pct_hc = if (!is.null(facies_result$agreement_pct_kmeans_hc)) facies_result$agreement_pct_kmeans_hc else NA_real_,
    kmeans_agreement_pct_mclust = if (!is.null(facies_result$agreement_pct_kmeans_mclust)) facies_result$agreement_pct_kmeans_mclust else NA_real_,
    n_samples_clustered = nrow(d),
    core_analytes = "Na,K,Ca,Mg,Cl,SO4,Alkalinity",
    notes = notes
  )
  dbWriteTable(con, "Facies_Cluster_Runs", run_row, append = TRUE, row.names = FALSE)
  run_id <- dbGetQuery(con, "SELECT MAX(run_id) AS id FROM Facies_Cluster_Runs")$id

  assignments <- d |>
    dplyr::transmute(
      run_id = run_id,
      sample_id = sample_id,
      location_id = location_id,
      facies_cluster = as.integer(as.character(facies_cluster)),
      facies_cluster_mclust = if ("facies_cluster_mclust" %in% names(d)) {
        as.integer(as.character(facies_cluster_mclust))
      } else {
        NA_integer_
      },
      facies_cluster_kmeans = if ("facies_cluster_kmeans" %in% names(d)) {
        as.integer(as.character(facies_cluster_kmeans))
      } else {
        NA_integer_
      }

    ) |>
    dplyr::distinct(sample_id, .keep_all = TRUE)

  dbWriteTable(con, "Facies_Cluster_Assignments", assignments, append = TRUE, row.names = FALSE)

  message("[facies_register] Registered run_id ", run_id, " (k=", facies_result$k,
          ", mclust agreement=", facies_result$agreement_pct, "%, ",
          nrow(assignments), " sample assignments).")

  invisible(run_id)
}
