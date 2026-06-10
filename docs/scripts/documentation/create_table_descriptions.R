#scripts/documentation/create_table_descriptions.R
#This file documents each table type in the database

library(officer)
library(flextable)

#helper function for all tables
make_table_section <- function(doc, title, df) {
  ft <- flextable(df)
  ft <- autofit(ft)
  ft <- set_caption(ft, caption = title)
  
  doc <- body_add_par(doc, title, style = "heading 2")
  doc <- body_add_flextable(doc, ft)
  doc <- body_add_par(doc, "")
  
  doc
}
# Locations table
locations_df <- data.frame(
  Variable = c(
    "location_id",
    "external_station_code",
    "name",
    "latitude",
    "longitude",
    "site_type",
    "notes"
  ),
  Data_Type = c(
    "INTEGER",
    "TEXT",
    "TEXT",
    "REAL",
    "REAL",
    "TEXT",
    "TEXT"
  ),
  Variable_Class = c(
    "Numeric (integer)",
    "Categorical (nominal)",
    "Categorical (nominal)",
    "Numeric (continuous)",
    "Numeric (continuous)",
    "Categorical (nominal)",
    "Free text"
  ),
  Description = c(
    "Primary key; unique location identifier",
    "External identifier (e.g., NDEP station code); must be unique",
    "Human-readable site name",
    "Latitude in decimal degrees (−90 to 90)",
    "Longitude in decimal degrees (−180 to 180)",
    "Site classification (spring, creek, background, etc.)",
    "Optional descriptive metadata"
  )
)
#Sampling_events
events_df <- data.frame(
  Variable = c(
    "event_id",
    "external_event_id",
    "date",
    "purpose",
    "weather_conditions",
    "observer",
    "notes"
  ),
  Data_Type = c(
    "INTEGER",
    "TEXT",
    "TEXT",
    "TEXT",
    "TEXT",
    "TEXT",
    "TEXT"
  ),
  Variable_Class = c(
    "Numeric (integer)",
    "Categorical (nominal)",
    "Date",
    "Categorical (nominal)",
    "Categorical / text",
    "Categorical (nominal)",
    "Free text"
  ),
  Description = c(
    "Primary key",
    "External event identifier (e.g., NDEP EVENTID); must be unique",
    "Sampling date (ISO format)",
    "Sampling purpose (historical, baseline, etc.)",
    "Optional weather information",
    "Sampling organization or observer",
    "Additional metadata"
  )
)
#samples table
samples_df <- data.frame(
  Variable = c(
    "sample_id",
    "location_id",
    "event_id",
    "sample_type",
    "collection_time",
    "filtered",
    "preservation_method",
    "notes",
    "external_station_code",
    "external_event_id",
    "external_sample_id"
  ),
  Data_Type = c(
    "INTEGER",
    "INTEGER",
    "INTEGER",
    "TEXT",
    "TEXT",
    "INTEGER",
    "TEXT",
    "TEXT",
    "TEXT",
    "TEXT",
    "TEXT"
  ),
  Variable_Class = c(
    "Numeric (integer)",
    "Numeric (integer)",
    "Numeric (integer)",
    "Categorical (nominal)",
    "Date-time",
    "Boolean (0/1)",
    "Categorical / text",
    "Free text",
    "Categorical (nominal)",
    "Categorical (nominal)",
    "Categorical (nominal)"
  ),
  Description = c(
    "Primary key",
    "Foreign key to Locations",
    "Foreign key to Sampling_Events",
    "Sample media (e.g., water)",
    "Collection timestamp (ISO 8601)",
    "Indicates if sample was filtered",
    "Preservation or sampling method",
    "Additional notes",
    "External location identifier",
    "External event identifier",
    "External sample identifier (e.g., NDEP SOURCESAMPLEID)"
  )
)
#Lab_analyses table
lab_df <- data.frame(
  Variable = c(
    "analysis_id",
    "sample_id",
    "analyte",
    "value",
    "units",
    "fraction",
    "detection_limit",
    "method",
    "source_id"
  ),
  Data_Type = c(
    "INTEGER",
    "INTEGER",
    "TEXT",
    "REAL",
    "TEXT",
    "TEXT",
    "REAL",
    "TEXT",
    "INTEGER"
  ),
  Variable_Class = c(
    "Numeric (integer)",
    "Numeric (integer)",
    "Categorical (nominal)",
    "Numeric (continuous)",
    "Categorical",
    "Categorical",
    "Numeric (continuous)",
    "Categorical",
    "Numeric (integer)"
  ),
  Description = c(
    "Primary key",
    "Foreign key to Samples",
    "Standardized analyte name",
    "Measured concentration",
    "Measurement units",
    "Sample fraction (e.g., dissolved/total); NA for NDEP",
    "Reporting or detection limit",
    "Analytical method",
    "Foreign key to Data_Sources"
  )
)
#Data_Sources table
sources_df <- data.frame(
  Variable = c(
    "source_id",
    "name",
    "citation",
    "url"
  ),
  Data_Type = c(
    "INTEGER",
    "TEXT",
    "TEXT",
    "TEXT"
  ),
  Variable_Class = c(
    "Numeric (integer)",
    "Categorical (nominal)",
    "Free text",
    "Free text"
  ),
  Description = c(
    "Primary key",
    "Data provider name",
    "Citation for data source",
    "Source URL"
  )
)
# Build word doc
doc <- read_docx()

doc <- make_table_section(doc, "Table: Locations", locations_df)
doc <- make_table_section(doc, "Table: Sampling_Events", events_df)
doc <- make_table_section(doc, "Table: Samples", samples_df)
doc <- make_table_section(doc, "Table: Lab_Analyses", lab_df)
doc <- make_table_section(doc, "Table: Data_Sources", sources_df)

print(doc, target = "database_tables_description.docx")