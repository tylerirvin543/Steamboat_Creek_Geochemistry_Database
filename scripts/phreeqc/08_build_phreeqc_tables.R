#08_build_phreeqc_tables
#
# Builds PHREEQC_Solutions (the direct input to PHREEQC SOLUTION blocks,
# see scripts/phreeqc/utils_phreeqc.R) from this database's validated
# chemistry tables: major/minor ions from Lab_Analyses, pH/temperature
# from Field_Measurements, and d18O/dD from Isotope_Analyses (carried
# through for later mixing-model use, even though PHREEQC itself doesn't
# model isotopes).
#
# Replaces the earlier, unwired scripts/phreeqc/09_build_phreeqc_tables.R,
# which: (a) connected to the wrong database file
# ("geochem_sampling.sqlite", not database/geochem_demo.sqlite or
# database/geochem_operational.sqlite -- the two files run_pipeline.R
# actually uses), (b) opened its own dbConnect() instead of accepting
# `con`, (c) hardcoded a simplified charge balance using only 8 analytes'
# equivalent weights instead of Chemistry_Parameters/lab_analyte_map.R's
# real charge/molar_mass values, and (d) used `overwrite = TRUE` (data
# loss on every rerun) instead of an idempotent upsert. All four are
# fixed here.

library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)

