#14_gas_mixing
#
# Forward and inverse two-end-member mixing for free-gas (fumarole)
# compositions -- the gas-phase analogue of 10_run_phreeqc_mixing.R's
# water Cl mixing model. Built ahead of real data for the same reason as
# 13_gas_geothermometry.R: the planned UCSB (Tobias Fischer) gas
# sampling campaign at the geysering fissure and nearby fumaroles will
# need exactly this kind of tool once real CO2/H2S/N2/Ar/He (+ isotope)
# analyses exist. No real gas-sample data exists yet, so (per explicit
# instruction) this stays a standalone, data-frame-in/data-frame-out
# module with no database table and no run_pipeline.R wiring -- pure
# self-test against real published end-members, mirroring
# demo_mixing_model()'s structure exactly.
#
# Model: a conservative-ratio approach, exactly like
# compute_mixing_fractions()'s Cl-ratio logic in
# 10_run_phreeqc_mixing.R, but using a gas-ratio tracer (default N2/Ar)
# instead of a dissolved-ion concentration. N2/Ar is the classic
# Giggenbach ternary-diagram axis (see Mariner & Janik 1995, Fig. 9 --
# "N2-He-Ar plot ... well 23-5 has the highest He relative to N2 and Ar
# ... so it should be most like the parent high-temperature fluid")
# used qualitatively in this project's one Steamboat-specific
# gas-geochemistry reference to assess dilution of deep thermal gas by
# air/meteoric gas. Treating N2/Ar as a conservative tracer for a
# *linear* two-end-member mix is a real, documented simplification --
# N2 and Ar can fractionate somewhat differently during boiling/
# degassing (different solubilities), so this should be read as a
# first-order screening tool, not a rigorous mass-balance model, until
# real paired gas analyses let that assumption be checked.
#
# Forward mixing (given two end-member gas compositions and a mixing
# fraction, predict the resulting composition) uses simple linear
# mole-percent averaging, renormalized to sum to 100 -- this implicitly
# assumes both end-members contribute comparable total gas per unit
# mixed fluid; a real total-gas-yield-weighted version would need each
# end-member's absolute gas content (e.g. mmol gas/kg fluid), which
# Mariner & Janik's Table 2 only reports for a handful of dissolved-gas
# rows (PW2/PW2-1/PW3-1), not for any free-gas/fumarole sample -- flagged
# here as a known simplification, not silently assumed away.

library(dplyr)

#' Compute a two-end-member mixing fraction from a conservative gas
#' ratio (e.g. N2/Ar).
#'
#' IMPORTANT: unlike a single conservative *concentration* (this
#' project's water-Cl mixing model in 10_run_phreeqc_mixing.R), a
#' *ratio* of two linearly-mixing components does NOT itself mix
#' linearly -- R_mix(f) = (f*num_th + (1-f)*num_met) / (f*denom_th +
#' (1-f)*denom_met) is a rational (hyperbolic), not linear, function of
#' f. An earlier version of this function used the water-model's linear
#' formula directly on the ratio and was wrong by nearly an order of
#' magnitude on this file's own self-test (recovered 0.10 instead of the
#' true 0.85) -- caught immediately by that self-test, which is exactly
#' why it exists. This version solves the correct hyperbolic relation
#' for f given the mixed ratio and each end-member's numerator/
#' denominator components directly (not pre-collapsed to a ratio).
#'
#' @param mixed_ratio Observed ratio (e.g. N2/Ar) in the sample of interest.
#' @param thermal_num,thermal_denom Numerator/denominator component
#'   values (e.g. N2, Ar mole %) in the thermal end-member.
#' @param meteoric_num,meteoric_denom Same, for the meteoric/atmospheric
#'   end-member.
#' @return Numeric mixing fraction attributable to the thermal end-member
#'   (0 = pure meteoric/atmospheric, 1 = pure thermal). Not clamped to
#'   [0,1] -- a fraction outside that range signals the two-end-member
#'   model doesn't fit (a third source, or non-conservative behavior).
compute_gas_mixing_fraction <- function(mixed_ratio, thermal_num, thermal_denom,
                                         meteoric_num, meteoric_denom) {
  denom <- thermal_num - meteoric_num - mixed_ratio * thermal_denom + mixed_ratio * meteoric_denom
  if (isTRUE(all.equal(denom, 0))) {
    stop("Thermal and meteoric end-members are not distinguishable for this tracer ratio.")
  }
  (mixed_ratio * meteoric_denom - meteoric_num) / denom
}

