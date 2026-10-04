## scripts/ingest/extract_well_production_history.R
##
## Extracts structured production/injection-well operating snapshots
## from the free-text "[<document>, Table 2: Well Summary During
## Tracer Flow Testing, tracer test date <date>.] Well '<name>'
## (<type>): status <status>, flow <value> <unit>, enthalpy
## temperature <NA|value> F, wellhead temperature <value> F, wellhead
## pressure <value> psig -- '<comment>'." entries already transcribed
## into Wells.notes (NDEP PRR TFT Compliance Report Table 2, see
## AGENTS.md Session 42/43 addenda). No new document is read here --
## this is a structured distillation of data already in the database.
##
## well_id is taken directly from the Wells row being scanned (not
## re-resolved by name), which sidesteps any well_name/canonical_name
## mismatch (e.g. the '23-33' vs '23-33RD' naming difference).
## Idempotent on (well_id, parameter, document_date, document_name).

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
})

.well_production_pattern <- paste0(
  "\\[([^]]*?), Table 2: Well Summary During Tracer Flow Testing, ",
  "tracer test date (\\d{4}-\\d{2}-\\d{2})\\.\\] Well '([^']+)' ",
  "\\((Production|Injection)\\): status ([^,]+), flow ([\\d.]+) (\\w+), ",
  "enthalpy temperature (NA|[\\d.]+) F, wellhead temperature ([\\d.]+) F, ",
  "wellhead pressure ([\\d.]+) psig -- '([^']+)'\\."
)

.parse_well_production_notes <- function(well_id, notes) {
  if (is.na(notes) || !grepl("Table 2: Well Summary During Tracer Flow Testing", notes, fixed = TRUE)) {
    return(NULL)
  }

  m <- gregexpr(.well_production_pattern, notes, perl = TRUE)
  matched_text <- regmatches(notes, m)[[1]]

  if (length(matched_text) == 0) {
    warning("[WELL PRODUCTION HISTORY] well_id ", well_id,
            ": notes mention 'Table 2: Well Summary During Tracer Flow Testing' ",
            "but did not fully match the expected pattern -- skipped. Check format.")
    return(NULL)
  }

  m2 <- regexec(.well_production_pattern, matched_text, perl = TRUE)
  groups <- regmatches(matched_text, m2)

  rows <- lapply(groups, function(g) {
    document_name <- g[2]
    document_date <- g[3]
    well_name <- g[4]
    well_type <- g[5]
    status <- trimws(g[6])
    flow_value <- suppressWarnings(as.numeric(g[7]))
    flow_unit <- g[8]
    enthalpy_temp <- if (g[9] == "NA") NA_real_ else suppressWarnings(as.numeric(g[9]))
    wellhead_temp <- suppressWarnings(as.numeric(g[10]))
    wellhead_pressure <- suppressWarnings(as.numeric(g[11]))
    comment <- g[12]

    tibble::tibble(
      well_id = well_id,
      well_name = well_name,
      well_type = well_type,
      status = status,
      parameter = c("flow", "enthalpy_temperature_f", "wellhead_temperature_f", "wellhead_pressure_psig"),
      value = c(flow_value, enthalpy_temp, wellhead_temp, wellhead_pressure),
      unit = c(flow_unit, "F", "F", "psig"),
      comment = comment,
      document_name = document_name,
      document_date = document_date
    )
  })

  dplyr::bind_rows(rows)
}

extract_well_production_history <- function(con) {
  wells <- DBI::dbGetQuery(con, "SELECT well_id, notes FROM Wells WHERE notes IS NOT NULL")

  parsed <- dplyr::bind_rows(
    lapply(seq_len(nrow(wells)), function(i) {
      .parse_well_production_notes(wells$well_id[i], wells$notes[i])
    })
  )

  if (nrow(parsed) == 0) {
    message("[WELL PRODUCTION HISTORY] No Table 2 entries found in Wells.notes -- nothing to extract.")
    return(invisible(NULL))
  }

  existing <- DBI::dbGetQuery(con, "
    SELECT well_id, parameter, document_date, document_name FROM Well_Production_History
  ")

  to_insert <- parsed %>%
    dplyr::anti_join(existing, by = c("well_id", "parameter", "document_date", "document_name"))

  if (nrow(to_insert) == 0) {
    message("[WELL PRODUCTION HISTORY] 0 new rows (already extracted).")
    return(invisible(NULL))
  }

  DBI::dbWriteTable(con, "Well_Production_History", to_insert, append = TRUE, row.names = FALSE)
  message("[WELL PRODUCTION HISTORY] Inserted ", nrow(to_insert), " new row(s) from ",
          length(unique(parsed$well_id)), " well(s), ", length(unique(parsed$document_date)), " document date(s).")
  invisible(to_insert)
}
