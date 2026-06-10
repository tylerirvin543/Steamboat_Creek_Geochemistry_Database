parse_datetime_safe <- function(x) {
  
  x <- trimws(as.character(x))
  
  # try numeric timestamps (UNIX)
  num <- suppressWarnings(as.numeric(x))
  
  parsed <- ifelse(
    !is.na(num) & num > 1e9 & num < 2e10,
    as.POSIXct(num, origin = "1970-01-01", tz = "UTC"),
    NA
  )
  
  # fallback to standard parsing
  parsed2 <- suppressWarnings(as.POSIXct(x, tz = "UTC"))
  
  parsed[is.na(parsed)] <- parsed2[is.na(parsed)]
  
  return(parsed)
}
