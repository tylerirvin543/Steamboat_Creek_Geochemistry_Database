audit_sample_duplicates <- function(con) {
  
  message("---- Running duplicate audit ----")
  
  samples <- DBI::dbReadTable(con, "Samples")
  
  # ---------------------------------
  # GROUP BY KEY (your uniqueness rule)
  # ---------------------------------
  dup <- samples |>
    dplyr::group_by(location_id, collection_time, sample_type) |>
    dplyr::summarise(
      sources = paste(unique(data_source), collapse = ", "),
      n = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::filter(n > 1)
  
  if (nrow(dup) == 0) {
    message("✅ No duplicate samples detected across sources")
    return(invisible(NULL))
  }
  
  # ---------------------------------
  # IDENTIFY CROSS-SOURCE OVERLAPS
  # ---------------------------------
  overlaps <- dup |>
    dplyr::filter(
      grepl("FIELD", sources) & grepl("NDEP", sources)
    )
  
  message("⚠️ Duplicate keys detected: ", nrow(dup))
  message(" Cross-source overlaps (FIELD + NDEP): ", nrow(overlaps))
  
  print(head(overlaps, 20))
  
  # ---------------------------------
  # OPTIONAL: WRITE REPORT
  # ---------------------------------
  out_dir <- "output/qc"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  readr::write_csv(dup, file.path(out_dir, "all_duplicate_samples.csv"))
  readr::write_csv(overlaps, file.path(out_dir, "cross_source_overlaps.csv"))
  
  message("Duplicate reports written to output/qc/")
  
  return(list(
    all_duplicates = dup,
    cross_source_overlaps = overlaps
  ))
}