# ============================================================
# Schema: Well production/injection operating history extracted from
# NDEP TFT Compliance Report "Table 2: Well Summary During Tracer Flow
# Testing" entries, which are already transcribed as free text into
# Wells.notes (see AGENTS.md Session 42/43). Sourced after 01-20.
#
# Mirrors Injection_Operating_History's long-format shape (one row per
# well/parameter/document) so both tables can feed the same
# monthly-indicator-timeline code.
# ============================================================

.create_well_production_history_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Well_Production_History (
      record_id INTEGER PRIMARY KEY AUTOINCREMENT,
      well_id INTEGER REFERENCES Wells(well_id),
      well_name TEXT NOT NULL,
      well_type TEXT,
      status TEXT,
      parameter TEXT NOT NULL CHECK(parameter IN (
        'flow', 'enthalpy_temperature_f', 'wellhead_temperature_f', 'wellhead_pressure_psig'
      )),
      value REAL,
      unit TEXT,
      comment TEXT,
      document_name TEXT,
      document_date TEXT,
      source TEXT DEFAULT 'TFT Compliance Report Table 2 (transcribed into Wells.notes)',
      notes TEXT,
      UNIQUE(well_id, parameter, document_date, document_name)
    )
  ")
}

.create_well_production_history_table(con)
