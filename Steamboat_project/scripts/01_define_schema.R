#01_define_schema
library(DBI)
library(RSQLite)

con <- dbConnect(SQLite(), "geochem_sampling.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# CORE LOOKUP TABLES
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Data_Sources (
  source_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  citation TEXT,
  url TEXT,
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Chemistry_Parameters (
  parameter TEXT PRIMARY KEY,
  phreeqc_name TEXT,
  charge INTEGER,
  molar_mass REAL,
  role TEXT
);
")

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

# -----------------------
# CORE ENTITY TABLES
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Locations (
  location_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  latitude REAL,
  longitude REAL,
  site_type TEXT CHECK (
    site_type IN ('spring', 'creek', 'mixing zone', 'background', 'fumarole')
  ),
  notes TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Sampling_Events (
  event_id INTEGER PRIMARY KEY,
  date TEXT NOT NULL,
  purpose TEXT CHECK (
    purpose IN ('baseline', 'post-eruption', 'reconnaissance', 'historical')
  ),
  weather_conditions TEXT,
  observer TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Samples (
  sample_id INTEGER PRIMARY KEY,
  location_id INTEGER NOT NULL,
  event_id INTEGER NOT NULL,
  sample_type TEXT CHECK (
    sample_type IN ('water', 'gas', 'precipitate')
  ),
  collection_time TEXT,
  filtered INTEGER CHECK (filtered IN (0,1)),
  preservation_method TEXT,

  FOREIGN KEY (location_id) REFERENCES Locations(location_id),
  FOREIGN KEY (event_id) REFERENCES Sampling_Events(event_id)
);
")

# -----------------------
# MEASUREMENTS
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Field_Measurements (
  measurement_id INTEGER PRIMARY KEY,
  sample_id INTEGER NOT NULL,
  parameter TEXT NOT NULL,
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
  method TEXT,
  detection_limit REAL,
  source_id INTEGER,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
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

dbDisconnect(con)