#' Forward-model the gas composition resulting from mixing two
#' end-members at a given thermal fraction (linear mole-% mixing,
#' renormalized to sum to 100 -- see file header for the total-gas-yield
#' caveat).
#'
#' @param thermal,meteoric Named numeric vectors of mole percent, e.g.
#'   c(CO2=97.7, H2S=1.04, H2=0.021, CH4=0.0051, N2=1.21, Ar=0.018,
#'   He=0.0022). Both vectors should use the same component names;
#'   any component missing from one is treated as 0 in that end-member.
#' @param fraction_thermal Numeric in [0,1].
#' @return Named numeric vector of mole percent, renormalized to sum to 100.
forward_gas_mixing <- function(thermal, meteoric, fraction_thermal) {
  if (fraction_thermal < 0 || fraction_thermal > 1) {
    stop("fraction_thermal must be in [0,1].")
  }
  components <- union(names(thermal), names(meteoric))
  t_full <- setNames(rep(0, length(components)), components); t_full[names(thermal)] <- thermal
  m_full <- setNames(rep(0, length(components)), components); m_full[names(meteoric)] <- meteoric

  mixed <- fraction_thermal * t_full + (1 - fraction_thermal) * m_full
  mixed * (100 / sum(mixed))
}

# =============================================================================
# SELF-TEST ON REAL PUBLISHED END-MEMBERS
# =============================================================================

#' Self-test forward + inverse gas mixing using two real, cited
#' compositions -- not synthetic data:
#'  - "thermal" end-member: well 23-5, 11/5/91, from Mariner & Janik
#'    (1995) Table 2 (the same real row validated in
#'    demo_gas_geothermometry()).
#'  - "meteoric/atmospheric" end-member: standard dry-air composition
#'    (NIST/CIPM; N2 78.084, O2 20.946, Ar 0.934, CO2 0.0417,
#'    He 0.000524 mole %) -- a well-established physical constant, not
#'    a project-specific measurement, used here as a stand-in for
#'    air contamination/dilution of a fumarole gas sample (a real and
#'    common sampling artifact this project will need to screen for once
#'    Fischer's samples arrive).
#'
#' Forward-mixes the two at a chosen fraction, then inverts using the
#' N2/Ar ratio to recover that same fraction -- a round-trip consistency
#' check, exactly mirroring demo_mixing_model()'s 50/50 Cl round-trip in
#' 10_run_phreeqc_mixing.R.
demo_gas_mixing <- function() {
  message("---- Gas mixing self-test (real 23-5 gas end-member + standard dry air) ----")

  thermal <- c(CO2 = 97.7, H2S = 1.04, H2 = 0.021, CH4 = 0.0051,
               N2 = 1.21, O2 = 0, Ar = 0.018, He = 0.0022)
  air <- c(CO2 = 0.0417, H2S = 0, H2 = 0, CH4 = 0,
           N2 = 78.084, O2 = 20.946, Ar = 0.934, He = 0.000524)

  n2ar_thermal <- unname(thermal["N2"] / thermal["Ar"])
  n2ar_air <- unname(air["N2"] / air["Ar"])
  message(sprintf("  Thermal end-member N2/Ar = %.1f; air N2/Ar = %.1f (air is higher, consistent with",
                   n2ar_thermal, n2ar_air))
  message("  Mariner & Janik's own Fig. 9 interpretation that 23-5 is the *least* air-diluted sample.)")

  f_true <- 0.85  # e.g. a fumarole sample that is mostly deep gas with modest air entrainment
  mixed <- forward_gas_mixing(thermal, air, f_true)
  n2ar_mixed <- unname(mixed["N2"] / mixed["Ar"])

  recovered_f <- compute_gas_mixing_fraction(n2ar_mixed,
                                              thermal_num = unname(thermal["N2"]), thermal_denom = unname(thermal["Ar"]),
                                              meteoric_num = unname(air["N2"]), meteoric_denom = unname(air["Ar"]))
  ok <- isTRUE(all.equal(recovered_f, f_true, tolerance = 1e-6))

  message(sprintf("  Forward-mixed composition at true fraction_thermal = %.2f: CO2 = %.2f%%, N2 = %.3f%%, Ar = %.4f%%, He = %.5f%%",
                   f_true, mixed["CO2"], mixed["N2"], mixed["Ar"], mixed["He"]))
  message(sprintf("  Inverse (N2/Ar tracer) recovered fraction = %.4f (expected %.2f) -- %s",
                   recovered_f, f_true, if (ok) "PASS" else "FAIL"))

  invisible(list(thermal = thermal, air = air, mixed = mixed,
                 true_fraction = f_true, recovered_fraction = recovered_f, pass = ok))
}