#' Determine PHREEQC eligibility for a set of samples.
#'
#' A sample is "eligible" for a SOLUTION block if it has temperature, pH,
#' and at least Na and Cl (the minimum needed for a chemically meaningful
#' PHREEQC run). Everything else is "rejected" with a human-readable reason.
#'
#' @param con DBI connection.
#' @param site_type Character. Filter by Locations.site_type (NULL for all).
#' @param sample_ids Character/integer vector of specific sample_ids (NULL for all).
#' @return list(eligible = tibble, rejected = tibble with a `reason` column)
get_phreeqc_eligible <- function(con, site_type = NULL, sample_ids = NULL) {
  solutions <- dbReadTable(con, "PHREEQC_Solutions") |> as_tibble()

  loc_info <- dbGetQuery(con, "
    SELECT s.sample_id, l.name AS location_name, l.site_type
    FROM Samples s
    JOIN Locations l ON s.location_id = l.location_id
  ")

  solutions <- solutions |> left_join(loc_info, by = "sample_id")

  if (!is.null(site_type)) solutions <- solutions |> filter(site_type == !!site_type)
  if (!is.null(sample_ids)) solutions <- solutions |> filter(sample_id %in% sample_ids)

  reason_for <- function(row) {
    reasons <- character()
    if (is.na(row$temperature)) reasons <- c(reasons, "missing temperature")
    if (is.na(row$pH)) reasons <- c(reasons, "missing pH")
    if (is.na(row$Na)) reasons <- c(reasons, "missing Na")
    if (is.na(row$Cl)) reasons <- c(reasons, "missing Cl")
    paste(reasons, collapse = "; ")
  }

  is_eligible <- !is.na(solutions$temperature) & !is.na(solutions$pH) &
    !is.na(solutions$Na) & !is.na(solutions$Cl)

  eligible <- solutions[is_eligible, , drop = FALSE]
  rejected <- solutions[!is_eligible, , drop = FALSE]
  if (nrow(rejected) > 0) {
    rejected$reason <- vapply(seq_len(nrow(rejected)), function(i) reason_for(rejected[i, ]), character(1))
  } else {
    rejected$reason <- character(0)
  }

  list(eligible = eligible, rejected = rejected)
}

#' Build (or refresh) PHREEQC_Solutions from validated chemistry tables.
#'
#' Idempotent: rows are upserted per sample_id (delete-then-append), so
#' rerunning after new chemistry is ingested only touches affected
#' samples, and a full pipeline rerun never destroys unrelated rows the
#' way the old script's `overwrite = TRUE` did.
#'
#' @param con DBI connection.
#' @return The built tibble (all samples with any qualifying chemistry),
#'   invisibly.
build_phreeqc_solutions <- function(con) {
  message("---- Building PHREEQC_Solutions ----")

  source("database/schema/lab_analyte_map.R")
  analytes <- lab_analyte_map$analyte

  # NDEP data (ingest_ndep.R, using ndep_analyte_map.R -- a separate
  # mapping table from lab_analyte_map.R used by FIELD/lab data) writes
  # some of the same physical quantities under different analyte codes
  # and, critically, does NOT normalize units the way ingest_lab.R does
  # -- confirmed 2026-09-06: the same analyte (e.g. "SiO2", "As", "B",
  # "Fe", "Li", "Mn") appears in Lab_Analyses with BOTH "ug/L" and
  # "mg/L" rows for different samples. Naively averaging raw values
  # across source_id/fraction (as this function already needs to do for
  # legitimate repeat analyses) would silently mix units and produce
  # ~1000x errors for whichever rows are "wrong" relative to others in
  # the average. Every value is now converted to mg/L (matching this
  # project's other convention -- ingest_lab.R stores everything in
  # mg/L) before any aggregation happens, using each row's own `units`
  # value, not the analyte's "expected" unit.
  #
  # "SiO2" (NDEP's code) and "Si" (lab_analyte_map's code) represent the
  # same physical quantity -- both are total dissolved silica expressed
  # as SiO2 mass -- so NDEP's SiO2 rows are folded into the "Si" column
  # directly (see the rename below); PHREEQC's "as SiO2" clause in
  # format_solution_block() already expects the value in exactly this
  # form.
  #
  # NDEP's alkalinity system ("HCO3", "CO3") is deliberately NOT folded
  # into the "Alkalinity" column here: the raw NDEP source mixes two
  # different reporting conventions ("HCO3 as CaCO3 (mg/L)" and "HCO3 as
  # HCO3 (mg/L)", a real ~22% mg/L unit difference for the same
  # dissolved mass -- CaCO3 eq. wt. 50.05 vs HCO3 eq. wt. 61.02) under
  # the single "HCO3" analyte code with no provenance column to tell
  # which convention any given row used. Including it without resolving
  # this would silently bias alkalinity-derived charge balance and
  # carbonate saturation indices for however many rows used the "as
  # CaCO3" convention. Flagged for the user rather than guessed; see
  # AGENTS.md.
  lab <- dbReadTable(con, "Lab_Analyses") |>
    filter(analyte %in% analytes | analyte == "SiO2") |>
    mutate(
      analyte = ifelse(analyte == "SiO2", "Si", analyte),
      value = case_when(
        tolower(coalesce(units, "")) == "ug/l" ~ value / 1000,
        tolower(coalesce(units, "")) %in% c("mg/l", "") ~ value,
        TRUE ~ NA_real_  # unrecognized unit -- do not silently guess
      )
    ) |>
    filter(!is.na(value)) |>
    select(sample_id, analyte, value) |>
    # A sample may have more than one Lab_Analyses row per analyte across
    # source_id/fraction (rare, but possible with multiple lab batches) --
    # take the mean (now unit-consistent, see above) rather than erroring
    # on pivot_wider's implicit dedup.
    group_by(sample_id, analyte) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = analyte, values_from = value)

  # pH/temperature: FIELD-sourced samples carry these in
  # Field_Measurements (parameter = 'pH'/'temperature'); NDEP-sourced
  # samples carry them as Lab_Analyses rows instead (analyte =
  # 'pH'/'temperature', confirmed 2026-09-06 -- NDEP has zero rows in
  # Field_Measurements at all). Pull from both and prefer the
  # Field_Measurements value when a sample genuinely has both (real
  # field instrument reading over a lab-reported one).
  field_pt <- dbReadTable(con, "Field_Measurements") |>
    filter(parameter %in% c("pH", "temperature")) |>
    select(sample_id, parameter, value)
  lab_pt <- dbReadTable(con, "Lab_Analyses") |>
    filter(analyte %in% c("pH", "temperature")) |>
    select(sample_id, parameter = analyte, value)
  field <- bind_rows(
    field_pt |> mutate(.src_priority = 1L),
    lab_pt |> mutate(.src_priority = 2L)
  ) |>
    group_by(sample_id, parameter) |>
    arrange(.src_priority, .by_group = TRUE) |>
    summarise(value = value[1], .groups = "drop") |>
    pivot_wider(names_from = parameter, values_from = value)

  isotopes <- tibble::tibble(sample_id = integer(0), d18O = double(0), dD = double(0))
  if (dbExistsTable(con, "Isotope_Analyses")) {
    iso_raw <- dbReadTable(con, "Isotope_Analyses") |>
      filter(analyte %in% c("d18O", "dD")) |>
      select(sample_id, analyte, value)
    if (nrow(iso_raw) > 0) {
      isotopes <- iso_raw |>
        group_by(sample_id, analyte) |>
        summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
        pivot_wider(names_from = analyte, values_from = value)
    }
  }

  # Every ion column named in lab_analyte_map should exist even if no
  # sample currently reports it, so downstream SOLUTION-block generation
  # and charge-balance math don't have to guard for a missing column.
  for (a in analytes) if (!a %in% names(lab)) lab[[a]] <- NA_real_
  for (p in c("pH", "temperature")) if (!p %in% names(field)) field[[p]] <- NA_real_
  for (i in c("d18O", "dD")) if (!i %in% names(isotopes)) isotopes[[i]] <- NA_real_

  solutions <- lab |>
    full_join(field, by = "sample_id") |>
    full_join(isotopes, by = "sample_id")

  # Charge balance using real charge/molar_mass from lab_analyte_map.R
  # (Chemistry_Parameters is the equivalent live-table copy, see
  # database/schema/08_phreeqc_schema.R) instead of the old script's
  # hardcoded 8-analyte equivalent weights.
  charged <- lab_analyte_map |> filter(!is.na(charge), charge != 0, !is.na(molar_mass))
  cations_map <- charged |> filter(charge > 0)
  anions_map  <- charged |> filter(charge < 0)

  meq_sum <- function(df, map) {
    total <- rep(0, nrow(df))
    for (i in seq_len(nrow(map))) {
      a <- map$analyte[i]
      if (!a %in% names(df)) next
      eq_wt <- map$molar_mass[i] / abs(map$charge[i])
      total <- total + coalesce(df[[a]], 0) / eq_wt
    }
    total
  }

  solutions <- solutions |>
    mutate(
      .cations_meq = meq_sum(solutions, cations_map),
      .anions_meq  = meq_sum(solutions, anions_map),
      charge_balance = 100 * (.cations_meq - .anions_meq) / (.cations_meq + .anions_meq),
      completeness_flag = ifelse(
        is.na(pH) | is.na(temperature) | is.na(Na) | is.na(Cl),
        "incomplete", "complete"
      ),
      units = "mg/L",
      built_at = as.character(Sys.time())
    ) |>
    select(-.cations_meq, -.anions_meq)

  # Ensure the full fixed column set from the PHREEQC_Solutions schema is
  # present even for columns no sample currently has (dbWriteTable would
  # otherwise write a table missing those columns on an append to an
  # existing table with extra NULLs already expected).
  schema_cols <- dbListFields(con, "PHREEQC_Solutions")
  schema_cols <- setdiff(schema_cols, "solution_id")
  for (col in schema_cols) if (!col %in% names(solutions)) solutions[[col]] <- NA
  solutions <- solutions[, schema_cols]

  # Idempotent upsert: delete existing rows for these sample_ids, then append.
  existing_ids <- solutions$sample_id
  if (length(existing_ids) > 0) {
    placeholders <- paste(rep("?", length(existing_ids)), collapse = ",")
    dbExecute(con, paste0("DELETE FROM PHREEQC_Solutions WHERE sample_id IN (", placeholders, ")"),
              params = as.list(existing_ids))
  }
  dbAppendTable(con, "PHREEQC_Solutions", solutions)

  n_complete <- sum(solutions$completeness_flag == "complete")
  message("PHREEQC_Solutions built: ", nrow(solutions), " rows (",
          n_complete, " complete, ", nrow(solutions) - n_complete, " incomplete).")

  invisible(solutions)
}
