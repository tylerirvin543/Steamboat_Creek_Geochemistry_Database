# ============================================================
# location_aliases_helpers.R
#
# Purpose:
# Read-time helper for querying real chemistry across an aliased
# group of Locations (see database/schema/19_location_aliases_schema.R
# and scripts/ingest/register_location_aliases.R) WITHOUT merging or
# re-pointing any underlying row -- a real UNION across every
# location_id in the group, each row still tagged with its own real
# location_id/name/external_station_code, per explicit user decision
# to keep SB5/SB6/STBT02Steamboat-2a and SBRR as separate Locations
# rows grouped only by name.
#
# Usage:
#   source("scripts/analysis/location_aliases_helpers.R")
#   get_location_family_chemistry(con, "SBRR")
# ============================================================

library(DBI)
library(dplyr)

#' Resolve a canonical name (or any of its aliases) to every real
#' location_id in its group, including the canonical location itself.
get_location_family_ids <- function(con, canonical_name) {
  canonical <- DBI::dbGetQuery(con, "
    SELECT location_id FROM Locations WHERE name = ? OR external_station_code = ?
  ", params = list(canonical_name, canonical_name))

  if (nrow(canonical) == 0) {
    # Maybe canonical_name was itself given as an alias -- resolve via Location_Aliases.
    via_alias <- DBI::dbGetQuery(con, "SELECT location_id FROM Location_Aliases WHERE alias = ?",
                                  params = list(canonical_name))
    if (nrow(via_alias) == 0) {
      warning("[location_aliases] '", canonical_name, "' not found as a Locations name/code or an alias.")
      return(integer(0))
    }
    canonical_id <- via_alias$location_id[1]
  } else {
    canonical_id <- canonical$location_id[1]
  }

  # The alias TEXT itself often corresponds to another REAL, separate
  # Locations row with its own real Samples/Lab_Analyses (e.g. SB5 is
  # location_id=10 in its own right) -- not merely an alternate name
  # with no underlying row. Resolve each alias string back to its own
  # real location_id (via name or external_station_code) so its real
  # chemistry is actually included, not just the bare alias string.
  aliases <- DBI::dbGetQuery(con, "SELECT alias FROM Location_Aliases WHERE location_id = ?",
                              params = list(canonical_id))
  aliased_ids <- integer(0)
  for (a in aliases$alias) {
    hit <- DBI::dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ? OR external_station_code = ?",
                            params = list(a, a))
    if (nrow(hit) > 0) aliased_ids <- c(aliased_ids, hit$location_id[1])
  }
  unique(c(canonical_id, aliased_ids))
}

#' Real, combined Samples/Lab_Analyses rows across an aliased location
#' group -- each row still carries its own real location_id/name, so
#' nothing is anonymized or blended; this is a read-time UNION, not a
#' data merge.
get_location_family_chemistry <- function(con, canonical_name) {
  ids <- get_location_family_ids(con, canonical_name)
  if (length(ids) == 0) return(data.frame())

  placeholders <- paste(rep("?", length(ids)), collapse = ",")
  DBI::dbGetQuery(con, sprintf("
    SELECT s.sample_id, l.location_id, l.name AS location_name, l.external_station_code,
           s.collection_time, s.data_source, la.analyte, la.value, la.units
    FROM Samples s
    JOIN Locations l ON l.location_id = s.location_id
    JOIN Lab_Analyses la ON la.sample_id = s.sample_id
    WHERE s.location_id IN (%s)
    ORDER BY s.collection_time
  ", placeholders), params = as.list(ids))
}
