#08_lab_wide_to_long
library(dplyr)
library(tidyr)
library(readxl)

lab_raw <- read_excel("lab/steamboat3_lab.xlsx")

lab_long <- lab_raw %>%
  pivot_longer(
    cols = -SAMPLE,
    names_to = "analyte",
    values_to = "raw_value"
  ) %>%
  mutate(
    qualifier = ifelse(grepl("<", raw_value), "<", NA),
    value = as.numeric(gsub("<", "", raw_value)),
    detection_limit = ifelse(!is.na(qualifier), value, NA)
  ) %>%
  rename(field_sample_name = SAMPLE)