# ============================================================
# register_well_network.R
#
# Purpose:
# Human-maintained registration of the Dhakal et al. (2025) well ->
# port -> injection-well flow network (schema: see
# database/schema/05_well_network_schema.R). Reads two small CSVs and
# upserts Wells / Well_Aliases / Sampling_Ports / Production_Port_Links
# / Port_Injection_Links rows from them. Mirrors
# register_monitor_well_locations.R's idempotency philosophy: this
# never overwrites an existing row, only adds new ones, so a manual
# in-database correction (e.g. once a well's real coordinates are
# finally confirmed) is never silently clobbered by a re-run.
#
# Inputs:
#   data/raw/wells/dhakal_well_network.csv
#     columns: well_name, well_role, port_name, valid_from, valid_to,
#              source, notes
#     well_role/port_name may be blank where not yet confirmed (see
#     the file's own notes column for why) -- a blank well_role
#     leaves Wells.well_role at its schema default ('unknown'); a
#     blank port_name means "register the well, but don't create any
#     port link yet."
#   data/raw/wells/well_aliases.csv
#     columns: well_name, alias, alias_type, source, notes
#     well_name must already exist in Wells (either from the network
#     CSV above, from an earlier run, or from some other ingest path)
#     -- rows whose well_name can't be resolved are skipped with a
#     warning, not silently dropped without a trace.
#
# Idempotency:
#   Wells: matched on well_name (trimmed). A well_name already present
#     is left untouched -- well_role is NOT updated on a second run,
#     even if the CSV changes, so a manually-corrected role in the
#     database always wins. Edit the database row directly (and the
#     CSV, for provenance) if a role needs to change.
#   Sampling_Ports: matched on port_name (also enforced by a UNIQUE
#     index), same "insert if new, never update" rule.
#   Production_Port_Links / Port_Injection_Links: matched on
#     (well_id, port_id, valid_from) per the schema's UNIQUE
#     constraint.
#   Well_Aliases: matched on (well_id, alias) per the schema's UNIQUE
#     constraint.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

