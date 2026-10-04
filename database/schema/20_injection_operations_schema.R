# ============================================================
# Schema: Injection operating history (pressure/rate), sourced from
# NDEP UIC permits/temporary permits. Sourced after 01-19.
#
# Purpose: track how injection-well wellhead pressure and injection
# rate limits have changed across successive NDEP UIC permits/
# temporary permits over time -- the concrete data behind the
# question of whether permitted increases in injection pressure/rate
# correlate with (and may have contributed to) the hydrothermal
# changes preceding the Lower Sinter Terrace eruption. Each row is a
# dated, as-reported value transcribed from one specific NDEP
# document; this table accumulates one snapshot per document as more
# permits/reports are read in future sessions, it does not represent
# a continuous time series on its own.
#
# This is deliberately a long, generic (parameter/metric_type/value)
# table rather than per-permit wide columns, since different NDEP
# documents report different metric types (e.g. "historic peak" only
# appears when a rate/pressure increase is being requested).
# ============================================================

.create_injection_operating_history_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Injection_Operating_History (
      record_id INTEGER PRIMARY KEY AUTOINCREMENT,
      well_id INTEGER REFERENCES Wells(well_id),
      well_name TEXT NOT NULL,
      canonical_well_name TEXT,
      parameter TEXT NOT NULL CHECK(parameter IN ('pressure_psig', 'rate_gpm')),
      metric_type TEXT NOT NULL,
      value REAL,
      value_min REAL,
      value_max REAL,
      unit TEXT,
      status TEXT,
      document_name TEXT,
      document_date TEXT,
      permit_number TEXT,
      notes TEXT,
      UNIQUE(well_name, parameter, metric_type, document_date, document_name)
    )
  ")
}

.create_injection_operating_history_table(con)
