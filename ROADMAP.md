# Project Roadmap: Steamboat Hills Geothermal Outflow

A strategic, project-level view of where the database and thesis stand,
what's blocking further progress, and where to go from here. Complements
(does not duplicate) `docs/action_items_for_user.md`, which is a short,
field-work-facing checklist -- this document is the "why it matters and
what's next" reference behind that checklist, and the source material
`AGENTS.md`'s 34 session logs and README's "Planned:" sections should be
consulted for full technical detail on anything summarized here.

Last updated: 2026-09-26.

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

## 2. Major roadblocks (and what unblocks each)

| Roadblock | Blocks | What unblocks it |
|---|---|---|
| Real chemistry samples don't temporally overlap the conductivity-logger deployment window | The whole Cl-sampling-frequency calibration workstream (`notebooks/01`); real (not representative-pair) mixing/inverse PHREEQC modeling | New Cl samples collected *during* an active logger deployment -- see Section 5 (sampling campaign) below |
| Too few in-field wells have current, usable water levels (only 2-3, vs. 21 in the wider, different South Truckee Meadows basin) | A real potentiometric surface; a site-specific (not STMGID-basin) barometric efficiency | The standing NDEP data request (`docs/action_items_for_user.md` #1) for daily water levels at 43-33-1/21-32-1/21-32-2, OW-1/2/3, and the stratigraphic test wells |
| No digitized fault traces exist anywhere in this project | Leapfrog 3D geologic model; fault-bounded PHREEQC end-member grouping; MODFLOW zonation | Digitizing Collar & Huntley (1990) Figure 1 in ArcGIS (your own stated next task) -- schema/ingest already built and waiting (`ingest_fault_traces.R`) |
| `Well_Lithology` is almost entirely unusable OCR garbage (5 rows, all unconfirmed) | A real Leapfrog lithology layer; any subsurface stratigraphic interpretation | Either OCR-quality improvement on the well-log pipeline (diminishing returns already documented) or literature-sourced lithology like the one real Akerley et al. (2021) interval already added for well 83C-6ST1 -- the latter is more promising |
| Skalbeck (2001) Table B-2's real monthly 1985+ Cl/B/temperature/depth-to-water time series is too OCR-degraded to auto-parse reliably | Densifying this project's Cl/B record for Brown School, Curti Geothermal/Domestic, Herz Geothermal/Domestic, and more (potentially hundreds of real dated observations) | A careful, manual, row-by-row transcription against the original scanned pages (or against the cleaner plotted figures already in `docs/figures/Skalbeck_2001_*.png`), the same kind of manual-transcription effort already done for several NDWR well logs |
| `PHREEQC_Inverse_Results`' mineral mass-transfer numbers were never correctly parsed (confirmed 2026-09-26 while building the real-mixing figure -- see notebook 06) | Any inverse-model mass-transfer figure/interpretation | A parser fix reading the run's raw `.pqo` output directly for the real "Phase mole transfers" section header |
| No MODFLOW grid, boundary conditions, recharge estimate, or K-field zonation exists | Any groundwater flow model | Needs the fault/lithology roadblocks above resolved first, plus a real recharge estimate (the one real Dec-2025-storm water-level response at STMGID MW10 is a start, not a calibration) |

## 3. Future directions, sequenced

**Near-term (doable now, no new field data or external-tool dependency):**
- An ArcGIS Empirical Bayesian Kriging (or IDW) surface over the real
  763-point `chloride_points` GeoPackage layer -- does not need the blocked
  water-level data, only real Cl samples already on file. The single most
  valuable ArcGIS figure achievable this year independent of the
  potentiometric-surface blocker.
- Fix `PHREEQC_Inverse_Results`' parser gap (Section 2) and build the real
  mineral-mass-transfer figure once the numbers are trustworthy.
- A true transect-based 2D well cross-section (distinct from the existing
  name-ordered "type-log gallery" in `well_completion_profile.R`) using
  already-available collar/completion-interval data.
- Consolidate notebook 08's individual statistics into a single summary
  table (mirroring notebook 07's) and a cross-notebook effect-size/CI
  "forest plot" for at-a-glance interpretability.
- Fix `website/results.Rmd`'s hardcoded discharge-timeline chart to reuse
  notebook 07's live-query version (currently two independently-maintained
  copies of the same data).

**Medium-term (your own field/GIS work, this thesis year):**
- The SBRR/SBGG calibration sampling campaign (Section 5) -- directly
  informs the Cl-EC relationship the whole conductivity-as-proxy thesis
  premise depends on.
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
follows exactly this logic: SBF_0001 and Boyd Domestic Well were chosen for
being chemically distinct real end-members (Cl = 815 vs. 45 mg/L), not for
being spatially adjacent. Keep this framing in both the thesis text and
any future Leapfrog-informed remodeling.

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
