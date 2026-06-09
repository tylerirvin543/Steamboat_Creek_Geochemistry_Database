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
