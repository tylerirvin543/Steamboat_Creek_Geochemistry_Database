library(openxlsx2)
library(mschart)

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------
transects <- c("transect_A", "transect_B")
output_file <- "flux_transects_template.xlsx"

# ------------------------------------------------------------
# CREATE WORKBOOK
# ------------------------------------------------------------
wb <- wb_workbook()

# ------------------------------------------------------------
# METADATA SHEET
# ------------------------------------------------------------
metadata <- data.frame(
  Field = c(
    "campaign_name",
    "event_id",
    "external_station_code",
    "operator",
    "date",
    "timezone",
    "units_flux",
    "units_velocity",
    "units_area",
    "notes"
  ),
  Value = ""
)

wb$add_worksheet("metadata")
wb$add_data("metadata", metadata, start_row = 1)

# Style metadata
meta_style <- wb_style(text_fmt = "bold")
wb$add_style("metadata", dims = "A1:A10", style = meta_style)

# ------------------------------------------------------------
# STYLES
# ------------------------------------------------------------
header_style <- wb_style(
  text_fmt   = "bold",
  font_color = wb_color("white"),
  bg_fill    = wb_color("#1F4E78"),
  halign     = "center"
)

# ------------------------------------------------------------
# CREATE TRANSECT SHEETS
# ------------------------------------------------------------
for (tr in transects) {
  
  wb$add_worksheet(tr)
  wb$grid_lines(tr, show = TRUE)
  
  headers <- c(
    "point_id",
    "datetime",
    "latitude",
    "longitude",
    "depth_m",
    "width_m",
    "velocity_m_s",
    "area_m2",
    "measured_value",
    "flux_calc",
    "transect_id",
    "notes"
  )
  
  # Write headers
  wb$add_data(tr, t(headers), start_row = 1, col_names = FALSE)
  wb$add_style(tr, dims = "A1:L1", style = header_style)
  
  # Pre-fill 25 empty rows
  n_rows <- 25
  empty_data <- data.frame(matrix("", nrow = n_rows, ncol = length(headers)))
  wb$add_data(tr, empty_data, start_row = 2, col_names = FALSE)
  
  # Fill transect ID column automatically
  wb$add_data(
    tr,
    x = rep(tr, n_rows),
    start_row = 2,
    start_col = 11,
    col_names = FALSE
  )
  
  # ------------------------------------------------------------
  # ADD EXCEL FORMULA FOR FLUX
  # ------------------------------------------------------------
  # Flux = measured_value / area_m2 (I / H)
  for (i in 2:(n_rows + 1)) {
    formula <- sprintf("=IF(AND(H%d>0,I%d<>\"\"), I%d/H%d, \"\")", i, i, i, i)
    wb$add_formula(tr, formula, start_col = 10, start_row = i)
  }
  
  # Freeze header row
  wb$freeze_pane(tr, first_active_row = 2)
  
  # Auto column widths
  wb$set_col_widths(tr, cols = 1:12, widths = "auto")
}

# ------------------------------------------------------------
# OPTIONAL VISUALIZATION SHEET
# ------------------------------------------------------------
wb$add_worksheet("Flux_Visualization")

# Example placeholder chart data
chart_data <- data.frame(
  Time = 1:5,
  Low = c(1, 2, NA, NA, NA),
  Med = c(NA, NA, 3, 4, NA),
  High = c(NA, NA, NA, NA, 5)
)

wb$add_data("Flux_Visualization", chart_data)

chart <- ms_linechart(
  chart_data,
  x = "Time",
  y = c("Low", "Med", "High")
) |>
  chart_title("Flux (Preview Gradient Chart)") |>
  chart_ax_titles(x = "Time", y = "Flux")

chart <- chart_labels_properties(
  chart,
  series = 1,
  styles = list(line_color = "#FFC000", marker_fill = "#FFC000")
)

chart <- chart_labels_properties(
  chart,
  series = 2,
  styles = list(line_color = "#ED7D31", marker_fill = "#ED7D31")
)

chart <- chart_labels_properties(
  chart,
  series = 3,
  styles = list(line_color = "#C00000", marker_fill = "#C00000")
)

wb$add_mschart("Flux_Visualization", chart, dims = "A10:H25")

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------
wb$save(output_file)

cat("Flux template created:", output_file, "\n")