register_well_network <- function(
    con,
    network_csv = "data/raw/wells/dhakal_well_network.csv",
    aliases_csv = "data/raw/wells/well_aliases.csv") {

  message("---- Registering Dhakal well/port flow network ----")

  # ------------------------------------------------------------
  # ONE-TIME MIGRATION: merge legacy separate "SB2"/"SB3" ports into
  # the single "SB2/3" port. Corrected 2026-09-05 (session 8): the
  # original SB2/SB3 split was a name-pattern guess, not a confirmed
  # design -- Dhakal et al. (2025) Figure 5 and the users own
  # digitized power-plant polygon both show ONE combined port. Safe to
  # re-run: no-ops once "SB2"/"SB3" no longer exist.
  # ------------------------------------------------------------
  legacy_ports <- dbGetQuery(con, "SELECT port_id, port_name FROM Sampling_Ports WHERE port_name IN ('SB2','SB3')")
  if (nrow(legacy_ports) > 0) {
    combined <- dbGetQuery(con, "SELECT port_id FROM Sampling_Ports WHERE port_name = 'SB2/3'")
    if (nrow(combined) == 0) {
      dbExecute(con, "
        INSERT INTO Sampling_Ports (port_name, port_type, source, notes)
        VALUES ('SB2/3', 'other',
                'Dhakal et al. (2025), Stanford GRC, Figure 5',
                'Created by register_well_network.R SB2/SB3 merge migration, 2026-09-05.')
      ")
      combined_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
    } else {
      combined_id <- combined$port_id[1]
    }
    for (legacy_id in legacy_ports$port_id) {
      dbExecute(con, "UPDATE Production_Port_Links SET port_id = ? WHERE port_id = ?",
                params = list(combined_id, legacy_id))
      dbExecute(con, "UPDATE Port_Injection_Links SET port_id = ? WHERE port_id = ?",
                params = list(combined_id, legacy_id))
      dbExecute(con, "DELETE FROM Sampling_Ports WHERE port_id = ?", params = list(legacy_id))
    }
    message("  -> Merged ", nrow(legacy_ports), " legacy SB2/SB3 port row(s) into a single SB2/3 port.")
  }

  wells_registered <- 0L
  ports_registered <- 0L
  prod_links_registered <- 0L
  inj_links_registered <- 0L
  aliases_registered <- 0L

  # ------------------------------------------------------------
  # WELL / PORT / LINK REGISTRATION
  # ------------------------------------------------------------
  if (!file_exists(network_csv)) {
    message("[register well network] No network map at ", network_csv, " -- nothing to register.")
  } else {
    net <- read_csv(network_csv, show_col_types = FALSE) %>%
      mutate(well_name = trimws(well_name)) %>%
      filter(!is.na(well_name), well_name != "") %>%
      distinct(well_name, well_role, port_name, valid_from, valid_to, source, notes)

    for (i in seq_len(nrow(net))) {
      row <- net[i, ]

      # --- Wells: insert if new, never update an existing row ---
      # Check Well_Aliases first: a CSV row using an alias name (e.g.
      # "IW-5" for canonical "46-28") must resolve to the SAME well_id,
      # not create a second, duplicate Wells row under the alias name.
      # (This bug was caught in practice 2026-09-05: three alias rows
      # left in this CSV as pure documentation -- no port_name, nothing
      # to link -- silently created duplicate "IW-1"/"IW-4"/"IW-5"
      # Wells rows alongside the real canonical "45-28"/"35-28"/"46-28"
      # ones. Removed those rows from the CSV *and* added this check so
      # it can't happen again from any future alias-named row.)
      existing_well <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?",
                                   params = list(row$well_name))

      if (nrow(existing_well) == 0) {
        alias_well <- dbGetQuery(con, "
          SELECT w.well_id FROM Well_Aliases a
          JOIN Wells w ON w.well_id = a.well_id
          WHERE a.alias = ?
        ", params = list(row$well_name))
        if (nrow(alias_well) > 0) existing_well <- alias_well
      }

      if (nrow(existing_well) == 0) {
        role <- if (!is.na(row$well_role) && row$well_role != "") row$well_role else "unknown"
        dbExecute(con, "INSERT INTO Wells (well_name, well_role) VALUES (?, ?)",
                  params = list(row$well_name, role))
        well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
        wells_registered <- wells_registered + 1L
      } else {
        well_id <- existing_well$well_id[1]
      }

      # --- No port specified for this row: nothing further to link ---
      if (is.na(row$port_name) || row$port_name == "") next

      # --- Sampling_Ports: insert if new, never update ---
      existing_port <- dbGetQuery(con, "SELECT port_id FROM Sampling_Ports WHERE port_name = ?",
                                   params = list(row$port_name))

      if (nrow(existing_port) == 0) {
        dbExecute(con, "INSERT INTO Sampling_Ports (port_name, source, notes) VALUES (?, ?, ?)",
                  params = list(row$port_name, row$source, row$notes))
        port_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
        ports_registered <- ports_registered + 1L
      } else {
        port_id <- existing_port$port_id[1]
      }

      # --- Link direction follows well_role ---
      role_for_link <- if (!is.na(row$well_role) && row$well_role != "") row$well_role else NA_character_

      if (identical(role_for_link, "production")) {
        already <- dbGetQuery(con, "
          SELECT link_id FROM Production_Port_Links
          WHERE well_id = ? AND port_id = ? AND valid_from IS ?
        ", params = list(well_id, port_id, row$valid_from))

        if (nrow(already) == 0) {
          dbExecute(con, "
            INSERT INTO Production_Port_Links (well_id, port_id, valid_from, valid_to, source, notes)
            VALUES (?, ?, ?, ?, ?, ?)
          ", params = list(well_id, port_id, row$valid_from, row$valid_to, row$source, row$notes))
          prod_links_registered <- prod_links_registered + 1L
        }
      } else if (identical(role_for_link, "injection")) {
        already <- dbGetQuery(con, "
          SELECT link_id FROM Port_Injection_Links
          WHERE port_id = ? AND well_id = ? AND valid_from IS ?
        ", params = list(port_id, well_id, row$valid_from))

        if (nrow(already) == 0) {
          dbExecute(con, "
            INSERT INTO Port_Injection_Links (port_id, well_id, valid_from, valid_to, source, notes)
            VALUES (?, ?, ?, ?, ?, ?)
          ", params = list(port_id, well_id, row$valid_from, row$valid_to, row$source, row$notes))
          inj_links_registered <- inj_links_registered + 1L
        }
      } else {
        message("  -> ", row$well_name, " has a port_name but no well_role -- skipping link ",
                "(can't tell production-side from injection-side). Fill in well_role to link it.")
      }
    }
  }

  # ------------------------------------------------------------
  # ALIAS REGISTRATION
  # ------------------------------------------------------------
  if (!file_exists(aliases_csv)) {
    message("[register well network] No alias map at ", aliases_csv, " -- nothing to register.")
  } else {
    aliases <- read_csv(aliases_csv, show_col_types = FALSE) %>%
      mutate(well_name = trimws(well_name)) %>%
      filter(!is.na(well_name), well_name != "")

    for (i in seq_len(nrow(aliases))) {
      row <- aliases[i, ]

      well_match <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?",
                                params = list(row$well_name))

      if (nrow(well_match) == 0) {
        warning("[register well network] Alias '", row$alias, "' references unknown well_name '",
                row$well_name, "' -- skipped. Add a Wells row (e.g. via dhakal_well_network.csv) first.")
        next
      }

      well_id <- well_match$well_id[1]

      already <- dbGetQuery(con, "SELECT alias_id FROM Well_Aliases WHERE well_id = ? AND alias = ?",
                             params = list(well_id, row$alias))

      if (nrow(already) == 0) {
        dbExecute(con, "
          INSERT INTO Well_Aliases (well_id, alias, alias_type, source, notes)
          VALUES (?, ?, ?, ?, ?)
        ", params = list(well_id, row$alias, row$alias_type, row$source, row$notes))
        aliases_registered <- aliases_registered + 1L
      }
    }
  }

  message("  -> Wells registered: ", wells_registered,
          " | Ports registered: ", ports_registered,
          " | Production links: ", prod_links_registered,
          " | Injection links: ", inj_links_registered,
          " | Aliases registered: ", aliases_registered)

  invisible(list(
    wells_registered = wells_registered,
    ports_registered = ports_registered,
    prod_links_registered = prod_links_registered,
    inj_links_registered = inj_links_registered,
    aliases_registered = aliases_registered
  ))
}
