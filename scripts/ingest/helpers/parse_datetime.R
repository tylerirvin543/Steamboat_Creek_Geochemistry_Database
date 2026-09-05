parse_datetime_safe <- function(x) {

  x <- trimws(as.character(x))

  # A purely numeric string (optionally with a decimal, e.g. "561817500.0")
  # is a Unix-epoch-seconds timestamp in this database, regardless of
  # magnitude -- some NDEP records go back to the 1980s, which is BELOW
  # the naive "> 1e9" cutoff this helper used to apply (that cutoff
  # incorrectly routed pre-2001 epoch values to the ISO-string parser,
  # which then hard-errors on a string like "561817500.0").
  is_epoch <- grepl("^-?[0-9]+(\\.[0-9]+)?$", x) & !is.na(x)

  # NOTE: ifelse() silently drops the POSIXct class, so build the result
  # with indexed assignment instead.
  parsed <- as.POSIXct(rep(NA_real_, length(x)), origin = "1970-01-01", tz = "UTC")
  parsed[is_epoch] <- as.POSIXct(as.numeric(x[is_epoch]), origin = "1970-01-01", tz = "UTC")

  if (any(!is_epoch)) {
    parsed[!is_epoch] <- suppressWarnings(as.POSIXct(x[!is_epoch], tz = "UTC"))
  }

  return(parsed)
}
