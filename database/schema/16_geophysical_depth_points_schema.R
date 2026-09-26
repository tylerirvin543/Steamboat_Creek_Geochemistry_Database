# ============================================================
# 16_geophysical_depth_points_schema.R
#
# Purpose: Geophysical_Depth_Model_Points -- model-derived depth-to-
# bedrock / layer-thickness points along a geophysical forward-model
# profile (e.g. Skalbeck 2001's 2.75-D gravity/aeromagnetic model).
# Deliberately NOT part of Well_Lithology: these are not real well logs,
# they are interpolated/forward-modeled estimates along a profile line,
# and conflating the two would misrepresent the data's real confidence
# level.
# ============================================================

create_geophysical_depth_points_schema <- function(con) {
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Geophysical_Depth_Model_Points (
      point_id INTEGER PRIMARY KEY,
      utm_e REAL,
      utm_n REAL,
      utm_zone TEXT DEFAULT '11N',
      datum TEXT DEFAULT 'NAD83',
      latitude REAL,
      longitude REAL,
      qal_thickness_m REAL,
      tv_thickness_m REAL,
      alt_kgd_km_thickness_m REAL,
      depth_to_bedrock_m REAL,
      profile_line TEXT,
      source_document TEXT,
      coordinate_uncertainty_m REAL DEFAULT 200,
      notes TEXT
    )
  ")
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_geophys_depth_pts_coord
    ON Geophysical_Depth_Model_Points(latitude, longitude)
  ")
  invisible(NULL)
}

# Additive migration (2026-09-26, continued): real ground-surface
# elevation at each depth-model point, from the USGS Elevation Point
# Query Service (a real DEM source, queried point-by-point via its
# public REST API -- no raster download/processing needed). Lets
# Leapfrog horizon exports report true Z elevation instead of only
# depth-below-surface.
migrate_geophysical_depth_points_elevation <- function(con) {
  cols <- dbGetQuery(con, "PRAGMA table_info(Geophysical_Depth_Model_Points)")$name
  if (!"surface_elevation_m" %in% cols) {
    dbExecute(con, "ALTER TABLE Geophysical_Depth_Model_Points ADD COLUMN surface_elevation_m REAL")
  }
  if (!"elevation_source" %in% cols) {
    dbExecute(con, "ALTER TABLE Geophysical_Depth_Model_Points ADD COLUMN elevation_source TEXT")
  }
  invisible(NULL)
}
