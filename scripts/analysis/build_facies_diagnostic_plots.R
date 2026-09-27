# ============================================================
# build_facies_diagnostic_plots.R
#
# Purpose:
# Additional statistical diagnostic/interpretive figures for the
# hydrochemical facies clustering built in
# cluster_hydrochemical_facies.R (run_facies_clustering()). These
# answer "how good is this k=4 grouping, and what does it mean" --
# complementing (not duplicating) the PCA biplot + ComplexHeatmap
# already built and embedded in notebook 07's facies section.
#
# Each function takes the list returned by run_facies_clustering(con)
# (referred to as `fc` below) and returns a plot object. Each also
# optionally saves a PNG to output/figures/facies/ when `out_path` is
# supplied, following this project's existing
# output/figures/<subfolder>/<name>.png convention.
#
# Usage:
#   source("scripts/analysis/cluster_hydrochemical_facies.R")
#   source("scripts/analysis/build_facies_diagnostic_plots.R")
#   fc <- run_facies_clustering(con)
#   plot_facies_dendrogram(fc)
#   plot_facies_silhouette_diagnostic(fc)
#   plot_facies_agreement_heatmap(fc)
#   plot_facies_alluvial(fc)
#   plot_facies_ion_raincloud(fc)
# ============================================================

library(ggplot2)
library(dplyr)
library(tidyr)
library(factoextra)
library(cluster)
library(ggdist)
library(ggbeeswarm)
library(ggalluvial)
library(ggrepel)

.save_if_requested <- function(plot_obj, out_path, width = 8, height = 6, dpi = 200) {
  if (!is.null(out_path)) {
    dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
    ggsave(out_path, plot = plot_obj, width = width, height = height, dpi = dpi)
  }
  invisible(plot_obj)
}

#' Dendrogram of the Ward hierarchical clustering, cut at k, colored
#' by cluster. Direct visual justification for "why k clusters" that
#' the silhouette-selection plot alone doesn't show -- in particular,
#' whether a small cluster (e.g. facies 4, n=8) is a genuinely
#' distinct, tight branch or a late, weak split.
plot_facies_dendrogram <- function(fc, out_path = "output/figures/facies/facies_dendrogram.png") {
  p <- fviz_dend(
    fc$hclust_obj, k = fc$k, rect = TRUE, cex = 0.35,
    k_colors = scales::hue_pal()(fc$k),
    main = paste0("Hydrochemical facies dendrogram (Ward's method, k=", fc$k, ")"),
    ylab = "Height (Euclidean distance, scaled log-ion space)"
  ) +
    labs(subtitle = paste0(
      "n = ", nrow(fc$data), " samples; ", fc$agreement_pct,
      "% agreement with independent Gaussian-mixture (mclust) fit at the same k"
    ))
  .save_if_requested(p, out_path, width = 10, height = 5)
}

#' Per-sample silhouette width, colored by cluster. Diagnostic of how
#' well each individual sample fits its assigned cluster -- a real
#' check on the "chemically interpretable, not arbitrary" claim made
#' about the facies elsewhere in the notebook, since a cluster with
#' many low/negative-silhouette members would weaken that claim.
plot_facies_silhouette_diagnostic <- function(fc, out_path = "output/figures/facies/facies_silhouette.png") {
  sil <- cluster::silhouette(as.integer(as.character(fc$data$facies_cluster)), fc$dist_obj)
  p <- fviz_silhouette(sil, print.summary = FALSE) +
    labs(
      title = "Per-sample silhouette width by facies cluster",
      subtitle = "Higher = better-separated from neighboring clusters; near-zero/negative = weak/ambiguous fit"
    ) +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
  .save_if_requested(p, out_path, width = 9, height = 5)
}

