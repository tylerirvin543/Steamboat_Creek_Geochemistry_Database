build_sample_flux <- function(con) {
  
  message("\n[FLUX] Building sample hydrochem flux")
  
  samples <- dbGetQuery(con, "
    SELECT
      s.sample_id,
      datetime(s.collection_time, 'unixepoch') AS sample_time,
      l.coord_key,
      l.name,
      l.latitude,
      l.longitude
    FROM Samples s
    JOIN Locations l ON s.location_id = l.location_id
  ")
  
  chemistry <- dbGetQuery(con, "
    SELECT sample_id, analyte, value, units
    FROM Lab_Analyses
    WHERE analyte IN ('Ca','Mg','Na','K','Cl','SO4','HCO3')
  ")
  
  flow <- dbReadTable(con, "usgs_samples_aligned")
  
  library(data.table)
  setDT(samples)
  setDT(chemistry)
  setDT(flow)
  
  message("  → Joining flow + chemistry...")
  
  result <- merge(flow, chemistry, by = "sample_id")
  result[, mass_flux := discharge_m3_s * value]
  
  message("  → Writing to database...")
  
  dbWriteTable(con, "sample_flux", result, overwrite = TRUE)
  
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_sample_flux_sample
    ON sample_flux(sample_id)
  ")
  
  message("✅ sample_flux ready (", nrow(result), " rows)")
}