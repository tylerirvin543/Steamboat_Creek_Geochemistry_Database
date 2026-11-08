#28_well_classes_schema
# ------------------------------------------------------------
# Well-class vocabulary for GIS symbology, added without touching the
# Wells.well_role CHECK constraint (SQLite cannot widen it).
#   Wells.well_use         what the well is/was for (production, injection,
#                          observation, thermal_gradient, stratigraphic_test,
#                          domestic, resort_spa, historical_exploration,
#                          abandoned_unmarked, eruption_pipe, unknown)
#   Wells.well_status_std  standardised status (in_use, shut_in, idle,
#                          plugged_abandoned, abandoned_unplugged, unknown).
#                          Wells.well_status keeps the raw NDOM text.
# Seeding is fill-only (only rows where the column is NULL) and idempotent,
# so it is safe to run on every schema load, including after new wells arrive.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

.add_col_28 <- function(tbl, col, type = "TEXT") {
  cols <- dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tbl))$name
  if (!col %in% cols) dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s", tbl, col, type))
}
.add_col_28("Wells", "well_use")
.add_col_28("Wells", "well_status_std")

# ---- status ----
dbExecute(con, "UPDATE Wells SET well_status_std = 'plugged_abandoned'
  WHERE well_status_std IS NULL AND well_id IN
    (SELECT well_id FROM Well_Work_Events WHERE work_type = 'abandonment')")
dbExecute(con, "UPDATE Wells SET well_status_std = CASE
    WHEN lower(well_status) IN ('in use','production','injection','observation','domestic') THEN 'in_use'
    WHEN lower(well_status) LIKE 'shut%' THEN 'shut_in'
    WHEN lower(well_status) = 'idle' THEN 'idle'
    WHEN lower(well_status) IN ('p&a','plugged and abandoned','plugged & abandoned') THEN 'plugged_abandoned'
    WHEN lower(well_status) = 'abandoned' THEN 'abandoned_unplugged'
    END
  WHERE well_status_std IS NULL AND well_status IS NOT NULL")

# ---- use: named cases first, then name patterns, then role ----
dbExecute(con, "UPDATE Wells SET well_use = 'eruption_pipe'      WHERE well_use IS NULL AND well_name = 'SBW_0003'")
dbExecute(con, "UPDATE Wells SET well_use = 'abandoned_unmarked' WHERE well_use IS NULL AND well_name = 'SBW_0001'")
dbExecute(con, "UPDATE Wells SET well_use = 'resort_spa'         WHERE well_use IS NULL AND well_name = 'SBW_0002'")
dbExecute(con, "UPDATE Wells SET well_use = 'historical_exploration'
  WHERE well_use IS NULL AND (well_name LIKE 'GS-%' OR well_name LIKE 'Auger Hole%')")
dbExecute(con, "UPDATE Wells SET well_use = 'stratigraphic_test'
  WHERE well_use IS NULL AND (lower(well_name) LIKE 'strat %' OR lower(well_name) LIKE 'strat-%')")
dbExecute(con, "UPDATE Wells SET well_use = 'thermal_gradient'
  WHERE well_use IS NULL AND (well_name LIKE 'TG-%' OR well_name LIKE 'TG %' OR well_name LIKE '%-TG')")
dbExecute(con, "UPDATE Wells SET well_use = CASE well_role
    WHEN 'production' THEN 'production'
    WHEN 'injection'  THEN 'injection'
    WHEN 'monitor'    THEN 'observation'
    WHEN 'domestic'   THEN 'domestic'
    ELSE 'unknown' END
  WHERE well_use IS NULL")
