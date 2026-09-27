# ============================================================
# register_location_aliases.R
#
# Purpose:
# Registers real Location_Aliases rows from a human-maintained CSV
# (data/raw/locations/location_aliases.csv: canonical_name, alias,
# alias_type, source, notes). Mirrors register_well_network.R's own
# idempotency philosophy exactly: only ever adds a new alias row,
# never updates or deletes an existing one. `canonical_name` is
# resolved against Locations.name OR Locations.external_station_code
# (whichever matches) -- a row whose canonical_name can't be resolved
# warns and is skipped, never guessed.
#
# Usage:
#   source("scripts/ingest/register_location_aliases.R")
#   register_location_aliases(con)
# ============================================================

library(DBI)
library(readr)
library(dplyr)

register_location_aliases <- function(con, aliases_csv = "data/raw/locations/location_aliases.csv") {
  if (!file.exists(aliases_csv)) {
    message("[location_aliases] No file at ", aliases_csv, " -- nothing to register.")
    return(invisible(0L))
  }

  rows <- readr::read_csv(aliases_csv, show_col_types = FALSE,
                           col_types = readr::cols(.default = readr::col_character()))

  existing <- DBI::dbGetQuery(con, "SELECT location_id, alias FROM Location_Aliases")

  n_added <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    loc <- DBI::dbGetQuery(con, "
      SELECT location_id FROM Locations WHERE name = ? OR external_station_code = ?
    ", params = list(r$canonical_name[1], r$canonical_name[1]))

    if (nrow(loc) == 0) {
      warning("[location_aliases] canonical_name '", r$canonical_name[1],
              "' not found in Locations (name or external_station_code) -- skipping alias '",
              r$alias[1], "'.")
      next
    }
    location_id <- loc$location_id[1]

    already <- existing$alias[existing$location_id == location_id] == r$alias[1]
    if (any(already, na.rm = TRUE)) next  # idempotent: already registered

    DBI::dbExecute(con, "
      INSERT INTO Location_Aliases (location_id, alias, alias_type, source, notes)
      VALUES (?, ?, ?, ?, ?)
    ", params = list(location_id, r$alias[1], r$alias_type[1], r$source[1], r$notes[1]))
    n_added <- n_added + 1L
  }

  message("[location_aliases] Registered ", n_added, " new alias(es) (",
          nrow(rows) - n_added, " already present or skipped).")
  invisible(n_added)
}
