# --------------------------------------------------
# Lab Analyte Mapping (DISSOLVED ONLY)
# Maps lab-reported analyte names to clean aqueous analytes
# --------------------------------------------------

library(tibble)

  lab_analyte_map <- tribble(
    ~raw_name, ~analyte, ~units, ~category, ~phreeqc_name, ~charge, ~molar_mass, ~conversion_factor,
    
    "Ca", "Ca", "mg/L", "major_ion", "Ca", 2, 40.078, 1,
    "Mg", "Mg", "mg/L", "major_ion", "Mg", 2, 24.305, 1,
    "Na", "Na", "mg/L", "major_ion", "Na", 1, 22.990, 1,
    "K",  "K",  "mg/L", "major_ion", "K", 1, 39.098, 1,
    
    "Cl", "Cl", "mg/L", "major_ion", "Cl", -1, 35.45, 1,
    # phreeqc_name is "S(6)" (not "SO4", and not bare "S") -- PHREEQC's
    # SOLUTION_MASTER_SPECIES element name for sulfate is "S" in every
    # checked database (phreeqc.dat, llnl.dat); "SO4" is only a
    # species/gfw label, not a valid element token for direct SOLUTION
    # input. Confirmed 2026-09-06: specifying "SO4  <value>" literally
    # produced "WARNING: Could not find element in database, SO4"
    # (silently dropping sulfate from every PHREEQC run) until fixed to
    # "S  <value>  as SO4" -- see scripts/phreeqc/utils_phreeqc.R's
    # format_solution_block() as_unit_lookup. Tightened further
    # 2026-09-06 (multi-gas CO2+H2S GAS_PHASE testing): a bare,
    # valence-unqualified "S" line is ambiguous the moment a second
    # sulfur species (e.g. dissolved sulfide, "S(-2)") is also specified
    # in the same SOLUTION block -- PHREEQC's default valence assignment
    # for unqualified "S" collided with an explicit "S(-2)" line and
    # threw "ERROR: Analytical data entered twice for HS-." (confirmed
    # against llnl.dat; this project has no sulfide analyte mapped yet,
    # so no real sample has hit this, but it will the moment one does).
    # Explicit "S(6)" is unambiguous and behaves identically to the old
    # bare "S" when no other sulfur species is present -- confirmed via
    # a side-by-side PHREEQC run against llnl.dat with only SO4 supplied.
    "SO4", "SO4", "mg/L", "major_ion", "S(6)", -2, 96.06, 1,
    "NO3 (as N)", "NO3", "mg/L", "nutrient", "N(5)", -1, 14.01, 1,
    "F", "F", "mg/L", "tracer", "F", -1, 18.998, 1,
    "Br", "Br", "mg/L", "tracer", "Br", -1, 79.904, 1,
    
    
    # charge = -1, molar_mass = 61.017 (HCO3's own molar mass) --
    # Alkalinity is stored project-wide as HCO3-mass-equivalent mg/L
    # (format_solution_block() always emits it as 'Alkalinity <val> as
    # HCO3'; NDEP's ingest converts its CaCO3-based titration value to
    # this same convention -- see database/schema/ndep_analyte_map.R).
    # Previously charge=0/molar_mass=NA, which silently excluded
    # Alkalinity from every charge-balance calculation in
    # scripts/phreeqc/08_build_phreeqc_tables.R even after real
    # Alkalinity data was available -- found 2026-09-06 when NDEP
    # samples' charge balance didn't improve after adding real
    # Alkalinity values.
    # conversion_factor 1.2189 (61.017/50.05): FIELD's raw lab report
    # (data/raw/lab/RE26169388.csv) explicitly declares this column's
    # units as 'mg/L CaCO3eq' -- confirmed 2026-09-06 by reading the raw
    # units row directly -- NOT true HCO3 mass, despite
    # format_solution_block() always emitting Alkalinity 'as HCO3'.
    # This is the exact same mislabeling bug found and fixed for NDEP's
    # 'Total Alkalinity as CaCO3' (see ndep_analyte_map.R) -- FIELD's
    # Alkalinity Total silently never reached Lab_Analyses at all
    # before this session (see ingest_lab.R's normalize_lab_wide() fix,
    # a separate make.names()-mangles-the-join-key bug), so this
    # conversion has never been applied to any real ingested value yet.
    "Alkalinity Total", "Alkalinity", "mg/L", "major_ion", "Alkalinity", -1, 61.017, 1.2189,
    
    # phreeqc_name is "Si" (not "SiO2") -- same class of bug as SO4
    # above: "Si" is the element name, "SiO2" only the gfw/species label.
    "Si", "Si", "mg/L", "minor", "Si", 0, 28.085, 1,
    "B", "B", "ug/L", "tracer", "B", 0, 10.81, 1,
    "Li", "Li", "ug/L", "tracer", "Li", 1, 6.94, 1,
    "Sr", "Sr", "ug/L", "tracer", "Sr", 2, 87.62, 1,
    "Fe", "Fe", "ug/L", "redox", "Fe", 2, 55.845, 1,
    "Mn", "Mn", "ug/L", "redox", "Mn", 2, 54.938, 1,
    "As", "As", "ug/L", "tracer", "As", 0, 74.922, 1
  )


# --------------------------------------------------
# SAFETY CHECKS
# --------------------------------------------------

stopifnot(!anyDuplicated(lab_analyte_map$raw_name))
stopifnot(!any(is.na(lab_analyte_map$analyte)))

lab_analyte_map
