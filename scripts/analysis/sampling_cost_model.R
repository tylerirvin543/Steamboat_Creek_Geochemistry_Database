# Single source for laboratory prices and sampling-frequency cost options.
# Used by manuscript/06, manuscript/00_thesis_proposal.qmd and docs/outreach/sampling_plan_costs.qmd
# so the three documents cannot drift apart.
#
# Prices come from the laboratory invoice for one batch of 7 samples:
#   BAT-01 administration 38.57; DISP-01 disposal 22.40, LOG-22 login 13.68,
#   ME-MS14L super-trace water 602.72, MS14L-ANPH anions by IC 519.20 (7 samples).
# Uncertain: whether BAT-01 is per batch (assumed) or per sample, and shipping (not on the
# invoice; planning range $20-50 per shipment). Isotopes (outside lab) are a planning estimate.

lab_invoice <- data.frame(
  code = c("BAT-01", "DISP-01", "LOG-22", "ME-MS14L", "MS14L-ANPH"),
  item = c("Administration fee", "Disposal of all sample fractions", "Sample login, received without barcode",
           "Super-trace analysis of water", "Anions by ion chromatography"),
  invoice_usd = c(38.57, 22.40, 13.68, 602.72, 519.20),
  scales_with = c("batch (assumed)", rep("sample", 4)),
  stringsAsFactors = FALSE
)
invoice_n_samples <- 7

unit_costs <- function() {
  li <- lab_invoice
  is_batch <- grepl("^batch", li$scales_with)
  li$unit_usd <- ifelse(is_batch, li$invoice_usd, li$invoice_usd / invoice_n_samples)
  list(
    table = li,
    batch = li$unit_usd[is_batch],
    batch_per_sample = li$invoice_usd[is_batch] / invoice_n_samples,
    sample = sum(li$unit_usd[!is_batch]),
    analysis_only = sum(li$unit_usd[li$code %in% c("ME-MS14L", "MS14L-ANPH")]),
    isotope = 40
  )
}

fmt_usd <- function(x) paste0("$", formatC(round(x), format = "d", big.mark = ","))

# Scenarios for the uncertain inputs.
cost_scenarios <- list(
  low     = list(bat = "batch",  ship = 20, ship_mode = "monthly"),
  central = list(bat = "batch",  ship = 35, ship_mode = "monthly"),
  high    = list(bat = "sample", ship = 50, ship_mode = "visit")
)

# Routine sampling Dec 2026 to Sep 2027 = 10 months after a 7-day daily window in Nov 2026.
routine_months <- 10

# Cost of one design. `visits` = routine visits to SBRR + SBGG; extra_* = add-on sites.
design_cost <- function(visits, iso_samples, scenario = "central", months = routine_months,
                        window_days = 7, storm_events = 2, sites = 2,
                        extra_sites = 0, extra_visits = 0, extra_iso = 0, qa_frac = getOption("steamboat.qa_frac", 0.10)) {
  u <- unit_costs(); sc <- cost_scenarios[[scenario]]
  chem <- visits * sites + window_days * sites + storm_events * sites + extra_sites * extra_visits
  qa <- ceiling(chem * qa_frac)
  n <- chem + qa
  ships <- (if (sc$ship_mode == "monthly") months else visits) + (window_days > 0) + storm_events
  lab <- n * u$sample + if (sc$bat == "batch") ships * u$batch else n * u$batch_per_sample
  shipping <- ships * sc$ship
  iso <- (iso_samples + extra_iso) * u$isotope
  data.frame(chem_samples = n, qa = qa, shipments = ships, iso_samples = iso_samples + extra_iso,
             lab = lab, shipping = shipping, iso = iso, total = lab + shipping + iso,
             discharge_dates = visits + window_days + storm_events, stringsAsFactors = FALSE)
}

# Options. A/B = creek only; C = B2 plus four fissure-area sites (monthly) with isotopes.
sampling_options <- function(extra_visits = routine_months) {
  o <- data.frame(
    option = c("A1. Monthly", "A2. Monthly + isotopes", "B1. Biweekly", "B2. Biweekly + isotopes",
               "C. B2 + fissure-area sites"),
    chem_cadence = c("Monthly (10 visits)", "Monthly (10 visits)", "Every 2 weeks (21 visits)",
                     "Every 2 weeks (21 visits)", "Every 2 weeks (21 visits) plus 4 add-on sites monthly"),
    iso_cadence = c("none", "every visit, both sites", "none", "every visit, both sites",
                    "every visit, all sites"),
    visits = c(10, 10, 21, 21, 21),
    iso = c(0, 20, 0, 42, 42),
    extra_sites = c(0, 0, 0, 0, 4),
    extra_iso = c(0, 0, 0, 0, 4 * extra_visits),
    stringsAsFactors = FALSE)
  spec <- o
  one <- function(i, s) design_cost(spec$visits[i], spec$iso[i], s, extra_sites = spec$extra_sites[i],
                                    extra_visits = if (spec$extra_sites[i] > 0) extra_visits else 0,
                                    extra_iso = spec$extra_iso[i])
  cen <- do.call(rbind, lapply(seq_len(nrow(o)), one, s = "central"))
  o <- cbind(o[c("option", "chem_cadence", "iso_cadence")], cen)
  tot <- sapply(c("low", "central", "high"), function(s) vapply(1:nrow(o), function(k) one(k, s)$total, numeric(1)))
  o$total_low  <- apply(tot, 1, min)
  o$total_high <- apply(tot, 1, max)
  o$cost_per_discharge <- o$total / o$discharge_dates
  o
}

# Phase split: Phase 1 = intensive calibration window (notebook 09 Tier 1, 2-4 weeks, daily; isotopes
# every 3rd day at both sites); Phase 2 = monthly or biweekly sampling with 2 storm events (Tier 2).
# Returns central-scenario cost of each phase and the combined total for window lengths of 7, 14 and 28 days.
phase_split <- function(windows = c(7, 14, 28)) {
  p2 <- list(A1 = design_cost(10, 0, window_days = 0), A2 = design_cost(10, 20, window_days = 0),
             B1 = design_cost(21, 0, window_days = 0), B2 = design_cost(21, 42, window_days = 0))
  do.call(rbind, lapply(windows, function(w) {
    p1 <- design_cost(0, 2 * ceiling(w / 3), window_days = w, storm_events = 0)
    do.call(rbind, lapply(names(p2), function(n) data.frame(
      window_days = w, phase2 = n, phase1_samples = p1$chem_samples, phase1_cost = p1$total,
      phase2_samples = p2[[n]]$chem_samples, phase2_cost = p2[[n]]$total,
      combined = p1$total + p2[[n]]$total, stringsAsFactors = FALSE)))
  }))
}
