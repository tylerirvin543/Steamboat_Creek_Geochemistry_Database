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
    # 2026-09-26: real FIELD collection_time strings like
    # "03/22/2024 9:12" (US format, no leading zero on the hour) are
    # not a "standard unambiguous format" for base R's as.POSIXct(),
    # which hard-ERRORS (not just NA-with-warning) the moment even one
    # element in the vector is ambiguous -- confirmed this was
    # silently blocking every real Cl/conductivity pairing attempt.
    # as.POSIXct() validates the WHOLE vector at once, so a single bad
    # element poisons every other (otherwise-valid, e.g. real ISO)
    # element in the same call too -- parse element-by-element instead,
    # trying ISO first then an explicit %m/%d/%Y %H:%M fallback
    # (mirrors the same fallback already used in notebook 07's own
    # .parse_any_date()) before giving up and leaving that one NA.
    rest <- x[!is_epoch]
    parsed_rest <- vapply(rest, function(v) {
      if (is.na(v) || !nzchar(v)) return(NA_real_)
      p <- tryCatch(as.numeric(as.POSIXct(v, tz = "UTC")), error = function(e) NA_real_)
      if (is.na(p)) {
        p <- tryCatch(as.numeric(as.POSIXct(v, format = "%m/%d/%Y %H:%M", tz = "UTC")),
                      error = function(e) NA_real_)
      }
      p
    }, numeric(1))
    parsed[!is_epoch] <- as.POSIXct(parsed_rest, origin = "1970-01-01", tz = "UTC")
  }

  return(parsed)
}
