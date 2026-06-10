build_isotope_pairs <- function(con) {
  
  message("[ISOTOPES] Building isotope pairs")
  
  iso <- dbGetQuery(con, "
SELECT
  sample_id,
  CASE
    WHEN LOWER(analyte) LIKE '%18%' THEN 'd18O'
    WHEN LOWER(analyte) LIKE '%d2%' OR LOWER(analyte) LIKE '%deuter%' THEN 'd2H'
    ELSE NULL
  END AS analyte_clean,
  value
FROM vw_isotopes_gis
")
  
  iso <- iso %>%
    filter(!is.na(analyte_clean))
  
  wide <- iso %>%
    tidyr::pivot_wider(names_from = analyte_clean, values_from = value)
  
  wide <- iso %>%
    pivot_wider(names_from = analyte, values_from = value)
  
  dbWriteTable(con, "Isotope_Pairs", wide, overwrite = TRUE)
}
