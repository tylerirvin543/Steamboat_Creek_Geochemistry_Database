library(DBI)
library(dplyr)

update_location_geometry <- function(con) {
  
  message("---- Updating location geometry ----")
  
  if (missing(con)) {
    stop("Database connection `con` not provided.")
  }
  
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  
  cols <- dbListFields(con, "Locations")
  
  if (!all(c("latitude", "longitude") %in% cols)) {
    stop("Locations table missing latitude/longitude.")
  }
  
  if (!"geom" %in% cols) {
    dbExecute(con, "ALTER TABLE Locations ADD COLUMN geom TEXT;")
  }
  
  locs <- dbReadTable(con, "Locations")
  
  updated <- locs %>%
    mutate(
      geom = ifelse(
        !is.na(longitude) & !is.na(latitude),
        paste0("POINT(", longitude, " ", latitude, ")"),
        NA_character_
      )
    )
  
  # WRITE TO TEMP TABLE
  dbWriteTable(con, "tmp_locations_geom", updated, overwrite = TRUE)
  
  # UPDATE ONLY geom column (NO DROP, NO FK ISSUE)
  dbExecute(con, "
  UPDATE Locations
  SET geom = (
    SELECT tmp.geom
    FROM tmp_locations_geom tmp
    WHERE tmp.location_id = Locations.location_id
  );
  ")
  
  dbExecute(con, "DROP TABLE tmp_locations_geom")
  
  message("Updated geometry for ", nrow(updated), " locations")
  message("---- Geometry update COMPLETE ----")
}
