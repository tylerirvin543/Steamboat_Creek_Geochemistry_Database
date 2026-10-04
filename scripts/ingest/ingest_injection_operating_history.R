## scripts/ingest/ingest_injection_operating_history.R
##
## Ingests injection-well wellhead pressure and injection-rate history
## transcribed from NDEP UIC permits/temporary permits (currently just
## data/raw/ndep/injection_pressure_rate_history.csv, from Temporary
## UIC Permit UNEV2007204T2025-1, issued 2025-05-30 -- an increase in
## the field's combined injection-rate limit from 49,500 to 55,000 gpm
## for IW-1, IW-4, IW-5, IW-6, 21-32, 42A-32, and 64A-32).
##
## Idempotent on (well_name, parameter, metric_type, document_date,
## document_name) via anti_join. well_id is resolved via an exact
## Wells.well_name match on canonical_well_name, falling back to
## Well_Aliases; left NULL (never guessed) when no match exists.
##
## Future NDEP permits/reports with the same table structure should be
## transcribed into new rows appended to the same CSV (or a sibling
## CSV read by the same function), not a new ad hoc script.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(readr)
})

ingest_injection_operating_history <- function(con, csv_path = "data/raw/ndep/injection_pressure_rate_history.csv") {
  if (!file.exists(csv_path)) {
    message("[INJECTION OPERATING HISTORY] No source file at ", csv_path, " -- skipping.")
    return(invisible(NULL))
  }

  raw <- readr::read_csv(csv_path, col_types = readr::cols(.default = "c"))

  raw <- raw %>%
    dplyr::mutate(
      value = suppressWarnings(as.numeric(value)),
      value_min = suppressWarnings(as.numeric(value_min)),
      value_max = suppressWarnings(as.numeric(value_max))
    )

  # Resolve well_id: exact Wells.well_name match on canonical_well_name,
  # else Well_Aliases, else NULL (never guessed/fabricated).
  wells <- DBI::dbGetQuery(con, "SELECT well_id, well_name FROM Wells")
  aliases <- DBI::dbGetQuery(con, "SELECT well_id, alias FROM Well_Aliases")

  resolve_well_id <- function(canon) {
    if (is.na(canon) || canon == "") return(NA_integer_)
    hit <- wells$well_id[wells$well_name == canon]
    if (length(hit) == 1) return(hit)
    hit <- aliases$well_id[aliases$alias == canon]
    if (length(hit) == 1) return(hit)
    NA_integer_
  }
  raw$well_id <- vapply(raw$canonical_well_name, resolve_well_id, integer(1))
  n_unresolved <- sum(is.na(raw$well_id) & raw$canonical_well_name != "TOTAL")
  if (n_unresolved > 0) {
    message("[INJECTION OPERATING HISTORY] ", n_unresolved,
            " row(s) have no matching Wells/Well_Aliases record -- well_id left NULL for those.")
  }

  existing <- DBI::dbGetQuery(con, "
    SELECT well_name, parameter, metric_type, document_date, document_name
    FROM Injection_Operating_History
  ")

  to_insert <- raw %>%
    dplyr::anti_join(existing, by = c("well_name", "parameter", "metric_type", "document_date", "document_name")) %>%
    dplyr::select(well_id, well_name, canonical_well_name, parameter, metric_type,
                   value, value_min, value_max, unit, status,
                   document_name, document_date, permit_number, notes)

  if (nrow(to_insert) == 0) {
    message("[INJECTION OPERATING HISTORY] 0 new rows (already ingested).")
    return(invisible(NULL))
  }

  DBI::dbWriteTable(con, "Injection_Operating_History", to_insert, append = TRUE, row.names = FALSE)
  message("[INJECTION OPERATING HISTORY] Inserted ", nrow(to_insert), " new row(s) from ", csv_path)
  invisible(to_insert)
}
