normalize_lab_wide <- function(df) {
  
  
  print(df[[1]])
  
  # --------------------------------------------------
  # 1. Find the REAL header row (where SAMPLE lives)
  # --------------------------------------------------
  header_row <- which(trimws(df[[1]]) == "SAMPLE")[1]
  
  if (is.na(header_row)) {
    stop("Could not find 'SAMPLE' header row")
  }
  
  units_row <- header_row + 1
  
  # --------------------------------------------------
  # 2. Extract analyte names and units
  # --------------------------------------------------
  analyte_names <- as.character(unlist(df[header_row, ]))
  units <- as.character(unlist(df[units_row, ]))
  
  # ✅ CRITICAL: fix empty names BEFORE assignment
  bad <- is.na(analyte_names) | analyte_names == ""
  analyte_names[bad] <- paste0("X", which(bad))
  
  # make syntactically valid (no duplicates, no blanks)
  analyte_names <- make.names(analyte_names, unique = TRUE)
  
  # --------------------------------------------------
  # 3. Assign names AFTER cleaning
  # --------------------------------------------------
  names(df) <- analyte_names
  
  # --------------------------------------------------
  # 4. Remove everything above data
  # --------------------------------------------------
  df <- df[-c(1:units_row), ]
  
  # Set first column explicitly
  colnames(df)[1] <- "sample_code"
  
  # Fix sample naming (IMPORTANT)
  df <- df %>%
    mutate(sample_code = gsub("_", "-", trimws(sample_code)))
  
  # --------------------------------------------------
  # 5. Pivot to long format
  # --------------------------------------------------
  df_long <- df %>%
    pivot_longer(
      cols = -sample_code,
      names_to = "analyte",
      values_to = "raw_value"
    )
  
  # --------------------------------------------------
  # 6. Clean values
  # --------------------------------------------------
  df_long %>%
    mutate(
      raw_value_chr = as.character(raw_value),
      
      qualifier = ifelse(
        grepl("^[<>]", raw_value_chr),
        substr(raw_value_chr, 1, 1),
        NA_character_
      ),
      
      value = suppressWarnings(
        as.numeric(gsub("[<>]", "", raw_value_chr))
      ),
      
      units = units[match(analyte, analyte_names)]
    ) %>%
    filter(!is.na(value))
}