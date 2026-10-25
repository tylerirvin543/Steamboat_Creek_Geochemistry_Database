# Project Roadmap: Steamboat Hills Geothermal Outflow

A strategic, project-level view of where the database and thesis stand,
what's blocking further progress, and where to go from here. Complements
(does not duplicate) `docs/action_items_for_user.md`, which is a short,
field-work-facing checklist -- this document is the "why it matters and
what's next" reference behind that checklist, and the source material
`AGENTS.md`'s 34 session logs and README's "Planned:" sections should be
consulted for full technical detail on anything summarized here.

Last updated: 2026-10-25.

## 1. Confirmed findings to date

These are real results, computed against real data, with stated caveats --
not aspirational claims:

- **Chloride remains the dominant conservative thermal-water tracer at
  Steamboat**, exactly as Sorey (1992, 2008, 2017) established. This
  project's own 2026 samples reproduce the expected Na-Cl-K-SO4-vs-Ca-Mg
  chemical dichotomy (correlation matrix + PCA + hierarchical facies
  clustering all independently agree; PC1 alone explains ~67% of major-ion
  variance).
- **The thermal-water Cl/B ratio is stable but has shifted slightly**: 19.6
  (1950-1991, Sorey & Colvard) vs. 21.9 (2024-2026, this project's own real
  thermal samples) -- small but statistically significant (t-test, p=0.015).
  Read as "essentially the same conservative signature, not literally
  unchanged," a more precise claim than earlier session notes made.
