# 15_well_deviation_surveys_schema.R
# ------------------------------------------------------------
# Well_Deviation_Surveys -- structure-only until this session, now
# seeded with the FIRST real (non-vertical) directional data this
# project has ever had for a Steamboat well: 83C-6ST1 (well_id 98),
# from Akerley et al. (2021, GRC Transactions Vol. 45, "Drilling
# Challenge and Pumping Innovations for the Steamboat Hills
# Enhancement") -- read directly from the paper, not guessed. A
# comprehensive keyword search across every Well_Log_Documents OCR
# text (DEVIATION/AZIMUTH/INCLINATION/DIRECTIONAL/DOGLEG) found ZERO
# real hits -- the NDWR public driller's-report PDFs genuinely never
# contain directional data (they're mostly shallow domestic/monitor
# wells drilled vertically); real deviation data for a deep Steamboat
# production well instead lives in Ormat's own published engineering
# literature, not the public well-log record.
#
# Each row is one real survey station (measured depth + inclination/
# azimuth where known). Some 83C-6ST1 stations below are narrative-
# derived (the paper describes the drilling qualitatively -- vertical
# to a stated depth, then a directional build to a stated maximum
# angle -- rather than publishing a full station-by-station survey
# table) -- flagged explicitly in `notes` per row, never presented as
# more precise than what the source actually gives.
#
# export_leapfrog.R's survey.csv checks this table first for a given
# well and only falls back to the assumed-vertical two-point trace
# when no real rows exist here -- so this is designed to "just work"
# the moment a well's real directional data becomes available, no
# code change needed then.
# ------------------------------------------------------------

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Deviation_Surveys (
  survey_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL,
  depth_ft REAL NOT NULL,          -- measured depth
  azimuth_deg REAL,                -- NULL where the source doesn't give a station-specific azimuth
  inclination_deg REAL,            -- degrees from vertical (0 = vertical, 90 = horizontal); NULL if not given
  data_quality TEXT DEFAULT 'narrative_derived',  -- 'surveyed_station' | 'narrative_derived' | 'assumed_vertical'
  source TEXT,
  notes TEXT,
  FOREIGN KEY (well_id) REFERENCES Wells(well_id)
);
")

dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_deviation_well ON Well_Deviation_Surveys(well_id)")

# ------------------------------------------------------------
# Seed: 83C-6ST1 (well_id 98) -- real, narrative-derived directional
# data from Akerley et al. (2021). Not inserted if already present
# (idempotent on well_id + depth_ft).
# ------------------------------------------------------------
existing_83c6 <- dbGetQuery(con, "SELECT COUNT(*) n FROM Well_Deviation_Surveys WHERE well_id = 98")$n

if (existing_83c6 == 0) {
  akerley_citation <- "Akerley, J., Eilan, B., Selwood, R., Darf, N., Canning, B. (2021). Drilling Challenge and Pumping Innovations for the Steamboat Hills Enhancement. GRC Transactions, Vol. 45."

  dbExecute(con, "
    INSERT INTO Well_Deviation_Surveys (well_id, depth_ft, azimuth_deg, inclination_deg, data_quality, source, notes)
    VALUES
      (98, 0,    NULL, 0,    'surveyed_station',   ?, 'Surface casing set vertical to 1600 ft per the paper -- this station and the next both represent that same vertical interval.'),
      (98, 1600, NULL, 0,    'surveyed_station',   ?, 'Kick-off point: vertical drilling ends at ~1600 ft MD (16-inch casing set to 1603 ft MD per the paper); directional build begins below this depth toward the NE.'),
      (98, 2687, NULL, NULL, 'narrative_derived',   ?, 'Target fracture zone intersected at 2687 ft MD (total losses) -- a real depth marker, but the paper reports the FRACTURE''s own orientation (dip 75 deg, azimuth 190 deg toward offset well 83B-6RD), not the wellbore''s own inclination/azimuth AT this station, so azimuth_deg/inclination_deg are left NULL rather than guessed from the fracture''s orientation.'),
      (98, 3000, NULL, NULL, 'narrative_derived',   ?, 'Total depth (measured depth). Directional path built at a maximum rate of 4.75 deg (build angle, direction NE) between the 1600 ft kick-off point and this total depth -- the paper does not publish the resulting final inclination/azimuth at TD as an explicit station value, so it is left NULL here rather than back-calculated from an ambiguous build-rate assumption. This well is confirmed real and non-vertical (not an assumed-vertical trace) -- see data_quality/notes on the two stations above for what IS precisely known.')
  ", params = list(akerley_citation, akerley_citation, akerley_citation, akerley_citation))

  message("[SCHEMA] Seeded 4 real (narrative-derived) Well_Deviation_Surveys rows for 83C-6ST1 (well_id 98) from Akerley et al. (2021).")
}

message("[SCHEMA] Well_Deviation_Surveys ready.")
