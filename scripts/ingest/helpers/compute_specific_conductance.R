# ------------------------------------------------------------
# compute_specific_conductance.R
#
# Purpose:
#   Convert raw, uncompensated electrical conductivity (EC) —
#   what a HOBO/Onset "Full Range" conductivity logger records —
#   into specific conductance (SC) referenced to 25 degC.
#
# Why this matters:
#   Raw EC varies with water temperature (~2%/degC) independent of
#   ion concentration. Specific conductance removes that temperature
#   effect so readings are comparable through time and usable as a
#   chloride proxy. This is the standard USGS/YSI non-linear
#   temperature-compensation approach (theta = 25 degC, coefficient
#   ~0.0191/degC), per USGS Techniques and Methods 1-D3.
#
# Formula:
#   SC25 = EC_measured / (1 + coefficient * (T - 25))
#
# Notes:
#   - `coefficient` defaults to 0.0191 (USGS default). If field/lab
#     conductivity-vs-temperature pairs become available for
#     Steamboat Creek, this should be recalibrated site-specifically
#     (see scripts/analysis/sampling_frequency/02_specific_conductance.R).
#   - Returns NA where either input is NA or non-finite, rather than
#     erroring, so it is safe to use inside a dplyr::mutate() over a
#     full logger file.
# ------------------------------------------------------------

compute_specific_conductance <- function(ec_raw, temperature_c, coefficient = 0.0191, theta = 25) {

  ec_raw <- suppressWarnings(as.numeric(ec_raw))
  temperature_c <- suppressWarnings(as.numeric(temperature_c))

  denom <- 1 + coefficient * (temperature_c - theta)

  sc25 <- ec_raw / denom

  # Guard against divide-by-near-zero / non-finite results
  sc25[!is.finite(sc25)] <- NA_real_

  sc25
}