#' Confusion matrix (as a heatmap) of the hierarchical (Ward) vs.
#' independent Gaussian-mixture (mclust) cluster labels -- turns the
#' bare "X% agreement" number already reported in prose into a picture
#' of exactly which cluster pairs the two methods disagree on.
plot_facies_agreement_heatmap <- function(fc, out_path = "output/figures/facies/facies_agreement_heatmap.png") {
  .pair_tab <- function(a, b, a_name, b_name, agree_pct) {
    t <- as.data.frame(table(row_lab = a, col_lab = b))
    t$comparison <- paste0(a_name, " vs. ", b_name, " (", agree_pct, "% agreement)")
    t
  }

  has_kmeans <- "facies_cluster_kmeans" %in% names(fc$data) && !is.null(fc$agreement_pct_kmeans_hc)

  tab_list <- list(
    .pair_tab(fc$data$facies_cluster, fc$data$facies_cluster_mclust,
              "Hierarchical (Ward)", "mclust", fc$agreement_pct)
  )
  if (has_kmeans) {
    tab_list[[2]] <- .pair_tab(fc$data$facies_cluster, fc$data$facies_cluster_kmeans,
                                "Hierarchical (Ward)", "k-means", fc$agreement_pct_kmeans_hc)
    tab_list[[3]] <- .pair_tab(fc$data$facies_cluster_mclust, fc$data$facies_cluster_kmeans,
                                "mclust", "k-means", fc$agreement_pct_kmeans_mclust)
  }
  tab <- dplyr::bind_rows(tab_list)

  p <- ggplot(tab, aes(x = col_lab, y = row_lab, fill = Freq)) +
    geom_tile(color = "white") +
    geom_text(aes(label = Freq), color = "black", size = 4) +
    scale_fill_viridis_c(option = "rocket", direction = -1, name = "n samples") +
    facet_wrap(~comparison, scales = "free") +
    labs(
      title = if (has_kmeans) {
        "Pairwise cluster-label agreement: hierarchical (Ward) vs. mclust vs. k-means"
      } else {
        "Hierarchical (Ward) vs. Gaussian-mixture (mclust) cluster labels"
      },
      subtitle = "Off-diagonal cells show exactly where each pair of independent methods disagree",
      x = "cluster label (2nd method)", y = "cluster label (1st method)"
    ) +
    theme_minimal(base_size = 12) +
    theme(aspect.ratio = 1)
  .save_if_requested(p, out_path, width = if (has_kmeans) 13 else 6, height = if (has_kmeans) 5 else 5.5)
}

#' Alluvial (flow) diagram: site_type -> facies_cluster. Turns the
#' already-computed fc$site_type_summary crosstab into a real flow
#' figure -- shows at a glance which site types dominate each facies,
#' and whether any site type splits across multiple facies.
plot_facies_alluvial <- function(fc, out_path = "output/figures/facies/facies_alluvial.png") {
  flow_data <- fc$data %>% dplyr::count(site_type, facies_cluster, name = "n")
  p <- ggplot(flow_data, aes(axis1 = site_type, axis2 = facies_cluster, y = n)) +
    geom_alluvium(aes(fill = facies_cluster), width = 0.25, alpha = 0.85) +
    geom_stratum(width = 0.25, fill = "grey90", color = "grey30") +
    geom_text_repel(stat = ggalluvial::StatStratum, aes(label = after_stat(stratum)),
                     size = 3.2, direction = "y", nudge_x = 0.35, segment.size = 0.3, seed = 4172) +
    scale_x_discrete(limits = c("Site type", "Facies cluster"), expand = c(0.18, 0.18)) +
    labs(
      title = "Site type -> hydrochemical facies cluster (real sample counts)",
      subtitle = paste0("n = ", nrow(fc$data), " samples with complete major-ion chemistry"),
      y = "Number of samples", fill = "Facies\ncluster"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
  .save_if_requested(p, out_path, width = 8, height = 6.5)
}

#' Per-cluster major-ion raincloud (ggdist half-eye + ggbeeswarm
#' points), faceted by ion, log1p scale (matches the transform used
#' for clustering itself). Directly visualizes the separation claims
#' already made in prose ("pure Na-Cl thermal cluster," "elevated-Ca/Mg
#' cluster," etc.) with real distributions rather than summary numbers
#' alone.
plot_facies_ion_raincloud <- function(fc, ions = c("Na", "Cl", "Ca", "Mg"),
                                       out_path = "output/figures/facies/facies_ion_raincloud.png") {
  long <- fc$data %>%
    dplyr::select(sample_id, facies_cluster, dplyr::all_of(ions)) %>%
    pivot_longer(cols = dplyr::all_of(ions), names_to = "ion", values_to = "value") %>%
    mutate(ion = factor(ion, levels = ions))

  p <- ggplot(long, aes(x = facies_cluster, y = value, color = facies_cluster, fill = facies_cluster)) +
    stat_halfeye(alpha = 0.55, .width = c(0.66, 0.95), point_interval = "median_qi",
                 position = position_nudge(x = 0.15)) +
    geom_quasirandom(width = 0.08, size = 1, alpha = 0.5, show.legend = FALSE) +
    scale_y_log10() +
    facet_wrap(~ ion, scales = "free_y", nrow = 1) +
    labs(
      title = "Major-ion concentration by facies cluster",
      subtitle = "ggdist half-eye distributions + individual samples (ggbeeswarm), log scale",
      x = "Facies cluster", y = "Concentration (mg/L, log scale)"
    ) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none")
  .save_if_requested(p, out_path, width = 11, height = 4.5)
}
