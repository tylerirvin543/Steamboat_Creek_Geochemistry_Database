##Generic unit conversions for database ingest

convert_units <- function(value, from_unit, to_unit) {
  
  if (from_unit == to_unit) {
    return(value)
  }
  
  # mg/L ↔ ug/L
  if (from_unit == "ug/L" && to_unit == "mg/L") {
    return(value / 1000)
  }
  
  if (from_unit == "mg/L" && to_unit == "ug/L") {
    return(value * 1000)
  }
  
  stop("Unsupported unit conversion: ", from_unit, " → ", to_unit)
}
