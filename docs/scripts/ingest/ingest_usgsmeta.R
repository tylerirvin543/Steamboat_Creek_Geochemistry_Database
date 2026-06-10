ingest_usgs_metadata <- function(con, metadata_path) {
  
  library(readr)
  library(dplyr)
  
  meta <- read_csv(metadata_path, show_col_types = FALSE)
  
  meta_clean <- meta %>%
    transmute(
      station_id = monitoring_location_id,
      latitude   = y,
      longitude  = x
    ) %>%
    distinct()
  
  dbWriteTable(con, "USGS_Stations", meta_clean, append = TRUE)
  
  message("✅ Inserted USGS station metadata: ", nrow(meta_clean))
}