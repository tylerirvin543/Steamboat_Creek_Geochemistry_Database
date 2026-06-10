#09_build_phreeqc_tables
#this script pulls major ions from lab_analyses
#pull pH, T, from Field_Measurments
#pivot into one row per sample
#flag missing ions or incomplete samples
#compute charge balance
#write PHREEQC_solutions and results to SQLite

library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)

con <- dbConnect(SQLite(), "geochem_sampling.sqlite")

# --------------------------------------------------
# 1. Create PHREEQC_Solutions table (derived layer)
# --------------------------------------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS PHREEQC_Solutions (
  solution_id INTEGER PRIMARY KEY,
  sample_id INTEGER UNIQUE,
  temperature REAL,
  pH REAL,
  Ca REAL,
  Mg REAL,
  Na REAL,
  K REAL,
  Cl REAL,
  SO4 REAL,
  HCO3 REAL,
  SiO2 REAL,
  units TEXT DEFAULT 'mg/L',
  charge_balance REAL,
  completeness_flag TEXT,

  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")

# --------------------------------------------------
# 2. Pull lab chemistry (major ions only)
# --------------------------------------------------

lab <- dbReadTable(con, "Lab_Analyses") %>%
  filter(analyte %in% c("Ca", "Mg", "Na", "K", "Cl", "SO4", "HCO3", "SiO2")) %>%
  select(sample_id, analyte, value)

chem_wide <- lab %>%
  pivot_wider(
    names_from = analyte,
    values_from = value
  )

# --------------------------------------------------
# 3. Pull field pH and temperature
# --------------------------------------------------

field <- dbReadTable(con, "Field_Measurements") %>%
  filter(parameter %in% c("pH", "temperature")) %>%
  select(sample_id, parameter, value) %>%
  pivot_wider(
    names_from = parameter,
    values_from = value
  )

# --------------------------------------------------
# 4. Combine chemistry + field data
# --------------------------------------------------

solutions <- chem_wide %>%
  left_join(field, by = "sample_id")

# --------------------------------------------------
# 5. Charge balance calculation (simplified)
# --------------------------------------------------

# charges (milliequivalents, approximate)
solutions <- solutions %>%
  mutate(
    cations =
      (Ca / 20.04) +
      (Mg / 12.15) +
      (Na / 23.0) +
      (K  / 39.1),
    
    anions =
      (Cl  / 35.45) +
      (SO4 / 48.03) +
      (HCO3 / 61.0),
    
    charge_balance =
      100 * (cations - anions) / (cations + anions)
  )

# --------------------------------------------------
# 6. Completeness flag
# --------------------------------------------------

solutions <- solutions %>%
  mutate(
    completeness_flag =
      ifelse(
        is.na(pH) |
          is.na(temperature) |
          is.na(Ca) |
          is.na(Mg) |
          is.na(Na) |
          is.na(Cl),
        "incomplete",
        "complete"
      )
  )

# --------------------------------------------------
# 7. Write to database (overwrite derived table)
# --------------------------------------------------

dbWriteTable(
  con,
  "PHREEQC_Solutions",
  solutions %>%
    select(
      sample_id, temperature, pH,
      Ca, Mg, Na, K, Cl, SO4, HCO3, SiO2,
      charge_balance, completeness_flag
    ),
  overwrite = TRUE
)

dbDisconnect(con)

message("PHREEQC_Solutions table built successfully.")

#Uses only validated database tables
#Makes assumptions explicit
#Can be rerun at any time
#Safe for PHREESQL
#Does not mix modeling with storage
#You can later:
#Add isotopes (separate table or extended schema)
#Add gas chemistry
#Tighten charge‑balance logic