- **Any long-term Cl decline is genuinely ambiguous with current data**: a
  naive pooled regression is significant (p=0.0099) but not robust to which
  wells count as "thermal" (p=0.099 excluding two intermediate NDEP wells);
  a facies-restricted mixed-effects model finds no significant trend; a
  population-level mixed-effects model (this project's newest analysis)
  finds a borderline positive trend driven more by which locations have
  been sampled when than by a real per-site process. **Open question, not
  resolved** -- more repeat sampling of the *same* wells across eras is
  what would actually settle this.
- **Real PHREEQC speciation/saturation-index results** exist for 233
  eligible samples (225 NDEP background + 8 real thermal). The 8 real
  thermal samples sit near quartz/chalcedony equilibrium and mildly-to-
  moderately supersaturated with respect to calcite/dolomite -- consistent
  with known carbonate-scaling behavior in these waters.
- **Na/K geothermometers (154-256°C) systematically exceed quartz/
  chalcedony geothermometers (52-127°C)** for the same real thermal
  samples -- read as a real, geologically informative divergence (silica
  re-equilibrates/dilutes faster than Na/K en route to discharge), not a
  contradiction to resolve away.
- **A real two-end-member conservative-mixing model, run against every real
  Cl-bearing sample** (not just a synthetic test), shows the expected
  smooth rise in calcite/dolomite saturation with mixing fraction, a
  comparatively flat quartz response (consistent with the geothermometer
  divergence above), and one real sample (SBW_0002) that is *more*
  concentrated than the chosen thermal reference itself -- a genuine,
  not-yet-explained finding worth a specific follow-up sample.
- **Barometric efficiency, computed for the first time against real paired
  water-level/pressure data**, gives BE = 0.29-0.60 for two South Truckee
  Meadows wells (STMGID MW3/MW10) -- inside the historically-expected
  0.2-1.18 range (White 1968) and used to derive a project-wide
  `aquifer_type` classification (7 wells now classified "confined"). No
  real Steamboat-field spring/production well yet has the paired data
  needed for a *site-specific* BE.
- **A real hourly temperature-vs-barometric-pressure test** finds a small
  but statistically significant inverse coupling at the hottest logger
  (A009, r=-0.17, p<1e-10) consistent with boiling-point-suppression
  behavior -- but no significant coupling at the widest-range fumarole
  logger (A005), a genuine mixed result worth keeping in mind before
  assuming this mechanism applies uniformly.
- **A gas-informed parent-fluid reconstruction, run independently from two
  real discharge points** (the fissure SBF_0001 and the resort-tank well
  SBW_0002), converges to within ~2% on chloride once each is corrected
  for steam loss and re-equilibrated with the one real fissure gas sample
  on file -- real, if single-gas-sample, evidence both points share one
  deep source. A six-database sensitivity sweep on this reconstruction
  found and mechanistically explained a real pH divergence (traced to
  each sample's own measured starting pH, not database choice or gas-load
  size).
- **A real forward-mixing model (fissure + SBRR) tested against the four
  real Low Sinter Terrace downgradient targets** (SBW_0001 and the three
  real LST springs SBS_0001/0002/0003) shows the three springs sitting
  reasonably close to the pure-conservative-mixing curve on calcite/
  dolomite SI and pH, while **SBW_0001 is a clear, repeatable outlier**
  well above the curve on every panel -- real evidence it taps a
  geochemically distinct aquifer from the springs, not just dilution
  noise. Hot spring 6 and GS-5 were explicitly tested and excluded as
  targets: both are confirmed Main Terrace features (this project's own
  Locations label, plus White 1964's own text), not Low Terrace.
- **Every real PHREEQC inverse-modeling attempt on file -- the original
  2026-09 Soccer Field run and the newer SBW_0001/SBS_0001 runs -- now
  honestly reports zero feasible models**, after a real parser bug (found
  2026-10-25) that had misread PHREEQC's own echoed-back input as a false
  "1 candidate solution" was fixed. A bounded follow-up (adding Quartz as
  a candidate phase, varying which elements are explicitly mass-balanced,
  scanning uncertainty from 5-15%) found SBW_0001's own residual is a
  genuine, Ca-specific infeasibility unaffected by any of those choices --
  11% uncertainty is the closest approach to feasible found (a single
  residual at the numerical noise floor) before the solver destabilizes
  at 12%+. This is a real, current limit of what two-end-member-plus-
  carbonate inverse modeling can resolve for this system, not a software
  bug waiting to be fixed.
- **A real forward PHREEQC REACTION-path titration, built as the direct
  complement to the SBW_0001 inverse-modeling null result above, finds a
  genuine interior optimum, not a full reconciliation.** Mixing the
  fissure and SBRR at their real, stored conservative mixing fraction,
  then explicitly titrating calcite and dolomite mass transfer (both
  net precipitation and net dissolution) and comparing against SBW_0001's
  real chemistry, shows the combined Ca/Mg/Alkalinity error drop from
  ~45-48% at pure conservative mixing to ~23% at a modest net
  *dissolution* of both minerals (~1.2e-4 mol combined) -- a real,
  substantial improvement over mixing alone, but alkalinity never fully
  closes even across a wide explored range. Chloride stays exactly
  conservative across every step (confirming the titration only moves
  carbonate species, as intended). The inverse and forward results agree:
  simple two-end-member-plus-carbonate mixing cannot fully explain
  SBW_0001, but real net carbonate dissolution along this flowpath is a
  genuine part of the answer. New `PHREEQC_Reaction_Path_Runs`/
  `PHREEQC_Reaction_Path_Steps` tables, `scripts/phreeqc/
  16_reaction_path_titration.R`, `data/raw/phreeqc/reaction_path_config.csv`,
  `RUN_ANALYSIS$phreeqc_reaction_path`.
- **Running the same forward titration against the three real Low Sinter
  Terrace springs does not simply confirm the earlier saturation-index-
  only picture.** SBS_0002 needs almost no reaction correction (fit
  quality barely changes from pure mixing), SBS_0003 needs a small
  correction and fits well (19.7% combined error, the best of the four
  real targets), but SBS_0001 shows the *worst* fit of all four even
  after titration (44.5%) -- its real calcium sits above anything the
  physically available reaction-progress range can reach, while its real
  alkalinity sits below the titrated curve at every explored point,
  including the most negative step the real Ca/Mg/C pool can support.
  These two demands pull in opposite directions that a simple two-phase
  calcite/dolomite model cannot reconcile. SBW_0001 still needs by far
  the largest correction and shows the largest absolute improvement, but
  it is no longer the only target this model struggles with -- SBS_0001
  does too, for a different, specific reason worth its own follow-up.
- **SBW_0002 (the resort tank), run as a reaction-path target for the
  first time, fits far better than any other target -- but only after a
  necessary, explicitly-stated adjustment.** Its own stored mixing
  fraction (1.043) slightly exceeds the valid 0-1 range (already
  documented: SBW_0002 is more concentrated than the fissure reference
  itself). Clamped to 1.0 (pure fissure end-member, no dilution) with an
  explicit warning rather than silently failing, the titration then
  finds a combined Ca/Mg/Alkalinity error of only 4.6% at a tiny net
  precipitation -- by far the best fit of any real target tested on this
  flowpath, consistent with the fissure and resort tank being the two
  most chemically similar real points on the whole flowpath.
- **A real stale-R-session bug found and fixed while running the
  Anhydrite/Gypsum/Fluorite sensitivity tests, not a bug in any file on
  disk.** A long-running R session had an old, pre-fix `lab_analyte_map`
  object cached in its global environment (`phreeqc_name = "SO4"`
  instead of the real, already-corrected `"S(6)"` on disk) --
  `.phreeqc_analyte_map()`'s `if (!exists(...))` guard saw the stale
  object and never re-sourced the real file, silently zeroing SO4/SiO2
  in every SOLUTION block generated that session. Harmless for
  Calcite/Dolomite-only titrations (which never use SO4), but it broke
  Anhydrite/Gypsum runs outright (negative-concentration errors, since
  the mixed solution had essentially zero real sulfate to react with).
  Fixed by removing the stale object and re-sourcing; a reminder that a
  long-lived interactive session can silently diverge from the real,
  already-correct files on disk.

## 2. Major roadblocks (and what unblocks each)

| Roadblock | Blocks | What unblocks it |
|---|---|---|
| Real chemistry samples don't temporally overlap the conductivity-logger deployment window | The whole Cl-sampling-frequency calibration workstream (`notebooks/01`); real (not representative-pair) mixing/inverse PHREEQC modeling | New Cl samples collected *during* an active logger deployment -- see Section 5 (sampling campaign) below |
| Too few in-field wells have current, usable water levels (only 2-3, vs. 21 in the wider, different South Truckee Meadows basin) | A real potentiometric surface; a site-specific (not STMGID-basin) barometric efficiency | The standing NDEP data request (`docs/action_items_for_user.md` #1) for daily water levels at 43-33-1/21-32-1/21-32-2, OW-1/2/3, and the stratigraphic test wells |
| No digitized fault traces exist anywhere in this project | Leapfrog 3D geologic model; fault-bounded PHREEQC end-member grouping; MODFLOW zonation | Digitizing Collar & Huntley (1990) Figure 1 in ArcGIS (your own stated next task) -- schema/ingest already built and waiting (`ingest_fault_traces.R`) |
| ~~`Well_Lithology` is almost entirely unusable OCR garbage (5 rows, all unconfirmed)~~ **Substantially improved 2026-09-26** -- added a controlled `formation_unit` vocabulary (Qal/Tv/AltKgdpKm/Kgd, matching Skalbeck 2001's own model units) alongside the free-text `description`; classified the 2 confirmed literature-sourced rows (83C-6ST1) and added 58 new real intervals for 10 wells from Skalbeck (2001) Table 3's own depth logs | A real Leapfrog lithology layer (now real for 12 wells + all 241 Skalbeck Table A-2 grid points via `geophysical_lithology_intervals.csv`); subsurface stratigraphic interpretation | The remaining well-log-OCR-derived rows stay unconfirmed/unclassified (`unknown`) -- still needs OCR-quality improvement or more literature-sourced logs like Akerley et al. (2021) |
| ~~Skalbeck (2001) Table B-2's Flame and Steinhardt monthly series could not be confidently resolved from OCR text alone~~ **Resolved 2026-09-26** -- both transcribed directly from a clean user-supplied table image (not OCR) and ingested (35 + 17 real monthly rows) | Densifies the pre-2000 Cl/B/temperature record for these two wells (see `notebooks/07_historical_context_sorey1992.qmd`'s new Skalbeck section) | No longer a roadblock; positional-date caveats are documented in `scripts/ingest/ingest_historical_skalbeck2001.R`'s own header comment (Flame assumed strict monthly from Jan-1985; Steinhardt anchored by value-match to a real 1991-11-08 sample) |
| Skalbeck (2001) Table A-2 has 112 of 353 rows with real column-position ambiguity that arithmetic cross-checking can't safely resolve (a physically-implausible Alt-thickness > Kgd-depth result on one hypothesis) | The full 353-point depth grid (currently 241/353 ingested) | Needs review against the actual scanned page images (Appendix A, pp.191-199), not OCR text alone -- logged to `data/derived/skalbeck2001_table_a2_ambiguous_rows.csv` |
| Logger measurement-uncertainty now has real manufacturer specs (`Logger_Specifications`) and real field calibration checks (`Logger_Calibration_Checks`, 10 real temperature checks auto-detected from Field_Measurements) but conductivity has only 1 real candidate check, and it falls outside the 4-hour matching tolerance | A real conductivity calibration-check example (temperature already has 10) | Needs a future field visit's lab/handheld conductivity reading taken closer in time to a logger reading, or a documented decision to widen the matching tolerance |
| Pine Tree Ranch #2 and SBG-TH1/2/3's real water-level-only time series (a separate, structurally simpler section at the end of Table B-2 -- no chemistry, just monthly depth-to-water) has not been transcribed | Extending real water-level history for these wells | Structurally much simpler than the chemistry blocks (3 clean depth-only columns, no Cl/B/Temp disambiguation needed) -- a good, fast next win once picked up |
| ~~`PHREEQC_Inverse_Results`' mineral mass-transfer numbers were never correctly parsed~~ **Root cause found 2026-10-25: there was no real solution to parse numbers from at all.** The parser bug (confirmed 2026-09-26) was compounded by a deeper one in `run_phreeqc_inverse()` itself: it never checked PHREEQC's own "Number of models found" summary line, so it reported a false "1 candidate solution" for a run PHREEQC's own output says found 0 feasible models. Fixed 2026-10-25 (`scripts/phreeqc/11_run_phreeqc_inverse.R`) -- every real inverse run on file (the original Soccer Field run, plus new SBW_0001/SBS_0001 attempts) now honestly reports 0 feasible models | Any inverse-model mass-transfer figure/interpretation | Still needs a real, geochemically feasible inverse-model solution before there is anything to extract mass-transfer numbers from -- e.g. more/different candidate phases, a real time-paired end-member set, or a loosened (but still defensible) uncertainty bound. A forward REACTION-path titration (Section 1, 2026-10-25) sidesteps this for SBW_0001 specifically, finding a real interior optimum without needing the inverse solver to converge at all |
| No geolocated southwest/west-of-Steamboat regional groundwater sample exists in this project | A true, defensible meteoric/dilution end-member for the Lower Sinter Terrace mixing model (per White's own documented Carson/Virginia Range mountain-front recharge direction) | A real coordinate for a candidate like Jumbo Grade Spring, or a new sample from a confirmed southwest/west domestic well/spring -- SBRR (real, located, but itself carrying a modest thermal signature) is used as a conservative stand-in in the meantime |
| SBW_0001 and the fissure (SBF_0001) -- the two real 2026 sampling points central to the current flowpath model -- have NO depth, completion, or lithology data on file at all | Turning the real SBW_0001-vs-springs chemical divergence (Section 1) into an aquifer-level explanation; any real multi-aquifer mixing model for this flowpath | A well log, driller's report, or geophysical survey at either point -- the single biggest concrete subsurface-data gap on the current flowpath |
| No MODFLOW grid, boundary conditions, recharge estimate, or K-field zonation exists | Any groundwater flow model | Needs the fault/lithology roadblocks above resolved first, plus a real recharge estimate (the one real Dec-2025-storm water-level response at STMGID MW10 is a start, not a calibration) |

## 3. Future directions, sequenced

**Near-term (doable now, no new field data or external-tool dependency):**
- An ArcGIS Empirical Bayesian Kriging (or IDW) surface over the real
  763-point `chloride_points` GeoPackage layer -- does not need the blocked
  water-level data, only real Cl samples already on file. The single most
  valuable ArcGIS figure achievable this year independent of the
  potentiometric-surface blocker.
- Find a real, geochemically feasible inverse-model solution (Section 2 --
  every real attempt so far genuinely finds 0 feasible models, not just an
  unparsed one) before a real mineral-mass-transfer figure is possible.
- A true transect-based 2D well cross-section (distinct from the existing
  name-ordered "type-log gallery" in `well_completion_profile.R`) using
  already-available collar/completion-interval data.
- Consolidate notebook 08's individual statistics into a single summary
  table (mirroring notebook 07's) and a cross-notebook effect-size/CI
  "forest plot" for at-a-glance interpretability.
- Fix `website/results.Rmd`'s hardcoded discharge-timeline chart to reuse
  notebook 07's live-query version (currently two independently-maintained
  copies of the same data).
- ~~Given inverse modeling's real, repeated inability to find a feasible
  solution for SBW_0001, try a real forward reaction-path model~~ **Done
  2026-10-25** -- see Section 1's new forward-titration finding above.
  ~~Next: run the same method against the three real LST springs~~ **Also
  done 2026-10-25** -- did NOT simply confirm the earlier saturation-
  index-only read: SBS_0002 needs almost no correction, SBS_0003 fits
  well with a small one, but SBS_0001 shows the WORST combined Ca/Mg/
  Alkalinity fit of all four real targets, because its real calcium and
  alkalinity pull the model in opposite directions a two-phase titration
  cannot reconcile over the physically available range. New follow-on:
  ~~work out what is specifically different about SBS_0001~~ **Partially
  done, same day**: tested a third candidate phase (anhydrite, gypsum,
  anhydrite+fluorite) and two alternate meteoric end-members (Tick
  Spring, Jumbo Grade Spring, both real chemistry with no coordinate on
  file). Every variant improves on the 44.5% baseline somewhat; the best
  single result scored fairly (fixed Ca/Mg/Alkalinity basis) is Tick
  Spring at 33.4%; honestly including fluorite's own real fluoride
  prediction (a real bug -- F was missing from PHREEQC's requested
  output -- found and fixed) flips part of the ranking, making the
  combined anhydrite+fluorite+Tick-Spring variant the single best result
  of any tested at 30.6%. None fully resolves the tension. A real,
  model-free Piper diagram does NOT show SBS_0001 visually separating
  toward the sulfate corner the way the hypothesis predicted -- chloride
  dominates the anion budget too heavily for the real but modest sulfate
  excess to show up in charge-equivalent percentage terms. New real
  finding: SBS_0001 and SBW_0001 sit only 109 m apart (real haversine
  distance) yet show two of the most different fit behaviors on this
  flowpath -- a concrete, mapped instance of this project's own
  proximity-does-not-imply-chemistry principle. New
  `scripts/analysis/lst_map_and_piper_figures.R`
  (`build_lst_proximity_map_figure()`, `build_lst_piper_diagram()`).

**Medium-term (your own field/GIS work, this thesis year):**
- The SBRR/SBGG calibration sampling campaign (Section 5) -- directly
  informs the Cl-EC relationship the whole conductivity-as-proxy thesis
  premise depends on.
- A real well log, driller's report, or geophysical survey at SBW_0001
  and/or the fissure (SBF_0001) -- the single biggest concrete subsurface
  gap on the current flowpath (Section 2), and the most direct way to
  confirm or rule out SBW_0001 tapping a distinct aquifer.
- A real, same-day synoptic sampling round across the fissure, resort
  well, SBW_0001, the three LST springs, and SBRR together -- removes the
  "representative, not time-paired" caveat that still qualifies every
  real mixing/inverse result in this project.
- Pin down a real coordinate for Jumbo Grade Spring (or sample a
  confirmed southwest/west well/spring instead) to get a true, non-
  conservative meteoric end-member in place of SBRR.
- Fault digitization (Collar & Huntley 1990 Figure 1) -> real Leapfrog 3D
  model -> fault-aware PHREEQC end-member regrouping.
- Following up on the NDEP water-level request to eventually support a
  real potentiometric surface.

**Longer-term (needs the above resolved first):**
- A MODFLOW grid informed by the Leapfrog 3D model's hydrostratigraphic
  zones and the barometric-efficiency-derived K-field starting point.
- Expanded PHREEQC reaction-path modeling (temperature/degassing ramps
  between real end-members) once more real, temporally-paired samples
  exist to choose better end-members from.
- Expanded gas geothermometry/gas mixing once a real dissolved-gas sample
  set exists (the D'Amore-Panichi and gas-mixing modules are built and
  validated against literature values, just never run on this project's
  own real gas chemistry).

## 4. A note on spatial position vs. chemistry (your own stated concern)

Worth stating explicitly, since it shapes how PHREEQC modeling should be
framed going forward: **a defensible mixing/reaction-path model is built
from conservative-tracer chemistry (which samples are real, credible
end-members), not from map proximity.** Two samples that happen to be
close together are not necessarily hydraulically connected, and two that
are far apart are not necessarily unconnected -- Leapfrog/MODFLOW's role is
to *test or inform* connectivity using independent evidence (heads, faults,
lithology), which can then be used to sanity-check or select among
chemically-plausible end-member pairs, not to define the chemistry itself.
The real two-end-member mixing model already in this project (Section 1)
follows exactly this logic: the fissure (SBF_0001) and SBRR were chosen for
being chemically distinct real end-members (Cl = 815 vs. 17 mg/L), not for
being spatially adjacent -- and an earlier choice in this same thread,
Boyd Domestic Well, was dropped specifically because its chemistry (Ca and
Mg far below plausible regional norms) didn't hold up, not because of its
location. The reverse mistake was also caught and corrected directly: hot
spring 6 and GS-5 looked like plausible nearby targets by name alone, but
are both confirmed Main Terrace features once actually checked against
this project's own data and White's (1964) original text -- a real
reminder that proximity on a map (or in a name) is not a substitute for
checking the actual identity and chemistry of a point. Keep this framing
in both the thesis text and any future Leapfrog-informed remodeling.

## 5. SBRR/SBGG calibration sampling campaign (thesis-year planning)

See the dedicated planning document/notebook (Section 6 of the manuscript,
and a standalone field-ready version) for the full analysis. Headline
recommendation, informed by the real diurnal/spectral structure already
characterized in `notebooks/01_conductivity_temporal_structure.qmd`:

- **A short (2-4 week), sub-daily-to-daily intensive campaign at both SBRR
  and SBGG early in the field season**, specifically to (a) establish a
  real Cl-EC calibration relationship for the first time with enough
  temporally-overlapping pairs, and (b) directly test whether short-term Cl
  variability tracks EC's own real diurnal signal.
- **A lower-frequency (biweekly-to-monthly) campaign for the remainder of
  the year**, with extra samples deliberately bracketing large storms and
  spring runoff (informed by the real, detectable precipitation-response
  signal already found at STMGID MW10).
- This design is testable against real data you already have (the
  conductivity record) *before* committing a year of field effort to it --
  see the Monte Carlo subsampling analysis for the quantitative version of
  this recommendation.

## 6. Thesis-writing structure going forward

- `notebooks/01`-`08` (+ `00_full_report.qmd`) stay **database/pipeline
  documentation** -- code-paired, living reference material, not meant to
  be read as a manuscript.
- A new `manuscript/` folder is the **actual scientific write-up**
  (introduction, geochemical background, methods, results, discussion),
  aimed at eventually becoming real thesis chapters/an article draft, using
  a real `.bib` file for proper citations rather than prose links. See
  `manuscript/README.md` once built for its own structure.
- `docs/literature/annotated_bibliography.qmd` stays a separate, broader
  reading-notes document (not manuscript-ready citations).

## 7. Known, deliberately-not-fixed cosmetic/process items

- `notebooks/00_full_report.qmd`'s rendered PDF has one stray auto-title
  page (page 1) before the correct one (page 2) -- a pandoc frontmatter-
  merge quirk, documented in that file's own body, not chased further
  given the risk/reward of the fix attempted.
- `data/derived/qc/` stays untracked in git by design (disposable,
  regenerable QC output).
