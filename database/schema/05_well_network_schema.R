#05_well_network_schema
# ------------------------------------------------------------
# Additive schema extension representing the production well ->
# port -> injection well flow network described in Dhakal et al.
# (2025, Stanford GRC) "Forty Years of Production from the Steamboat
# Geothermal Field" -- geothermal fluid produced from multiple
# production wells is commingled at a small number of named
# collection points ("ports": Galena 1/2/3, SB2/3, SBHR per that
# diagram) before being routed on to one or more injection wells.
#
# This was previously undesigned/unbuilt (flagged repeatedly in
# project memory as conversation-only well/coordinate matches with
# nowhere in the schema to actually record the flow relationships).
#
# Sourced immediately after 01-04 (both at initial connection and
# inside the DEMO reset block in run_pipeline.R), mirroring
# 02_conductivity_schema.R's pattern of a single self-contained file
# that both defines structure and seeds what's currently known.
#
# Design:
#   Wells.well_role         -> migration adding a role classification
#                              ('production' | 'injection' | 'monitor'
#                               | 'domestic' | 'unknown') to the
#                              existing Wells table.
#   Well_Aliases             -> a well may be known by more than one
#                              name across sources (Dhakal diagram
#                              labels, UIC permit IDs, historical
#                              GS-numbered wells, NDWR permit owners).
#   Sampling_Ports           -> the named collection/commingling
#                              points themselves. location_id is
#                              nullable: coordinates for these are not
#                              currently known for any port.
#   Production_Port_Links     -> many production wells -> one port.
#   Port_Injection_Links      -> one port -> many injection wells.
#   vw_well_flow_network      -> convenience view chaining production
#                              well -> port -> injection well.
#
# Both link tables carry valid_from/valid_to (TEXT, nullable) because
# Ormat's actual routing is an operational choice that can be
# reconfigured over time -- the Dhakal (2025) diagram is a snapshot,
# not necessarily a permanent wiring diagram. valid_to = NULL means
# "still in effect as of the citing source" / unknown end date, not
# necessarily "currently active today."
#
# IMPORTANT: well_role is enforced only by convention/comments, not a
# cross-table CHECK or trigger (SQLite CHECK constraints cannot
# reference other tables) -- Production_Port_Links.well_id is
# *expected* to reference a Wells row with well_role = 'production',
# and Port_Injection_Links.well_id likewise 'injection'. Nothing in
# the schema currently stops a mismatched insert; if this becomes a
# real risk (e.g. once register_well_network.R has more than a
# handful of manually-curated rows), consider a qc script check
# alongside the existing scripts/qc/ scripts rather than a trigger.
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# MIGRATION: Wells.well_role
# -----------------------
wells_cols <- dbListFields(con, "Wells")
if (!"well_role" %in% wells_cols) {
  message("[MIGRATION] Wells.well_role missing -- adding (default 'unknown').")
  dbExecute(con, "
    ALTER TABLE Wells ADD COLUMN well_role TEXT
      CHECK (well_role IN ('production', 'injection', 'monitor', 'domestic', 'unknown'))
      DEFAULT 'unknown'
  ")
  dbExecute(con, "UPDATE Wells SET well_role = 'unknown' WHERE well_role IS NULL")
}

# -----------------------
# MIGRATION: Wells coordinate provenance (mirrors Locations.coordinate_source
# / coordinate_uncertainty_m added in 04_photo_location_schema.R). Needed so
# register_well_coordinates.R (below) can record *how* a well's lat/lon was
# resolved (e.g. NBMG Geothermal_Wells exact-name match, with the apino
# permit id) directly alongside the coordinate, the same way Locations does.
# -----------------------
wells_cols <- dbListFields(con, "Wells")
if (!"coordinate_source" %in% wells_cols) {
  message("[MIGRATION] Wells.coordinate_source/coordinate_uncertainty_m/notes missing -- adding.")
  dbExecute(con, "ALTER TABLE Wells ADD COLUMN coordinate_source TEXT")
  dbExecute(con, "ALTER TABLE Wells ADD COLUMN coordinate_uncertainty_m REAL")
  dbExecute(con, "ALTER TABLE Wells ADD COLUMN notes TEXT")
}

# -----------------------
# WELL ALIASES
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Aliases (
  alias_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  alias_type TEXT CHECK (
    alias_type IN ('dhakal_diagram', 'uic_permit', 'historical_gs_number', 'ndwr_permit', 'other')
  ),
  source TEXT,
  notes TEXT,
  UNIQUE (well_id, alias),
  FOREIGN KEY (well_id) REFERENCES Wells(well_id)
);
")

# -----------------------
# SAMPLING PORTS
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Sampling_Ports (
  port_id INTEGER PRIMARY KEY,
  port_name TEXT UNIQUE NOT NULL,
  port_type TEXT CHECK (
    port_type IN ('separator_station', 'pipeline_header', 'collection_point', 'other')
  ) DEFAULT 'other',
  location_id INTEGER,
  source TEXT,
  notes TEXT,
  FOREIGN KEY (location_id) REFERENCES Locations(location_id)
);
")

# -----------------------
# PRODUCTION WELL -> PORT
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Production_Port_Links (
  link_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL,      -- expected well_role = 'production'
  port_id INTEGER NOT NULL,
  valid_from TEXT,
  valid_to TEXT,                 -- NULL = open-ended / unknown end
  source TEXT,
  notes TEXT,
  UNIQUE (well_id, port_id, valid_from),
  FOREIGN KEY (well_id) REFERENCES Wells(well_id),
  FOREIGN KEY (port_id) REFERENCES Sampling_Ports(port_id)
);
")

# -----------------------
# PORT -> INJECTION WELL
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Port_Injection_Links (
  link_id INTEGER PRIMARY KEY,
  port_id INTEGER NOT NULL,
  well_id INTEGER NOT NULL,      -- expected well_role = 'injection'
  valid_from TEXT,
  valid_to TEXT,
  source TEXT,
  notes TEXT,
  UNIQUE (port_id, well_id, valid_from),
  FOREIGN KEY (port_id) REFERENCES Sampling_Ports(port_id),
  FOREIGN KEY (well_id) REFERENCES Wells(well_id)
);
")

# -----------------------
# INDEXES
# -----------------------
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_well_aliases_well ON Well_Aliases(well_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ports_location ON Sampling_Ports(location_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prod_links_well ON Production_Port_Links(well_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prod_links_port ON Production_Port_Links(port_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_inj_links_port ON Port_Injection_Links(port_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_inj_links_well ON Port_Injection_Links(well_id)")

# -----------------------
# SEED: the five named ports from the Dhakal et al. (2025) diagram
# -----------------------
# No coordinates are known for any of these yet (location_id left
# NULL); port_type is provisionally 'other' since the diagram's own
# terminology for each point (separator vs. header vs. simple
# junction) hasn't been re-checked against the source figure.
# Corrected 2026-09-05 (session 8): originally seeded as six ports,
# splitting "SB2"/"SB3" as separate entries by name-pattern guesswork.
# Dhakal et al. (2025) Figure 5 and the user's own digitized power-plant
# polygon (Steamboat_power_plant_locations.shp) both show ONE combined
# port literally named "SB2/3" -- corrected to match. Any pre-existing
# database that still has separate "SB2"/"SB3" rows needs a manual
# migration (see register_well_network.R's port-merge step, run once).
dhakal_ports <- c("Galena 1", "Galena 2", "Galena 3", "SB2/3", "SBHR")
for (p in dhakal_ports) {
  dbExecute(con, "
    INSERT OR IGNORE INTO Sampling_Ports (port_name, port_type, source, notes)
    VALUES (?, 'other', 'Dhakal et al. (2025), Stanford GRC, ''Forty Years of Production from the Steamboat Geothermal Field'' (flow diagram)',
            'Seeded by 05_well_network_schema.R. Coordinates and precise port_type not yet resolved -- see docs/literature/ for the source figure.')
  ", params = list(p))
}

# -----------------------
# SEED: three confirmed injection-well aliases
# -----------------------
# Confirmed via NDEP's own Temporary UIC Permit UNEV2007204T2025-1
# REVISED (June 2025), which explicitly lists these alias pairs --
# the strongest-sourced well identities in this network so far.
# Canonical Wells rows are created here with well_role='injection' and
# no coordinates (not yet resolved); register_well_network.R (run
# after this schema file, per run_pipeline.R) is where any future,
# less-certain matches from data/raw/wells/*.csv get layered in
# without touching these.
confirmed_injection_aliases <- data.frame(
  canonical_name = c("45-28", "35-28", "46-28"),
  alias          = c("IW-1", "IW-4", "IW-5"),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(confirmed_injection_aliases))) {
  wname <- confirmed_injection_aliases$canonical_name[i]
  alias <- confirmed_injection_aliases$alias[i]

  existing_well <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(wname))

  if (nrow(existing_well) == 0) {
    dbExecute(con, "
      INSERT INTO Wells (well_name, well_role)
      VALUES (?, 'injection')
    ", params = list(wname))
    well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
  } else {
    well_id <- existing_well$well_id[1]
  }

  dbExecute(con, "
    INSERT OR IGNORE INTO Well_Aliases (well_id, alias, alias_type, source, notes)
    VALUES (?, ?, 'uic_permit',
            'NDEP Temporary UIC Permit UNEV2007204T2025-1 REVISED (June 2025)',
            'Confirmed injection-well alias, seeded by 05_well_network_schema.R.')
  ", params = list(well_id, alias))
}

# -----------------------
# -----------------------
# VIEWS: flow network, as separate segments
# -----------------------
# Redesigned 2026-09-05 (session 8) after confirming with the project
# owner that injection wells structurally do NOT have a "port" the way
# production wells do -- fluid flows FROM a port INTO an injection
# well, but there is no per-injection-well port assignment to fill in
# (unlike production wells, which do commingle at a specific named
# port). The original single vw_well_flow_network required a
# Production_Port_Link AND a matching Port_Injection_Link for the same
# port to produce any row -- with zero Port_Injection_Links rows (by
# design, not a data gap), that view could only ever return 0 rows,
# which is a dead end for visualization even though real
# production -> port connections exist today.
#
# Split into two independently-useful segments instead:
#   vw_production_to_port  -- production well -> port. Real data now
#                             (Production_Port_Links is populated).
#   vw_port_to_injection    -- port -> injection well. Will be empty
#                             until/unless a genuine port-level
#                             injection assignment is identified (a
#                             different kind of evidence than a
#                             per-well "port_name" column -- e.g. a
#                             diagram that draws that specific arrow).
# vw_well_flow_network is kept as the full chained view (both legs
# confirmed) for whenever that cardinality is real; it is expected to
# legitimately stay empty given the "wont have ports" structural
# note above, and that is fine -- it documents the intended full-chain
# shape rather than something actively broken.
dbExecute(con, "DROP VIEW IF EXISTS vw_well_flow_network")
dbExecute(con, "DROP VIEW IF EXISTS vw_production_to_port")
dbExecute(con, "DROP VIEW IF EXISTS vw_port_to_injection")

dbExecute(con, "
CREATE VIEW vw_production_to_port AS
SELECT
  pw.well_id     AS production_well_id,
  pw.well_name   AS production_well_name,
  sp.port_id,
  sp.port_name,
  ppl.valid_from,
  ppl.valid_to,
  ppl.source,
  ppl.notes
FROM Production_Port_Links ppl
JOIN Wells pw          ON pw.well_id = ppl.well_id
JOIN Sampling_Ports sp ON sp.port_id = ppl.port_id
")

dbExecute(con, "
CREATE VIEW vw_port_to_injection AS
SELECT
  sp.port_id,
  sp.port_name,
  iw.well_id     AS injection_well_id,
  iw.well_name   AS injection_well_name,
  pil.valid_from,
  pil.valid_to,
  pil.source,
  pil.notes
FROM Port_Injection_Links pil
JOIN Sampling_Ports sp ON sp.port_id = pil.port_id
JOIN Wells iw          ON iw.well_id = pil.well_id
")

dbExecute(con, "
CREATE VIEW vw_well_flow_network AS
SELECT
  pw.well_id            AS production_well_id,
  pw.well_name          AS production_well_name,
  sp.port_id,
  sp.port_name,
  iw.well_id            AS injection_well_id,
  iw.well_name          AS injection_well_name,
  ppl.valid_from        AS production_valid_from,
  ppl.valid_to          AS production_valid_to,
  pil.valid_from        AS injection_valid_from,
  pil.valid_to          AS injection_valid_to,
  ppl.source            AS production_link_source,
  pil.source            AS injection_link_source
FROM Production_Port_Links ppl
JOIN Wells pw           ON pw.well_id = ppl.well_id
JOIN Sampling_Ports sp  ON sp.port_id = ppl.port_id
JOIN Port_Injection_Links pil ON pil.port_id = sp.port_id
JOIN Wells iw            ON iw.well_id = pil.well_id
")

message("[SCHEMA] Well network schema ready (Wells.well_role, Well_Aliases, Sampling_Ports, Production_Port_Links, Port_Injection_Links, vw_production_to_port, vw_port_to_injection, vw_well_flow_network).")
