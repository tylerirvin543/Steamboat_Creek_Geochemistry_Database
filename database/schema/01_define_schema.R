#01_define_schema
library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via index.Rmd or orchestrator.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# CORE LOOKUP TABLES
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Ingest_Run_Log (
  ingest_run_id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  data_source TEXT NOT NULL,
  script_name TEXT NOT NULL,
  locations_inserted INTEGER DEFAULT 0,
  events_inserted INTEGER DEFAULT 0,
  samples_inserted INTEGER DEFAULT 0,
  measurements_inserted INTEGER DEFAULT 0,
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Data_Sources (
  source_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  citation TEXT,
  url TEXT,
  notes TEXT
);
")

# ------------------------------------------------------------
# MIGRATION: Data_Sources uniqueness on name
#
# Every ingest script registers its source with
# 'INSERT OR IGNORE INTO Data_Sources (name, ...)', which is only
# idempotent if a UNIQUE constraint/index exists for SQLite to
# ignore-on-conflict against. Data_Sources.name was never declared
# UNIQUE, so every pipeline run silently inserted a fresh duplicate
# row per source (confirmed 2026-09-05: 14 duplicate 'Nevada DEP
# Water Quality Portal' rows, 6 duplicate 'Elitech LogEt 8', etc.).
# This migration is additive and safe to run on a database that
# already has duplicates: it first collapses each name to its
# lowest source_id (repointing any Lab_Analyses/etc. rows that
# reference a soon-to-be-removed duplicate id), then creates the
# UNIQUE index so INSERT OR IGNORE actually works from here on.
# No-op on a fresh database (nothing to dedupe, index just gets
# created).
# ------------------------------------------------------------
has_unique_index <- nrow(dbGetQuery(con, "
  SELECT name FROM sqlite_master
  WHERE type = 'index' AND tbl_name = 'Data_Sources' AND name = 'idx_data_sources_name_unique'
")) > 0

if (!has_unique_index) {
  dup_map <- dbGetQuery(con, "
    SELECT name, MIN(source_id) AS keep_id
    FROM Data_Sources
    GROUP BY name
    HAVING COUNT(*) > 1
  ")

  if (nrow(dup_map) > 0) {
    message("[MIGRATION] Collapsing ", nrow(dup_map), " duplicate Data_Sources name(s) before adding UNIQUE index")
    for (i in seq_len(nrow(dup_map))) {
      keep_id <- dup_map$keep_id[i]
      dup_ids <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ? AND source_id != ?",
                             params = list(dup_map$name[i], keep_id))$source_id
      if (length(dup_ids) > 0) {
        placeholders <- paste(rep("?", length(dup_ids)), collapse = ",")
        for (tbl in c("Lab_Analyses", "Field_Measurements")) {
          if (dbExistsTable(con, tbl) && "source_id" %in% dbListFields(con, tbl)) {
            dbExecute(con, paste0("UPDATE ", tbl, " SET source_id = ? WHERE source_id IN (", placeholders, ")"),
                      params = c(list(keep_id), as.list(dup_ids)))
          }
        }
        dbExecute(con, paste0("DELETE FROM Data_Sources WHERE source_id IN (", placeholders, ")"),
                  params = as.list(dup_ids))
      }
    }
  }

  dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS idx_data_sources_name_unique ON Data_Sources(name)")
  message("[MIGRATION] Data_Sources.name is now UNIQUE-indexed")
}
#######
#Grey out for first run of ndep only
#######
#dbExecute(con, "
#CREATE TABLE IF NOT EXISTS Chemistry_Parameters (
  #parameter TEXT PRIMARY KEY,
  #phreeqc_name TEXT,
  #charge INTEGER,
  #molar_mass REAL,
  #role TEXT
#);
#")

dbExecute(con, "CREATE TABLE IF NOT EXISTS QC_Summary (
  qc_run_date TEXT,
  total_samples INTEGER,
  samples_missing_pH INTEGER,
  samples_missing_temperature INTEGER,
  samples_missing_major_ions INTEGER,
  samples_charge_imbalance INTEGER,
  samples_alkalinity_mismatch INTEGER
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Logger_Files_Processed (
  file_name TEXT PRIMARY KEY,
  processed_time TEXT
)
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Logger_Station_Map (
  logger_id INTEGER,
  station_id TEXT
)
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS USGS_Stations (
  station_id TEXT PRIMARY KEY,
  latitude REAL,
  longitude REAL
)
")

# -----------------------
# CORE ENTITY TABLES
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Locations (
  location_id INTEGER PRIMARY KEY,
  external_station_code TEXT UNIQUE,
  name TEXT NOT NULL,
  latitude REAL,
  longitude REAL,
  coord_key TEXT,
  elevation_m REAL,
  geom TEXT,
  crs TEXT NOT NULL,
  site_type TEXT CHECK (
    site_type IN ('spring', 'creek', 'well', 'background', 'fumarole', 'seep', 'steaming ground', 'transect')
  ),
  notes TEXT
);
")

# ------------------------------------------------------------
# MIGRATION: Locations.coord_key
#
# coord_key is defined in the CREATE TABLE above, but CREATE TABLE IF
# NOT EXISTS never adds columns to an already-existing table -- any
# operational database created before this column was added to the
# schema silently never got it, even though every view/ingest script
# that references Locations.coord_key (create_gis_views.R,
# create_analysis_views.R, ingest_field.R, ingest_ndwr.R, ...) assumes
# it exists. This block is a no-op once the column is present, and
# backfills it from lat/lon (matching the convention used everywhere
# else in the codebase: paste0(latitude, "_", longitude)) for any
# database that predates this fix.
# ------------------------------------------------------------
loc_cols <- dbListFields(con, "Locations")
if (!"coord_key" %in% loc_cols) {
  message("[MIGRATION] Locations.coord_key missing -- adding and backfilling from lat/lon.")
  dbExecute(con, "ALTER TABLE Locations ADD COLUMN coord_key TEXT")
  dbExecute(con, "
    UPDATE Locations
    SET coord_key = latitude || '_' || longitude
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
  ")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Sampling_Events (
  event_id INTEGER PRIMARY KEY,
  external_event_id TEXT UNIQUE,
  date TEXT NOT NULL,
  purpose TEXT CHECK (
    purpose IN ('baseline', 'post-eruption', 'reconnaissance', 'historical')
  ),
  weather_conditions TEXT,
  observer TEXT,
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Samples (
  sample_id INTEGER PRIMARY KEY,
  location_id INTEGER NOT NULL,
  event_id INTEGER NOT NULL,
  sample_type TEXT,
  collection_time TEXT,
  filtered INTEGER,
  preservation_method TEXT,
  notes TEXT,
  external_event_id TEXT,
  external_sample_id TEXT UNIQUE,
  data_source TEXT,
  FOREIGN KEY(location_id) REFERENCES Locations(location_id),
  FOREIGN KEY(event_id) REFERENCES Sampling_Events(event_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Temperature_Loggers (
  logger_id INTEGER PRIMARY KEY,
  logger_name TEXT,
  manufacturer TEXT,
  model TEXT,
  serial_number TEXT UNIQUE NOT NULL,
  location_id INTEGER,
  deployment_start DATETIME,
  deployment_end DATETIME,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN (
      'active',
      'retrieved',
      'destroyed',
      'lost',
      'standby'
    )),
  notes TEXT,
  CHECK (
    status = 'standby' OR location_id IS NOT NULL
  ),
  FOREIGN KEY (location_id)
    REFERENCES Locations(location_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Photos (
  photo_id INTEGER PRIMARY KEY,
  photo_filename TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  
  external_station_code TEXT NOT NULL,
  sample_id TEXT,
  event_id INTEGER,
  
  taken_time TEXT,
  latitude REAL,
  longitude REAL,
  elevation_m REAL,
  crs TEXT NOT NULL,

  
  device TEXT,
  notes TEXT,
  
  FOREIGN KEY (external_station_code)
  REFERENCES Locations(external_station_code),
  
  FOREIGN KEY (sample_id)
  REFERENCES Samples(external_sample_id),
  
  FOREIGN KEY (event_id)
  REFERENCES Sampling_Events(event_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS External_Location_Map (
  map_id INTEGER PRIMARY KEY,
  location_id INTEGER NOT NULL,
  external_id TEXT NOT NULL,
  source_system TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (location_id) REFERENCES Locations(location_id),
  UNIQUE(external_id, source_system)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Wells (
  well_id INTEGER PRIMARY KEY,
  ndwr_site_id TEXT UNIQUE,

  well_name TEXT,
  owner TEXT,

  latitude REAL,
  longitude REAL,
  coord_key TEXT,
  elevation_m REAL,

  total_depth REAL,
  top_perforation REAL,
  bottom_perforation REAL,
  mid_screen_depth REAL,

  basin TEXT,
  basin_name TEXT,

  location_id INTEGER,

  FOREIGN KEY (location_id)
    REFERENCES Locations(location_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Water_Level_Observations (
  observation_id INTEGER PRIMARY KEY,

  well_id INTEGER NOT NULL,
  timestamp TEXT NOT NULL,
  coord_key TEXT,

  depth_to_water REAL,
  water_level_elevation REAL,

  method TEXT,          -- raw (T, F)
  method_type TEXT,     -- interpreted (manual, transducer)

  notes TEXT,

  UNIQUE (well_id, timestamp, method),

  FOREIGN KEY (well_id)
    REFERENCES Wells(well_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS USGS_Timeseries (
  station_id TEXT,
  datetime TEXT,
  parameter_code TEXT,
  value REAL,
  unit TEXT,
  status TEXT,
  last_modified TEXT,
  source_file TEXT,
  
  PRIMARY KEY (station_id, datetime, parameter_code)
);
")

# -----------------------
# MEASUREMENTS
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Temperature_Observations (
  observation_id INTEGER PRIMARY KEY,
  logger_id INTEGER NOT NULL,
  timestamp TEXT NOT NULL,
  temperature REAL NOT NULL,
  units TEXT DEFAULT 'deg C',
  status TEXT,
  source_id INTEGER,

  FOREIGN KEY (logger_id) REFERENCES Temperature_Loggers(logger_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
")


dbExecute(con, "
CREATE TABLE IF NOT EXISTS Field_Measurements (
  measurement_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  parameter TEXT,
  value REAL NOT NULL,
  units TEXT,
  instrument TEXT,
  source_id INTEGER,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Lab_Analyses (
  analysis_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  analyte TEXT NOT NULL,
  value REAL,
  units TEXT,
  fraction TEXT,
  method TEXT,
  detection_limit REAL,
  qualifier TEXT,
  source_id INTEGER,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Isotope_Analyses (
  isotope_id INTEGER PRIMARY KEY,
  sample_id INTEGER,
  analyte TEXT,     -- 'd18O', 'dD'
  value REAL,
  units TEXT DEFAULT 'permil',
  standard TEXT DEFAULT 'VSMOW',
  source_id INTEGER,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
")

#------------------------
#Enforce Uniqueness in Schema
#------------------------
dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_sampling_events_external_id
ON Sampling_Events (external_event_id);
")

dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_samples_unique
ON Samples (external_sample_id);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_samples_location
ON Samples(location_id);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_water_levels_time
ON Water_Level_Observations(timestamp);
")

dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_field_measurements_unique
ON Field_Measurements (sample_id, parameter, source_id);
")

dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_lab_unique
ON Lab_Analyses (sample_id, analyte, fraction, source_id);
")

dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_temp_obs_unique
ON Temperature_Observations (logger_id, timestamp);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_samples_time
ON Samples(collection_time);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_temp_obs_time 
ON Temperature_Observations(timestamp);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_usgs_time
ON USGS_Timeseries(datetime)
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_usgs_station_time
ON USGS_Timeseries(station_id, datetime)
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_logger_location
ON Temperature_Loggers(location_id);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_lab_analyte
ON Lab_Analyses(analyte);
")

# -----------------------
# STAGING TABLE
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Staging_NDEP_WQ (
  station_name TEXT,
  latitude REAL,
  longitude REAL,
  sample_date TEXT,
  analyte TEXT,
  value REAL,
  units TEXT,
  method TEXT,
  detection_limit REAL,
  raw_source_file TEXT
);
")
