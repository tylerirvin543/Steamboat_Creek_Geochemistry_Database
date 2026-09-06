# --------------------------------------------------
# NDEP Analyte Mapping (DISSOLVED ONLY)
# Authoritative mapping between NDEP CHARACTERISTICNAME
# values and clean aqueous analytes used internally
# --------------------------------------------------

library(dplyr)
library(tibble)

ndep_analyte_map <- tribble(
  ~raw_name,                                      ~analyte,      ~units,   ~category,        ~role,        ~conversion_factor,
  
  # ==================================================
  # FIELD PARAMETERS (aqueous)
  # ==================================================
  "pH Field (SU)",                                "pH",          "SU",     "field",          "required", 1,
  "pH Lab (SU)",                                  "pH",          "SU",     "field",          "required", 1,
  "Temp Field (deg C)",                           "temperature", "deg C",  "field",          "required", 1,
  "Temp Lab (deg C)",                             "temperature", "deg C",  "field",          "required", 1,
  "SpC Field (uS/cm)",                            "conductivity","uS/cm",  "field",          "supporting", 1,
  "SpC Lab (uS/cm)",                              "conductivity","uS/cm",  "field",          "supporting", 1,
  "TDS Field (mg/L)",                             "TDS",         "mg/L",   "field",          "supporting", 1,
  "TDS Lab (mg/L)",                               "TDS",         "mg/L",   "field",          "supporting", 1,
  "Turbidity Field (NTU)",                        "turbidity",   "NTU",    "field",          "supporting", 1,
  "Turbidity Lab (NTU)",                          "turbidity",   "NTU",    "field",          "supporting", 1,
  
  # ==================================================
  # MAJOR CATIONS (DISSOLVED ONLY)
  # ==================================================
  "Calcium Diss (mg/L)",                          "Ca",          "mg/L",   "major_ion",      "cation", 1,
  "Magnesium Diss (mg/L)",                        "Mg",          "mg/L",   "major_ion",      "cation", 1,
  "Sodium Diss (mg/L)",                           "Na",          "mg/L",   "major_ion",      "cation", 1,
  "Potassium Diss (mg/L)",                        "K",           "mg/L",   "major_ion",      "cation", 1,
  
  # ==================================================
  # MAJOR ANIONS & ALKALINITY SYSTEM (AQUEOUS)
  # ==================================================
  "Chloride (mg/L)",                              "Cl",          "mg/L",   "major_ion",      "anion", 1,
  "Sulfate (mg/L)",                               "SO4",         "mg/L",   "major_ion",      "anion", 1,
  
  # 2026-09-06: 'HCO3 as CaCO3'/'CO3 as CaCO3' are confirmed duplicate
  # representations of the exact same measurement as 'HCO3 as HCO3'/
  # 'CO3 as CO3' (same EVENTIDs, ratio consistently matching the true
  # CaCO3/HCO3 and CaCO3/CO3 equivalent-weight ratios) -- NOT
  # independent values. Previously both variants mapped to the same
  # clean analyte code ('HCO3'/'CO3'), so ingest_ndep.R's own
  # distinct(sample_id, analyte, source_id) dedup silently kept
  # whichever one happened to come first, mislabeling a CaCO3-basis
  # number as if it were true HCO3/CO3 mass for however many rows
  # that affected. Remapped to a distinct, explicitly-excluded code
  # ('_dup' suffix, role='excluded') so the raw measurement is still
  # ingested/traceable but can never again collide with the true-mass
  # 'HCO3'/'CO3' codes. The authoritative alkalinity source is now
  # 'Total Alkalinity as CaCO3' -> clean analyte 'Alkalinity' (see below).
  "HCO3 as CaCO3 (mg/L)",                         "HCO3_as_CaCO3_dup", "mg/L", "alkalinity", "excluded", 1,
  "HCO3 as HCO3 (mg/L)",                          "HCO3",        "mg/L",   "alkalinity",     "anion", 1,
  
  "CO3 as CaCO3 (mg/L)",                          "CO3_as_CaCO3_dup",  "mg/L", "alkalinity", "excluded", 1,
  "CO3 as CO3 (mg/L)",                            "CO3",         "mg/L",   "alkalinity",     "anion", 1,

  # 2026-09-06: 'Total Alkalinity as CaCO3' is the directly-titrated
  # alkalinity measurement in the raw NDEP export -- confirmed via a
  # side-by-side check against 'HCO3 as CaCO3'/'HCO3 as HCO3' (which
  # turn out to be the exact same 647 measurement events reported in
  # two unit conventions, not independent values -- ratio consistently
  # ~0.82, matching the true CaCO3/HCO3 equivalent-weight ratio) that
  # 'Total Alkalinity as CaCO3' covers more samples (736) and is the
  # standard analytical parameter to feed PHREEQC's Alkalinity input.
  # Previously NOT ingested at all under any mapping. conversion_factor
  # converts mg/L as CaCO3 -> mg/L as HCO3 (61.017/50.05 = 1.2189) so
  # this project's 'Alkalinity' analyte code stays internally
  # consistent with format_solution_block()'s fixed 'as HCO3' clause.
  "Total Alkalinity as CaCO3 (mg/L)",             "Alkalinity",  "mg/L",   "major_ion",      "anion", 1.2189,
  
  # ==================================================
  # SILICA (AQUEOUS)
  # ==================================================
  "Silica as SiO2 (ug/L)",                        "SiO2",        "ug/L",   "minor",          "neutral", 1,
  "Silica as SiO2 Diss (ug/L)",                   "SiO2",        "ug/L",   "minor",          "neutral", 1,
  
  # ==================================================
  # NUTRIENTS (AQUEOUS)
  # ==================================================
  "Nitrate N (mg/L)",                             "NO3_N",       "mg/L",   "nutrient",       "supporting", 1,
  "Nitrate NO3 (mg/L)",                           "NO3",         "mg/L",   "nutrient",       "supporting", 1,
  "Nitrate+Nitrite N (mg/L)",                     "NOx_N",       "mg/L",   "nutrient",       "supporting", 1,
  "Ammonia N (mg/L)",                             "NH4_N",       "mg/L",   "nutrient",       "supporting", 1,
  "Ammonia, Unionized (mg/L)",                    "NH3",         "mg/L",   "nutrient",       "supporting", 1,
  
  # ==================================================
  # TRACE METALS (DISSOLVED ONLY)
  # ==================================================
  "Iron Diss (ug/L)",                             "Fe",          "ug/L",   "trace_metal",    "redox", 1,
  "Manganese Diss (ug/L)",                        "Mn",          "ug/L",   "trace_metal",    "redox", 1,
  "Arsenic Diss (ug/L)",                          "As",          "ug/L",   "trace_metal",    "toxic", 1,
  "Boron Diss (ug/L)",                            "B",           "ug/L",   "trace_metal",    "supporting", 1,
  "Lithium Diss (ug/L)",                          "Li",          "ug/L",   "trace_metal",    "geothermal", 1,
  
  # ==================================================
  # DERIVED / QC ONLY
  # ==================================================
  "Hardness Diss (mg/L)",                          "Hardness",    "mg/L",   "derived",        "qc_only", 1
)

