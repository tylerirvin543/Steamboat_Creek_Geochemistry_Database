# --------------------------------------------------
# NDEP Analyte Mapping (DISSOLVED ONLY)
# Authoritative mapping between NDEP CHARACTERISTICNAME
# values and clean aqueous analytes used internally
# --------------------------------------------------

library(dplyr)
library(tibble)

ndep_analyte_map <- tribble(
  ~raw_name,                                      ~analyte,      ~units,   ~category,        ~role,
  
  # ==================================================
  # FIELD PARAMETERS (aqueous)
  # ==================================================
  "pH Field (SU)",                                "pH",          "SU",     "field",          "required",
  "pH Lab (SU)",                                  "pH",          "SU",     "field",          "required",
  "Temp Field (deg C)",                           "temperature", "deg C",  "field",          "required",
  "Temp Lab (deg C)",                             "temperature", "deg C",  "field",          "required",
  "SpC Field (uS/cm)",                            "conductivity","uS/cm",  "field",          "supporting",
  "SpC Lab (uS/cm)",                              "conductivity","uS/cm",  "field",          "supporting",
  "TDS Field (mg/L)",                             "TDS",         "mg/L",   "field",          "supporting",
  "TDS Lab (mg/L)",                               "TDS",         "mg/L",   "field",          "supporting",
  "Turbidity Field (NTU)",                        "turbidity",   "NTU",    "field",          "supporting",
  "Turbidity Lab (NTU)",                          "turbidity",   "NTU",    "field",          "supporting",
  
  # ==================================================
  # MAJOR CATIONS (DISSOLVED ONLY)
  # ==================================================
  "Calcium Diss (mg/L)",                          "Ca",          "mg/L",   "major_ion",      "cation",
  "Magnesium Diss (mg/L)",                        "Mg",          "mg/L",   "major_ion",      "cation",
  "Sodium Diss (mg/L)",                           "Na",          "mg/L",   "major_ion",      "cation",
  "Potassium Diss (mg/L)",                        "K",           "mg/L",   "major_ion",      "cation",
  
  # ==================================================
  # MAJOR ANIONS & ALKALINITY SYSTEM (AQUEOUS)
  # ==================================================
  "Chloride (mg/L)",                              "Cl",          "mg/L",   "major_ion",      "anion",
  "Sulfate (mg/L)",                               "SO4",         "mg/L",   "major_ion",      "anion",
  
  "HCO3 as CaCO3 (mg/L)",                         "HCO3",        "mg/L",   "alkalinity",     "anion",
  "HCO3 as HCO3 (mg/L)",                          "HCO3",        "mg/L",   "alkalinity",     "anion",
  
  "CO3 as CaCO3 (mg/L)",                          "CO3",         "mg/L",   "alkalinity",     "anion",
  "CO3 as CO3 (mg/L)",                            "CO3",         "mg/L",   "alkalinity",     "anion",
  
  # ==================================================
  # SILICA (AQUEOUS)
  # ==================================================
  "Silica as SiO2 (ug/L)",                        "SiO2",        "ug/L",   "minor",          "neutral",
  "Silica as SiO2 Diss (ug/L)",                   "SiO2",        "ug/L",   "minor",          "neutral",
  
  # ==================================================
  # NUTRIENTS (AQUEOUS)
  # ==================================================
  "Nitrate N (mg/L)",                             "NO3_N",       "mg/L",   "nutrient",       "supporting",
  "Nitrate NO3 (mg/L)",                           "NO3",         "mg/L",   "nutrient",       "supporting",
  "Nitrate+Nitrite N (mg/L)",                     "NOx_N",       "mg/L",   "nutrient",       "supporting",
  "Ammonia N (mg/L)",                             "NH4_N",       "mg/L",   "nutrient",       "supporting",
  "Ammonia, Unionized (mg/L)",                    "NH3",         "mg/L",   "nutrient",       "supporting",
  
  # ==================================================
  # TRACE METALS (DISSOLVED ONLY)
  # ==================================================
  "Iron Diss (ug/L)",                             "Fe",          "ug/L",   "trace_metal",    "redox",
  "Manganese Diss (ug/L)",                        "Mn",          "ug/L",   "trace_metal",    "redox",
  "Arsenic Diss (ug/L)",                          "As",          "ug/L",   "trace_metal",    "toxic",
  "Boron Diss (ug/L)",                            "B",           "ug/L",   "trace_metal",    "supporting",
  "Lithium Diss (ug/L)",                          "Li",          "ug/L",   "trace_metal",    "geothermal",
  
  # ==================================================
  # DERIVED / QC ONLY
  # ==================================================
  "Hardness Diss (mg/L)",                         "Hardness",    "mg/L",   "derived",        "qc_only"
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