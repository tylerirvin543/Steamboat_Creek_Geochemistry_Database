# 19_location_aliases_schema.R
# ------------------------------------------------------------
# Location_Aliases -- mirrors Well_Aliases's column shape exactly,
# but for Locations. Built 2026-09-26 after confirming SB5
# ("Steamboat Creek @ Rhodes Road," an NDEP StationData.csv station)
# and SBRR (this project's own conductivity-logger location) are the
# same real-world monitoring point, ~12 m apart -- per explicit user
# decision, NOT merged (no location_id re-pointing, no data loss risk):
# both Locations rows stay exactly as they are, and this table records
# which external names/codes refer to the same real point, grouped
# under one canonical location_id.
#
# Real, coordinate-confirmed grouping seeded by
# register_location_aliases.R (data/raw/locations/location_aliases.csv):
# SB5, SB6 ("Steamboat Ditch @ Rhodes Road"), and STBT02Steamboat-2a
# ("Steamboat Creek north of the USGS gage off of Rhodes Road") all
# alias to canonical location_id=78 (SBRR) -- all three sit within
# ~150 m of SBRR and of the co-located USGS gauge (10349300).
#
# Deliberately NOT grouped (explicitly corrected mid-session by the
# user after an initial wrong guess): SBGG's own location does NOT
# get an SB7 ("Steamboat Creek @ Geiger Grade") alias -- SBGG is this
# project's own new downstream conductivity-logger deployment point, a
# genuinely different physical location from the old NDEP "Geiger
# Grade" station despite the similar naming. SB7 stays its own
# distinct, unaliased Locations row.
# ------------------------------------------------------------

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Location_Aliases (
  alias_id INTEGER PRIMARY KEY,
  location_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  alias_type TEXT CHECK (
    alias_type IN ('ndep_station_code', 'usgs_code', 'other')
  ),
  source TEXT,
  notes TEXT,
  UNIQUE (location_id, alias),
  FOREIGN KEY (location_id) REFERENCES Locations(location_id)
);
")