# --------------------------------------------------
# SAFETY CHECKS
# --------------------------------------------------

stopifnot(!anyDuplicated(ndep_analyte_map$raw_name))
stopifnot(!any(is.na(ndep_analyte_map$analyte)))

ndep_analyte_map

# --------------------------------------------------
# Clean NDEP StationData for Locations table
# --------------------------------------------------
ndep_analyte_map <- ndep_analyte_map |>
  mutate(
    raw_name_norm = gsub("\\s*\\(.*\\)$", "", raw_name)
  )
# --------------------------------------------------
# NDEP StationData -> Locations
# Explicitly keyed on STATIONCODE / MONITORINGLOCATIONID
# --------------------------------------------------

library(DBI)
library(dplyr)
library(readr)

# --------------------------------------------------
# 1. Clean NDEP StationData
# --------------------------------------------------

clean_ndep_stations <- function(station_csv) {
  
  stations <- read_csv(station_csv, show_col_types = FALSE)
  
  stations |>
    transmute(
      station_code = MONITORINGLOCATIONID,  # THIS is the key
      name = StationName,
      latitude = as.numeric(Latitude),
      longitude = as.numeric(Longitude),
      site_type = "background",  # explicitly neutral
      notes = paste(
        "NDEP station.",
        "StationCode:", MONITORINGLOCATIONID,
        "Waterbody:", WaterBodyName,
        "County:", County,
        "HUC:", HUC,
        sep = " "
      )
    ) |>
    distinct(station_code, .keep_all = TRUE)
}

# --------------------------------------------------
# 2. Insert new Locations safely
# --------------------------------------------------

insert_ndep_locations <- function(con, stations_df) {
  
  # Pull existing locations with station codes embedded in notes
  existing <- dbReadTable(con, "Locations") |>
    select(location_id, name, notes)
  
  # Identify new stations by station_code
  existing_codes <- existing |>
    filter(grepl("StationCode:", notes)) |>
    mutate(
      station_code = sub(".*StationCode:\\s*", "", notes)
    ) |>
    pull(station_code)
  
  new_locations <- stations_df |>
    filter(!station_code %in% existing_codes)
  
  if (nrow(new_locations) > 0) {
    dbWriteTable(
      con,
      "Locations",
      new_locations |>
        select(name, latitude, longitude, site_type, notes),
      append = TRUE
    )
  }
  
  message(nrow(new_locations), " new NDEP locations inserted.")
  
  invisible(NULL)
}

# --------------------------------------------------
# 3. Build station_code -> location_id lookup
# --------------------------------------------------

build_station_location_lookup <- function(con) {
  
  locations <- dbReadTable(con, "Locations")
  
  lookup <- locations |>
    filter(grepl("StationCode:", notes)) |>
    mutate(
      station_code = sub(".*StationCode:\\s*", "", notes)
    ) |>
    select(location_id, station_code)
  
  lookup
}
