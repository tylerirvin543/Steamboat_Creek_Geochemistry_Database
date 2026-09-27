# ============================================================
# facies_random_forest.R
#
# Purpose:
# Random-forest variable importance for hydrochemical facies
# membership -- which of the 7 core major ions (Na/K/Ca/Mg/Cl/SO4/
# Alkalinity) most separates the already-persisted facies clusters
# (run_facies_clustering(), see cluster_hydrochemical_facies.R). An
# independent, non-distance-based cross-check on the PCA-loading-
# based reading already given in prose (PC1 ~ Na/K/Cl/SO4, PC2 ~
# Ca/Mg) -- random forest doesn't assume linear separability the way
# PCA loadings implicitly do, so agreement between the two is a real,
# not circular, validation.
#
# Deliberately built now, per explicit user instruction, ahead of the
# k-means cross-check (which waits until the site_type='background'
# cleanup is independently verified -- see AGENTS.md/plan notes).
# `ranger` is already installed/used elsewhere in this project
# (sampling-frequency workstream) -- no new dependency.
#
# Usage:
#   source("scripts/analysis/cluster_hydrochemical_facies.R")
#   source("scripts/analysis/facies_random_forest.R")
#   fc <- run_facies_clustering(con)
#   rf_result <- run_facies_random_forest(fc)
#   rf_result$plot_importance
#   rf_result$confusion_matrix
# ============================================================

library(ranger)
library(dplyr)
library(ggplot2)

CORE_ANALYTES_RF <- c("Na", "K", "Ca", "Mg", "Cl", "SO4", "Alkalinity")

#' @param fc The list returned by run_facies_clustering(con).
#' @param n_trees Number of trees (ranger default-ish; kept modest
#'   since n=157 is small -- more trees won't meaningfully change a
#'   stable importance ranking at this sample size).
#' @param seed Random seed for both the train/test split and ranger's
#'   own bootstrap sampling.
#' @return list(model=, importance=, plot_importance=,
#'   confusion_matrix=, oob_error=, test_accuracy=)
run_facies_random_forest <- function(fc, n_trees = 1000, seed = 7213,
                                      out_path = "output/figures/facies/facies_rf_importance.png") {
  d <- fc$data %>%
    dplyr::select(dplyr::all_of(c("facies_cluster", CORE_ANALYTES_RF))) %>%
    dplyr::filter(stats::complete.cases(.)) %>%
    dplyr::mutate(facies_cluster = factor(facies_cluster))

  set.seed(seed)
  # A held-out test split, even though the primary goal here is
  # variable importance (not predictive deployment) -- reporting a
  # real test accuracy is a cheap, honest way to show the importance
  # ranking isn't coming from a model that can't actually distinguish
  # the clusters at all.
  n <- nrow(d)
  test_idx <- sample(seq_len(n), size = round(0.25 * n))
  train <- d[-test_idx, ]
  test <- d[test_idx, ]

  rf <- ranger::ranger(
    facies_cluster ~ ., data = train,
    num.trees = n_trees, importance = "impurity",
    seed = seed
  )

  pred <- predict(rf, data = test)$predictions
  test_accuracy <- mean(pred == test$facies_cluster)
  confusion <- table(observed = test$facies_cluster, predicted = pred)

  imp <- rf$variable.importance
  imp_df <- data.frame(analyte = names(imp), importance = as.numeric(imp)) %>%
    dplyr::arrange(dplyr::desc(importance)) %>%
    dplyr::mutate(analyte = factor(analyte, levels = rev(analyte)))

  p <- ggplot(imp_df, aes(x = importance, y = analyte)) +
    geom_col(fill = "#3b6fb6") +
    labs(
      title = "Random-forest variable importance for facies membership",
      subtitle = paste0(
        "n = ", nrow(d), " samples (", nrow(train), " train / ", nrow(test), " test); ",
        "OOB error = ", round(rf$prediction.error, 3), "; test accuracy = ", round(test_accuracy, 3)
      ),
      x = "Importance (mean decrease in node impurity, Gini)", y = NULL
    ) +
    theme_minimal(base_size = 12)

  message("[facies_rf] OOB error: ", round(rf$prediction.error, 4),
          " | Held-out test accuracy: ", round(test_accuracy, 4),
          " (n_test=", nrow(test), ")")
  message("[facies_rf] Importance ranking: ", paste(imp_df$analyte[order(-imp_df$importance)], collapse = " > "))

  if (!is.null(out_path)) {
    resolved_path <- out_path
    if (basename(getwd()) == "notebooks") resolved_path <- file.path("..", out_path)
    dir.create(dirname(resolved_path), showWarnings = FALSE, recursive = TRUE)
    ggsave(resolved_path, plot = p, width = 8, height = 5, dpi = 200)
  }

  list(
    model = rf,
    importance = imp_df,
    plot_importance = p,
    confusion_matrix = confusion,
    oob_error = rf$prediction.error,
    test_accuracy = test_accuracy
  )
}
