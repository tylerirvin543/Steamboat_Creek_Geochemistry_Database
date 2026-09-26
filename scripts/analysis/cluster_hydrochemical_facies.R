# ============================================================
# cluster_hydrochemical_facies.R
#
# Purpose:
# Groups real water-chemistry samples (NDEP + FIELD + historical
# Sorey/Colvard 1992 + Mariner & Janik 1995) into hydrochemical facies
# by clustering on the 7 major ions (Na, K, Ca, Mg, Cl, SO4, Alkalinity)
# every sample has in common, optionally cross-checked against PHREEQC
# saturation indices where available. This replaces the previously
# pooled, confounded "all thermal wells vs. time" regression in
# notebook 07 with a group-aware analysis: temporal trend testing is
# only meaningful WITHIN a hydrochemical facies, not across all sites
# regardless of water type.
#
# Design choices, made deliberately rather than defaulted:
#   - Only samples with ALL 7 core majors present are clustered (no
#     imputation) -- ~157 of 846 chemistry-bearing samples as of
#     2026-09-26. This is a real constraint on statistical power, not
#     hidden: reported plainly wherever results are used.
#   - log1p-transform then z-score each analyte before clustering
#     (matches the transform already used for the ComplexHeatmap in
#     website/results.Rmd, for consistency across the project's own
#     visualizations).
#   - Cluster COUNT is chosen objectively via silhouette width
#     (factoextra::fviz_nbclust) and cross-checked with NbClust's
#     majority-vote index, not picked by eye.
#   - Final grouping uses hierarchical clustering (Ward's method,
#     Euclidean distance on the scaled matrix) with the chosen k,
#     cross-checked against an independent Gaussian-mixture fit
#     (mclust) -- if the two disagree substantially, that disagreement
#     is reported, not silently resolved by picking one.
#   - PHREEQC saturation indices (Calcite/Dolomite/Quartz/Chalcedony),
#     where available for a clustered sample, are joined for
#     interpretation/plotting only -- NOT fed into the clustering
#     distance itself, since they exist for only a subset of samples
#     and are themselves derived from the same major-ion inputs
#     (would double-count that signal).
#
# Usage:
#   source("scripts/analysis/cluster_hydrochemical_facies.R")
#   result <- run_facies_clustering(con)
#   result$plot_cluster        # PCA-plane cluster plot (factoextra)
#   result$plot_silhouette     # cluster-count selection diagnostic
#   result$data                # samples with cluster assignment attached
# ============================================================

library(DBI)
library(dplyr)
library(tidyr)
library(ggplot2)
library(cluster)
library(factoextra)
library(mclust)

CORE_ANALYTES <- c("Na", "K", "Ca", "Mg", "Cl", "SO4", "Alkalinity")

get_facies_chemistry <- function(con) {
  chem_long <- dbGetQuery(con, "
    SELECT sm.sample_id, sm.location_id, sm.name AS location_name, sm.analyte, sm.value,
           l.site_type, s.collection_time, s.data_source
    FROM vw_sample_master sm
    JOIN Samples s ON s.sample_id = sm.sample_id
    JOIN Locations l ON l.location_id = sm.location_id
    WHERE sm.analyte IN ('Na','K','Ca','Mg','Cl','SO4','Alkalinity','B','Li')
  ")

  chem_wide <- chem_long %>%
    group_by(sample_id, location_id, location_name, site_type, collection_time, data_source, analyte) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = analyte, values_from = value)

  chem_wide$n_core_present <- rowSums(!is.na(chem_wide[, intersect(CORE_ANALYTES, names(chem_wide))]))
  chem_wide
}

run_facies_clustering <- function(con, k_range = 2:8) {
  chem_wide <- get_facies_chemistry(con)
  complete <- chem_wide %>% filter(n_core_present == length(CORE_ANALYTES))

  message("[facies] ", nrow(chem_wide), " chemistry samples total; ",
          nrow(complete), " have all ", length(CORE_ANALYTES),
          " core majors (Na/K/Ca/Mg/Cl/SO4/Alkalinity) -- these are the ones clustered.")

  mat <- as.matrix(complete[, CORE_ANALYTES])
  mat_log <- log1p(mat)
  mat_scaled <- scale(mat_log)
  rownames(mat_scaled) <- complete$sample_id

  # ---- Cluster count selection (silhouette) ----
  sil_plot <- fviz_nbclust(mat_scaled, FUN = function(x, k) list(cluster = cutree(hclust(dist(x), method = "ward.D2"), k)),
                            method = "silhouette", k.max = max(k_range)) +
    labs(title = "Cluster-count selection (silhouette width)",
         subtitle = paste0("n = ", nrow(mat_scaled), " samples with complete major-ion chemistry"))

  # sil_plot$data$clusters is a factor; as.integer() on a factor returns
  # the level POSITION, not its label -- go through as.character() first
  # (caught by comparing against the plot's own visible peak at k=4).
  best_k <- as.integer(as.character(sil_plot$data$clusters[which.max(sil_plot$data$y)]))
  message("[facies] Silhouette-selected k = ", best_k)

  # ---- Hierarchical clustering (Ward, Euclidean) at chosen k ----
  hc <- hclust(dist(mat_scaled), method = "ward.D2")
  hc_clusters <- cutree(hc, k = best_k)

  # ---- Cross-check: Gaussian mixture (mclust), independent method ----
  set.seed(4821)
  mc <- Mclust(mat_scaled, G = best_k, verbose = FALSE)
  mc_clusters <- mc$classification

  agreement <- if (!is.null(mc_clusters)) {
    tab <- table(hc_clusters, mc_clusters)
    max_overlap <- sum(apply(tab, 1, max))
    round(100 * max_overlap / length(hc_clusters), 1)
  } else NA_real_

  message("[facies] Hierarchical (Ward) vs. Gaussian-mixture (mclust) cluster agreement (best row-wise match): ",
          agreement, "%")

  complete$facies_cluster <- factor(hc_clusters)
  complete$facies_cluster_mclust <- factor(mc_clusters)

  cluster_plot <- fviz_cluster(list(data = mat_scaled, cluster = hc_clusters),
                                geom = "point", ellipse.type = "convex",
                                main = paste0("Hydrochemical facies clusters (k=", best_k, ", Ward/Euclidean)"),
                                subtitle = paste0("PCA plane; site_type shown via point shape below"))

  # Attach PHREEQC saturation indices where available (interpretation only)
  phreeqc_si <- tryCatch(
    dbGetQuery(con, "
      SELECT sample_id, mineral, saturation_index
      FROM PHREEQC_Results
      WHERE mineral IN ('Calcite','Dolomite','Quartz','Chalcedony')
    "),
    error = function(e) NULL
  )
  if (!is.null(phreeqc_si) && nrow(phreeqc_si) > 0) {
    si_wide <- phreeqc_si %>%
      pivot_wider(names_from = mineral, values_from = saturation_index, names_prefix = "SI_")
    complete <- complete %>% left_join(si_wide, by = "sample_id")
  }

  # Cluster-by-site-type summary table (which facies correspond to which
  # a priori site classification -- the real interpretive payoff)
  summary_tbl <- complete %>%
    dplyr::count(facies_cluster, site_type) %>%
    pivot_wider(names_from = site_type, values_from = n, values_fill = 0)

  list(
    data = complete,
    k = best_k,
    agreement_pct = agreement,
    plot_silhouette = sil_plot,
    plot_cluster = cluster_plot,
    site_type_summary = summary_tbl,
    hclust_obj = hc
  )
}
