# --------------------------------------------------
# Insert Lab_Analyses into SQLite
# --------------------------------------------------

library(DBI)
library(dplyr)

insert_lab_analyses <- function(con, lab_df) {
  
  # Optional: remove exact duplicates
  existing <- dbReadTable(con, "Lab_Analyses")
  
  new_records <- lab_df |>
    anti_join(
      existing,
      by = c("sample_id", "analyte", "value")
    )
  
  if (nrow(new_records) > 0) {
    dbWriteTable(
      con,
      "Lab_Analyses",
      new_records,
      append = TRUE
    )
  }
  
  message(nrow(new_records), " new lab analyses inserted.")
  
  invisible(NULL)
}