# --------------------------------------------------
# Lab Analyte Mapping (DISSOLVED ONLY)
# Maps lab-reported analyte names to clean aqueous analytes
# --------------------------------------------------

library(tibble)

  lab_analyte_map <- tribble(
    ~raw_name, ~analyte, ~units, ~category, ~phreeqc_name, ~charge, ~molar_mass,
    
    "Ca", "Ca", "mg/L", "major_ion", "Ca", 2, 40.078,
    "Mg", "Mg", "mg/L", "major_ion", "Mg", 2, 24.305,
    "Na", "Na", "mg/L", "major_ion", "Na", 1, 22.990,
    "K",  "K",  "mg/L", "major_ion", "K", 1, 39.098,
    
    "Cl", "Cl", "mg/L", "major_ion", "Cl", -1, 35.45,
    "SO4", "SO4", "mg/L", "major_ion", "SO4", -2, 96.06,
    "NO3 (as N)", "NO3", "mg/L", "nutrient", "N(5)", -1, 14.01,
    "F", "F", "mg/L", "tracer", "F", -1, 18.998,
    "Br", "Br", "mg/L", "tracer", "Br", -1, 79.904,
    
    
    "Alkalinity Total", "Alkalinity", "mg/L", "major_ion", "Alkalinity", 0, NA,
    
    "Si", "Si", "mg/L", "minor", "SiO2", 0, 28.085,
    "B", "B", "ug/L", "tracer", "B", 0, 10.81,
    "Li", "Li", "ug/L", "tracer", "Li", 1, 6.94,
    "Sr", "Sr", "ug/L", "tracer", "Sr", 2, 87.62,
    "Fe", "Fe", "ug/L", "redox", "Fe", 2, 55.845,
    "Mn", "Mn", "ug/L", "redox", "Mn", 2, 54.938,
    "As", "As", "ug/L", "tracer", "As", 0, 74.922
  )


# --------------------------------------------------
# SAFETY CHECKS
# --------------------------------------------------

stopifnot(!anyDuplicated(lab_analyte_map$raw_name))
stopifnot(!any(is.na(lab_analyte_map$analyte)))

lab_analyte_map