# Action Items for Tyler (outside the database)

A personal working checklist of things that need *your* action — field
work, external data requests, ArcGIS digitizing, or a judgment call —
rather than more pipeline code. Not part of the rendered website or
report. Updated 2026-09-25/26.

## 1. NDEP data requests (what / where / when)

An email covering most of this was already drafted in an earlier
session (see `AGENTS.md` "Session 4" for the exact wording/date sent) to
an NDEP contact, referencing NDEP's own Temporary UIC Permit
UNEV2007204T2025-1 REVISED (June 2025). If a reply hasn't come back yet,
or a follow-up is due, the concrete asks are:

- **Daily water-level/pressure data** for wells `43-33-1`, `21-32-1`,
  `21-32-2` (the three deep, actively-monitored wells the UIC permit
  itself references) — this is the single biggest blocker to a real
  potentiometric surface. Right now only 2-3 wells *inside* the
  Steamboat field have any usable water-level record at all (see
  `notebooks/07_historical_context_sorey1992.qmd`'s potentiometric-
  feasibility section) — everything else with continuous water level
  (STMGID MW3/MW10, etc.) is in the wider South Truckee Meadows basin,
  not the field itself.
- **Fumarole inspection logs** — referenced in the permit, not yet
  received.
- **Water levels for OW-1/OW-2/OW-3 and the stratigraphic test wells**
  (`strat 2/5/6/7/8/9/13/14`) — these are registered in the database as
  provisional, coordinate-less `Wells` rows (from Sorey & Colvard 1992
  Table 8) with zero water-level history.
- **Chemistry for the standing monitoring network**: NDOT, Herz, Boyd,
  Soccer Field, Eich, Jeppson, Rogers wells — some of these already
  have historic chemistry promoted from NDEP PRR documents, but a
  *current* round would help close the Cl-sampling-frequency gap below.
  **Partially addressed 2026-10-01**: real field parameters (pH,
  specific conductance, temperature) now exist for all of these wells
  through 12/12/2025 (a real ~3-month, roughly monthly record — see
  AGENTS.md Session 42's "42-row OCR batch" addendum) — but this is
  still field parameters only, **not lab chemistry/chloride**, so the
  Cl-sampling-frequency gap below is unchanged.
- **More precise surveyed well coordinates** where NDEP has them — most
  of this project's well coordinates come from NBMG/ArcGIS-digitization
  with 50-800 m uncertainty, not a real survey.

**Why it matters, concretely:**
- Potentiometric mapping needs deeper-well water levels (above).
- The Cl-sampling-frequency workflow (`notebooks/01_...qmd`,
  `scripts/analysis/sampling_frequency/`) is fully built and self-tested
  but still has **zero real Cl-conductivity pairs**, because the only
  real Cl chemistry on file predates the conductivity logger deployment
  by ~2.5 months. Any new chemistry sample collected *during* an active
  logger deployment window would unlock this immediately.
- Real (not representative/typical) mixing and inverse-modeling
  end-members for PHREEQC still need a genuinely paired thermal +
  meteoric sample set collected close together in time.

## 2. Fault digitization (you mentioned this is next)

- Recommended source: **Collar & Huntley (1990) Figure 1** — a real
  fault + air-photo-lineament map with ~10 already-coordinated wells
  visible on it, making it easier to georeference than the Dhakal flow
  diagram (which has no fault traces at all).
- Digitize in ArcGIS using this project's own well coordinates
  (exportable today via `export_geopackage()`'s `wells` layer) as
  control points.
- Save the resulting shapefile under **`data/raw/arcgis/faults/`**.
- The receiving pipeline is already built and waiting:
  `database/schema/11_fault_traces_schema.R` (`Fault_Traces`/
  `Alteration_Zones` tables) + `scripts/ingest/ingest_fault_traces.R`
  (wired into `run_pipeline.R` as `RUN_INGEST$fault_traces`) — currently
  a safe no-op since no shapefile exists yet. Distinguishes mapped
  faults (inferred/concealed) from air-photo lineaments, per Collar &
  Huntley's own legend, so keep that distinction in your ArcGIS
  attribute table if possible.
- Once faults exist, the persisted `Facies_Clusters` GeoPackage layer
  (`facies_clusters`, 132 real points) is ready to overlay against them
  directly in ArcGIS.

## 3. Well-identity confirmations pending your judgment

- ~~Log 61248 → well 23-5~~ — **done this session** (2026-09-26):
  promoted, including its 3 lithology intervals and 1 work-event record.
- **Log 123802 vs. well 43-33**: 18 m coordinate match (the tightest
  found anywhere in the well-log matching work) but an 8-year
  completion-date gap (123802 completed 2015; 43-33 drilled 2007) — not
  promoted. Your call on whether this is a dedicated adjacent monitor
  well or a re-permitted secondary use of 43-33 itself.
- **`data/derived/well_log_match_candidates.csv`** (regenerated every
  pipeline run by `qc_well_log_matches.R`) currently has 2 rows for
  review: the long-known 146403/Gerlach case (confirmed not a Steamboat
  well, no action needed) and log 80672 ("Greg Street Well" candidate,
  4.5 km away — flagged "keep unresolved," not a real match).
- **Herz-2**: still ambiguous between two NBMG "Harold Herz Geothermal
  Well 1/2" candidates ~1.3 km apart — Sorey & Colvard's own Table 3 OCR
  for this well is garbled across multiple rows and couldn't be
  disentangled from the text alone.
- **PTR-1/PTR-2, STMGID MW-3/MW-4**: no NDWR or NBMG match found under
  any name tried — NBMG's only STMGID-named record is a production well
  (Shadowridge #4), not this monitor pair.
- **Brown School's real chloride range**: Sorey & Colvard's Table 3 OCR
  row-position for a "16-22 mg/L" range most likely actually belongs to
  Brown School rather than Steinhardt (the Steinhardt fix moved a
  300→140 mg/L decline to Steinhardt based on the report's narrative
  text) — Brown School's own number is still unconfirmed.
- Several other long-open names remain unresolved and unchanged since
  earlier sessions: `Steinhardt`'s exact well vs. domestic-use
  distinction, `NDOT`'s specific identity (a 2007 well-log lead near
  Herz was checked and ruled out — real NDOT sits ~2.5 km north, per
  Klein 2007 Figure 1), `MacKay`, `Woods`, `Tangen`, `Bianco` (only a
  tentative PLSS-centroid match, depth mismatch flagged), and the
  stratigraphic/GS-numbered wells beyond what's already resolved.

## 4. Water-level data is genuinely thin right now

Worth restating plainly: most of the wells touched or newly registered
in recent sessions (the ~44 provisional wells from the big well-log
batch, the Sorey & Colvard Table 3/8 wells, well 23-5 itself as of this
session) have **no water-level observations at all**. The only wells
with a real, continuous, multi-year water-level record usable for
anything (barometric efficiency, trend analysis) are outside the
Steamboat field proper (STMGID MW3/MW10, South Truckee Meadows basin).
This is the same root gap as item 1 above — solving it is really one
NDEP-data problem, not several.

## 4b. One flagged value from the new 42-row OCR batch (2026-10-01)

Herz Domestic Well's 10/24/2025 field conductivity reads 9,933 uS/cm
in the database — roughly 7-9x every other reading on file for this
well (1,037-1,425 uS/cm across every other round, this session and
prior ones). Flagged directly in the `Field_Measurements.instrument`
text as a likely OCR misread, not silently corrected or dropped. Worth
a 2-minute check against the original scanned page (PDF pages 69/70 of
`NDEP_compiled_U230_Steamboat_reports.pdf`) next time you have it open.

## 5. Housekeeping / no action needed right now

- **git status is clean** as of this session (only
  `data/derived/qc/` untracked, which is disposable/regenerable QC
  output by design — nothing to commit there).
- **`docs/literature/` stays gitignored, permanently** — per your
  explicit instruction this session, do not `git add -f` anything in
  that folder (including the annotated bibliography or its rendered
  outputs), regardless of what any earlier session note might have
  implied about "the still-open commit-to-git question." This question
  is now closed: the answer is no.

## 6. Longer-horizon, not blocking anything today

- A real dissolved-gas-bearing sample would let PHREEQC's gas-phase
  module be run against the real barometric-pressure record and tested
  against this session's temperature-vs-pressure correlation finding
  (well A009) directly — flagged as a good next PHREEQC direction once
  such a sample exists.
- A true nested piezometer pair (two wells close together, different
  screen depths, both with current water level) would let a real
  confining-layer/vertical-head-difference argument be made — nothing
  in the current network qualifies.

## 7. Steamboat Ditch losing-reach field measurement (real, testable, cheap)

Raised 2026-09-26. Steamboat Ditch (real `Locations` row: `Steamboat
Ditch @ Rhodes Road`, real NDEP chemistry on file, 41 samples) is a
seasonal (~May–October) Truckee River diversion that enters Steamboat
Creek just above the SBRR gauge — inside the primary geothermal
discharge area. Whether that reach is *losing* water to the shallow
subsurface (a real recharge term this project's conceptual model
doesn't currently have) or just passing it through to SBRR is
untested with any data on file today.

**Concrete field method** (see
`notebooks/07_historical_context_sorey1992.qmd`'s new "Steamboat
Ditch" section for the full write-up): three flow-probe discharge
measurements on the same day — Steamboat Creek just upstream of the
ditch confluence, the ditch itself just before the confluence, and
Steamboat Creek just downstream (near SBRR). $$Q_{down} < Q_{up} +
Q_{ditch}$$ = losing reach (real recharge evidence); $$Q_{down} >
Q_{up} + Q_{ditch}$$ = gaining reach. Repeating this 2–3 times across
the diversion season, plus once after the ditch is shut off (a
natural-baseflow-only control), would give a real seasonal signal,
not just one snapshot.

**A separate, real anomaly worth resolving while you're out there**:
one Ditch sample (date field ambiguous — the known
`Sampling_Events.date` dual-epoch issue) reads Cl=1100 mg/L, an order
of magnitude above every other Ditch reading (0–5 mg/L). Could be a
data error, or could be a real off-season reading if the ditch gate
being closed lets thermally-influenced water reach that sample point
— worth a quick look at whichever lab report/field sheet this came
from to recover the real date.

**Also flagged (not yet actionable without more data)**: separating
Truckee-Ditch recharge from local Galena/Mt. Rose runoff chemically
needs isotopes (Cl alone can't do it — Whites Creek is just as dilute
as the Ditch). Zero isotope samples exist for the Ditch, Whites Creek,
or Galena Creek today (all 8 isotope samples on file are thermal FIELD
sites). A handful of d18O/dD samples at these dilute end-members,
ideally paired with the discharge measurements above, would make a
real per-well mixing calculation possible for the first time. Little
Washoe Lake was checked directly as a candidate end-member too — no
`Locations` row or chemistry exists for it at all.

## 8. Injection pressure/rate history vs. eruption timing (new, 2026-10-04)

You supplied NDEP UIC Temporary Permit UNEV2007204T2025-1 (issued
2025-05-30), which authorized raising the field's combined injection
rate limit from 49,500 to 55,000 gpm for `IW-1`, `IW-4`, `IW-5`,
`IW-6`, `21-32`, `42A-32`, and `64A-32`, and gives each well's
historic-peak / current / newly-authorized wellhead pressure and
injection rate (Tables B/C). This is now stored, not just read once:
`data/raw/ndep/injection_pressure_rate_history.csv` →
`Injection_Operating_History` table (schema
`database/schema/20_injection_operations_schema.R`, ingest
`scripts/ingest/ingest_injection_operating_history.R`, wired into
`run_pipeline.R` as `RUN_INGEST$injection_operating_history`). A
comparison figure
(`output/figures/injection_operations/injection_pressure_by_well.png`)
and tidy summary CSVs
(`data/derived/injection_operations/injection_pressure_summary.csv`,
`injection_rate_summary.csv`) are regenerated automatically by
`build_injection_pressure_plot()`.

**This is a one-snapshot table today** — it only reflects this one
permit's own before/after comparison. It becomes a real multi-document
time series the moment more NDEP permits/annual reports with the same
pressure/rate table structure are transcribed into the same CSV
(append more rows, following the existing `document_name`/
`document_date`/`permit_number` columns) — worth doing with the other
UIC permits/renewals/TFT reports already on file or requested, so
pressure changes can eventually be lined up against the 2025 eruption
timeline.

**The bigger idea you raised** (quoted in full below for when you're
ready to scope it as real analysis work, not just documentation) is a
genuine, testable research question — whether subsurface pressure
and/or fluid-chemistry changes from geothermal operations correlated
with, and may have contributed to, the hydrothermal changes preceding
the Lower Sinter Terrace eruption. The two competing hypotheses you
laid out (pressure-driven vs. fluid-migration/plumbing-reorganization,
distinguished via conservative tracers like Cl/B, Na/Cl, Li/Cl,
SiO2/Cl ratios) and the suggested methods (monthly master timeline,
cross-correlation/lag analysis, PCA on chemistry, a "null model" check
against pre-eruption periods with no eruption) are all things this
database can support — but building the full workflow (a master
monthly timeline joining injection/production/water-level/chemistry/
conductivity/surface-observation data, the lag/cross-correlation
analysis, the tracer-ratio stability check, PCA/clustering, and the
null-model comparison) is a substantial, multi-session analysis
project in its own right, not something to build opportunistically.
Flagged here as the next real research-question candidate once the
calibration-sampling/Cl-conductivity thread (see
`manuscript/06_calibration_sampling_proposal.qmd`) is further along —
happy to scope it properly in Plan mode when you're ready to start.

### Update 2026-10-04: corrections, Lindsey (2026) timeline, and tracer ratios

Three concrete pieces of this were completed:

- **Corrected two real data issues you caught**: `14A-22` is now
  stored as its own distinct well (new provisional `Wells` row,
  `well_id=271`), not a typo for `14A-33` — both are now correctly
  recorded as currently-production wells, not injection. `23-33`'s
  current pressure (135 psig) exceeding its own newly-authorized limit
  (120 psig) is now a dedicated, explicitly flagged
  `status = "exceeds_new_authorized_limit"` row — visible in the CSV,
  the summary table, **and** the figure's caption (not just buried in
  a notes field). Every well with real reported numeric values in this
  report (the ones that previously showed `status = NA`) now has
  `status = "injection_well"`.
- **Real eruption timeline pulled directly from Lindsey et al. (2026)**
  (`docs/literature/Lindsey_etal_2016_GeyserE_renewedA_steamboat.pdf`
  — filed under a "2016" filename, but the paper itself is dated
  February 2026), not reconstructed from memory:
  `data/raw/historical/lindsey2026_eruption_timeline.csv` — 2022
  renewed-activity onset, 2023 diffuse steaming expansion, 2024 shift
  to discrete seeps/vents, early-2025 vents becoming more energetic,
  the 2025-06-03 geyser-like eruption (per the paper's own abstract;
  body text says "mid-June 2025"), the pipe being capped shortly
  after, the June 2025 NBMG monitoring program start, and the two
  calibrated thermal-drone surveys (2025-07-07/08 and 2025-10-01).
  Cited throughout as **Lindsey et al. (2026)**.
- **Conservative tracer ratios (Cl/B, Na/Cl, Li/Cl, SiO2/Cl) computed**
  for every sample with the relevant analytes
  (`scripts/analysis/conservative_tracer_ratios.R`,
  `compute_tracer_ratios(con)`) — `data/derived/tracer_ratios/tracer_ratios_by_site.csv`
  and a log-scale figure
  (`output/figures/tracer_ratios/tracer_ratios_by_site.png`), labeling
  each sample `thermal_endmember` (the curated Sorey & Colvard 1992 +
  FIELD set already used in notebook 07's Cl/B t-test) vs.
  `background_or_other` (NDEP/domestic/Skalbeck monitoring etc.), per
  your preference to show both populations rather than excluding one.
  **A real, if small-n (16 thermal points), observation**: the thermal
  end-member points' Cl/B (~13-17) and Na/Cl (~0.7-0.8) ratios sit in a
  visually tight band across the full 1950-2026 span on file, while
  the much larger `background_or_other` population is far noisier —
  consistent with (not proof of) a largely stable thermal source
  composition. This is a stability check only, not a conclusion about
  the eruption.
- **Still not built** (per the plan, scoped as design only): the
  master monthly timeline joining injection/production/water-level/
  chemistry/conductivity, and the downstream cross-correlation/PCA/
  null-model analysis. Design notes below.

### Update 2026-10-04 (continued): all three follow-ons built

- **`Well_Production_History` built**: `database/schema/21_well_production_history_schema.R`
  + `scripts/ingest/extract_well_production_history.R` — extracted
  104 real rows (13 wells × 2 TFT report dates × 4 parameters:
  flow/enthalpy-temperature/wellhead-temperature/wellhead-pressure)
  directly from the bracketed `[... Table 2: Well Summary During
  Tracer Flow Testing ...]` entries already transcribed into
  `Wells.notes` — no new document read, a structured distillation of
  existing data. `well_id` resolved directly from the `Wells` row
  being scanned, sidestepping any name-matching ambiguity. Wired into
  `run_pipeline.R` as `RUN_ANALYSIS$well_production_history`.
- **Thermal-drift flagging added** to
  `scripts/analysis/conservative_tracer_ratios.R`
  (`flag_thermal_drift()`): screens every background/domestic
  well/site with ≥3 samples spanning ≥180 days for a trend toward the
  thermal-endmember reference band (loose `p < 0.1` threshold —
  explicitly a screening step, not a confirmatory test). Real result:
  94 feature/ratio combinations screened, 16 flagged — several are
  geochemically sensible (e.g. "Brown's School Geothermal Well,"
  "Curti Barn Well (geothermal)" — wells that are themselves
  geothermal-influenced, just outside the curated thermal-endmember
  scoping). Full results in
  `data/derived/tracer_ratios/thermal_drift_flags.csv`; the figure
  labels only the top 8 by significance to stay readable.
- **`build_monthly_indicator_timeline()` built**
  (`scripts/analysis/monthly_indicator_timeline.R`), default range
  2025-01-01–today per the "start where real post-eruption coverage
  exists" instruction. Real coverage assembled across all 6 planned
  indicators: injection_pressure (1 month), well_production (2
  months), conductivity (2 months), field_chemistry (8 months),
  tracer_ratios (4 months), water_level (12 months) — written to
  `data/derived/monthly_indicator_timeline/monthly_indicator_timeline.csv`
  and a faceted figure
  (`output/figures/monthly_indicator_timeline/monthly_indicator_timeline.png`)
  with the 2025-06-03 eruption marked on every panel. **Still no
  cross-correlation/lag/PCA/null-model analysis** — this is assembly
  and visualization only, per the original phased design. Not wired
  into `run_pipeline.R` yet (standalone, manually invoked, since its
  indicator scope may still change).

### Design sketch: master monthly indicator timeline (superseded by the build above, kept for reference)

A future session should build a single long-format table —
`(month, indicator, value)` — joining:

| Indicator | Source | Status today |
|---|---|---|
| Injection pressure/rate | `Injection_Operating_History` | **One snapshot** (2025-05-30) — needs more permits transcribed into the same CSV (see below) before this axis has real monthly resolution |
| Production | `Wells.notes` (free text, from TFT reports) | No structured monthly table exists — would need a small new schema addition (e.g. `Well_Production_History`, mirroring `Injection_Operating_History`'s shape) if more than a couple of manually-read snapshots are wanted |
| Water levels | `Water_Level_Observations` | Thin inside the Steamboat field itself (2-3 wells with real continuous records — see the standing note in item 4) |
| Chemistry (Cl, B, Na, Li, SiO2, ratios) | `Lab_Analyses`/`vw_major_ions`, plus the new `tracer_ratios_by_site.csv` above | Real but sparse for the eruption window specifically — most thermal FIELD samples are 2024-2026, pre-dating the eruption by months in some cases |
| Conductivity | `Conductivity_Observations` | Loggers deployed 2026-07-15 — postdates the 2025-06-03 eruption by over a year, so this axis can't speak to the eruption's buildup, only its aftermath |
| Surface observations / eruption precursors | New `lindsey2026_eruption_timeline.csv` above | Real, dated, but literature-sourced (not a live-updating table) |

Proposed function signature for the next session to implement directly
from this table:
`build_monthly_indicator_timeline(con, start = "2020-01-01", end = Sys.Date())`
returning the long-format table, plus a faceted small-multiples plot
(one panel per indicator) as the first deliverable — cross-correlation/
lag analysis, PCA, and the null-model check (comparing this window
against earlier periods with no eruption) should all be built as
separate, later steps on top of that table, not in the same pass.

**Honest gap, worth stating up front to whoever builds this next**:
given the table above, the window with genuinely dense multi-indicator
coverage is **after** the eruption (mid-2025 onward: conductivity
loggers, the U230 field-parameter rounds, this one injection permit),
not before it — the pre-eruption 2022-2025 buildup described in
Lindsey et al. (2026) has essentially no matching *subsurface*
monitoring data on file yet (no injection history, thin water levels,
sparse chemistry). This doesn't make the project infeasible, but it
does mean the first real result from this timeline is more likely to
be "how has the system responded since the eruption" than "what led up
to it" — worth setting that expectation before investing session time
in the cross-correlation/lag analysis specifically.

### Workflow for adding more NDEP permits/reports (no new code needed)

When another NDEP UIC permit, renewal, or annual report with a
pressure/rate table (like Tables B/C in this one) becomes available:

1. Transcribe its rows into
   `data/raw/ndep/injection_pressure_rate_history.csv`, following the
   exact same columns (`well_name, canonical_well_name, parameter,
   metric_type, value, value_min, value_max, unit, status,
   document_name, document_date, permit_number, notes`) — just append
   rows, don't replace existing ones.
2. Re-run `ingest_injection_operating_history(con)` — it's additive
   and idempotent (keyed on well/parameter/metric/document), so this
   is safe to re-run any time.
3. Re-run `build_injection_pressure_plot(con)` — once more than one
   `document_date` exists, `pressure_wide`/`rate_wide` will show every
   document side by side, and the bar-chart figure (which currently
   filters to the single most recent document) should be extended to a
   line-over-time view per well instead — a small, concrete follow-up
   once there's a second real data point to compare against.

## 9. New temperature logger data ingested (2026-10-04) -- three real issues flagged

New observation files were added to `data/raw/loggers/observations/`
(dated 2026-09-27) and ingested: 72,128 new rows across 7 loggers
(A001-A005, A009, A010), extending their records through
2026-09-27. Verified on a scratch copy first, then applied to the real
`geochem_operational.sqlite` (backed up first to
`database/archive/geochem_operational_pre_temp_logger_ingest_<timestamp>.sqlite`),
idempotent re-run confirmed (0 new rows). `docs/data/temp_sample.csv`
and the website homepage's "Temperature readings" stat card now both
show the real total (276,750 rows), and `results.html`'s interactive
chart includes the new late-September 2026 data. Three things found
along the way, not fixed, since none should be guessed at:

- **A008 (EMO259100052, meant for station `SBF_0002`) still cannot be
  ingested at all.** `SBF_0002` does not exist in `Locations` --
  confirmed directly (location_ids run ...76, 78..., with a gap where
  77 would be). This blocks not just today's new file but *every*
  observation file ever collected for this logger (May/August/
  September 2026 files all sit unprocessed). If `SBF_0002` is a real
  field site, it needs a `Locations` row (coordinates, `site_type`)
  before any of A008's data can be ingested.
- **A013 (EMO259100043) is marked `destroyed` as of 7/14/2026 in
  `temperature_logger_deployments.csv`, with no `external_station_code`
  at all -- but a real observation file for this exact serial, dated
  2026-09-27, now exists.** That's not possible for a logger
  genuinely destroyed two and a half months earlier. Either (a) this
  is a different, redeployed physical unit reusing the same serial, in
  which case it needs a new deployment row (status, start date,
  location) rather than updating the destroyed one, or (b) the
  `destroyed`/`7/14/2026` entry was premature or wrong and this logger
  is actually still active somewhere. Not resolved here -- the file
  sits ingested-nowhere until the real status is confirmed.
- **A010 (CMN232100066, station `SBS_0006`)'s real data starts
  2025-10-01 -- about seven months before its own documented
  `deployment_start` of 5/1/2026.** Confirmed directly: the earliest
  272 readings are real, regularly-spaced (4-minute interval) data,
  not a parsing artifact. Two real possibilities, neither assumed: this
  specific physical logger unit was deployed somewhere else first
  (its onboard memory not cleared before being moved to `SBS_0006`,
  so the pre-5/1/2026 readings may describe a *different* location
  entirely), or `deployment_start` in the CSV is simply wrong. Worth
  checking against field notes/photos for this unit before trusting
  any pre-May-2026 reading as representing `SBS_0006` specifically.

No manuscript/report text needed a numeric correction this round (the
"Eleven continuous temperature loggers" count in
`manuscript/00_thesis_proposal.qmd`/`03_methods.qmd` was already
correct and carries no stale date range) -- only the website's
data-driven exports and chart needed refreshing, which is done.

## 10. A010/A013 clarified, SBF_0001 install photo logged (2026-10-04)

Per direct confirmation from Tyler:

- **A010 (CMN232100066) is explained, not a data error.** The real
  readings starting 2025-10-01 (about 7 months before this logger's
  documented 5/1/2026 `deployment_start`) are from this same physical
  unit's earlier use in Cary Lindsey's own pre-project monitoring
  effort -- the onboard memory was recovered, and the data is real.
  Noted directly in `Temperature_Loggers.notes` for this logger (the
  deployment CSV itself couldn't be edited this session -- see the
  blocker below). Those pre-5/1/2026 readings should still be read as
  describing Lindsey's own earlier deployment, not necessarily
  `SBS_0006`, until/unless that's also confirmed.
- **A013 (EMO259100043) is confirmed redeployed** after the original
  A013 unit was destroyed -- a real new observation file
  (`EMO259100043_20260927122459.xls.xlsx`, dated 2026-09-27) belongs
  to this redeployment, not the destroyed unit. **Still needed: the
  real deployment location (external_station_code) and start date for
  the redeployment** -- without it, this row and file continue to be
  skipped by `ingest_temperature_loggers()` rather than guessed at.
  Once you confirm the station, I can register the redeployment
  properly (as a fresh deployment, not an edit to the destroyed row)
  and ingest the September file.
- **A real blocker hit this session**:
  `data/raw/loggers/temperature_logger_deployments.csv` is currently
  locked for writing at the Windows level (confirmed via R, bash, and
  PowerShell all independently failing with the same
  sharing-violation/"device or resource busy" error on this one file
  specifically, while every other file in the same folder writes
  fine) -- most likely something has it open (e.g. Excel). The A010
  and A013 notes above were applied directly to the database instead
  (`Temperature_Loggers.notes`, bypassing the CSV), but **the CSV
  itself still needs the same two notes added once it's closed/
  unlocked**, since `ingest_temperature_loggers()`'s upsert logic
  treats the CSV as the source of truth and will overwrite
  `Temperature_Loggers.notes` from the (currently blank) CSV column
  the next time it runs. Close whatever has the file open, then let me
  know and I'll apply the same edit there.
- **SBF_0001 install photo logged.** A real field photo documenting
  the first logger (A005, serial EMO259100060) at `SBF_0001` was saved
  to `data/raw/images/image_drop/SBF_0001_logger_install.jpg` and a
  new `Field_Observations` row (location_id 68) records it. No EXIF
  GPS or capture-date survived in this file (confirmed via exiftool --
  same metadata-stripping pattern already seen for other chat-shared
  photos), so no new coordinate was added; this is documentation only.
  A second install photo (for a different logger) is still pending --
  send it when ready and I'll run the same exiftool check.

## 11. A008 / SBF_0002 resolved -- the pending "second logger" photo (2026-10-05)

The second install photo flagged as pending in item 10 has arrived
(`IMG_5509.jpeg`) and, unlike the earlier chat-shared field photos,
retained its full camera EXIF -- including real GPS. This closes the
single biggest standing temperature-logger gap:

- **`SBF_0002` is now a real, registered `Locations` row**
  (location_id 253; 39.382253, -119.740486; `site_type = 'fumarole'`;
  `coordinate_source = 'photo_exif'`, `coordinate_uncertainty_m = 8.7`,
  matching the photo's own real `GPSHPositioningError`). Sanity-checked
  against `SBF_0001` (39.38241, -119.7399): ~53 m apart, a plausible
  distinct-but-nearby fumarole in the same cluster, not a duplicate or
  an obviously wrong point. Raw photo stored at
  `data/raw/images/image_drop/IMG_5509_SBF_0002.jpeg`; capture date
  2026-08-22 16:12:14 -07:00 per EXIF.
- **A008 (EMO259100052)'s entire backlog is now ingested** -- all
  three of its previously-unprocessable files (May, August, and
  September 2026) went in at once: 27,909 new observations
  (6,366 + 11,242 + 10,301). `Temperature_Observations` now totals
  304,659 rows. QC re-run clean (same 2 pre-existing PHREEQC failures,
  0 logger outliers). Website re-exported/rebuilt; the homepage stat
  card and `results.html` now reflect the real new total.
- **A013 remains the only open item from §10** -- still needs its
  real redeployment location/start date before it can be registered,
  and `temperature_logger_deployments.csv` was still locked for
  writing as of the last check (the A010/A013 provenance notes are
  only in the database, not yet in the CSV -- see §10 for the
  details). Close whatever has that file open and let me know.

## 12. Lower Sinter Terrace scope shift -- White/Geyser Society GIS features ingested; real leads/gaps for you to resolve (2026-10-24)

Per the scope shift toward the Lower Sinter Terrace (LST), the new
`data/raw/arcgis/excel ingest/White&Geyser_Society_Mariner&Janik_GIS_located_wells_springs_features.xlsx`
sheet is now ingested (`scripts/ingest/ingest_white_geyser_features.R`,
`RUN_INGEST$white_geyser_features`): 32 new Locations, 6 existing
coordinate-less Locations (GS-1, Herz 1/2, Peigh, Stmgid 4, Stuart)
filled in, and real chemistry/temperature for GS-1 and two auger holes
promoted into Sampling_Events/Samples/Lab_Analyses/Field_Measurements.
A dedicated `gas_analyses` GeoPackage layer was also added so the
Fischer/Ruprecht gas sample points export cleanly.

**Three coordinate discrepancies -- resolved 2026-10-25** (see
`data/derived/white_geyser_coordinate_discrepancies.csv`): the Curti
case turned out to be a real bug, not just an ambiguous discrepancy --
"Curti Barn Well (geothermal)" (location 160) had been silently given
a duplicate copy of the separate "Curti Domestic Well" (159) point
rather than its own real coordinate, so comparing the sheet's point
against 159 was comparing against the wrong well entirely. Fixed by
giving location 160 the real NBMG "Curti Barn Geothermal Well" match
(39.40524, -119.74316), which sits only ~154 m from the sheet's own
digitization -- good agreement. Brown School (206 m) and Cox I-1
(577 m) were both left at their existing, better-corroborated NBMG
coordinates (exact name match plus, for Cox I-1, a footage/legal
description); the sheet's points are logged as secondary references in
each Location's own notes rather than discarded.

**Busick-property eruption well and the resort-tank well (SBW_0002) --
real NBMG leads, not confirmed identities.** A proximity check against
NBMG's statewide `Geothermal_Wells.csv` found:
- `SBW_0001` ("Phil's property" / the eruption pipe): nearest named
  wells are 131-280 m away (Ormat's "Industrial Production Well
  33-33"; Steamboat Resort's "No. 32 Geyser Well," "Carver Geothermal
  Well," "Steamboat No. 2," "Steamboat No. 4") -- none close enough to
  confidently identify. If you have any Busick-provided documents on
  the well's depth/construction, that would resolve this immediately;
  otherwise this is a good candidate for the next Ormat/NBMG outreach
  round.
- `SBW_0002` (resort main outflow tank): a much stronger lead -- three
  NBMG wells sit within 10-24 m of it: "Carver Geothermal Well" (10 m,
  8.6 m deep), "Steamboat No. 4" (12 m, 68.58 m / ~225 ft deep,
  Abandoned), "Steamboat No. 2" (24 m, 36.576 m / ~120 ft deep,
  Abandoned) -- all Steamboat Resort-operated. These three are
  plausible candidates for the aquifer feeding your May 2026 resort-
  tank sample (SBW_0002, sample 815), but are too close together to
  pick one without more information. Both locations now have a
  minimal `Wells` row (`well_role='unknown'`) so a confirmed depth can
  be recorded once you/Ormat/NBMG confirm which well this is.

**Thermal-imagery rasters (TIR ortho, July/October 2025 two-panel
comparison, TGCP/vent/pit/launch points) are not yet files on disk** --
only chat attachments so far. To get these digitized as real,
GPS-registered Locations (continuing the SBO_* photo-survey-point
convention), drop the underlying GeoTIFF/raster files and/or the
labeled TGCP point list into `data/raw/images/` or a new
`data/raw/thermal_imagery/` folder. This is the concrete next step for
the "map new surface features from temperature anomalies" mapping
deliverable.

**NBMG eruption-timeline PDF** ("Steamboat Springs Approximate
Timeline of Events"): its real day-by-day June 2025 account (including
a previously-unrepresented SECOND eruption pulse, June 5-6, distinct
from the June 1-2 first pulse) is now transcribed into
`data/raw/historical/nbmg_timeline_2022_2025.csv` and reflected in
`output/figures/manuscript/steamboat_timeline.png` (Figure 1). I only
have the extracted text, not the actual PDF file -- please drop the
real PDF into `docs/literature/` so it can be properly archived/cited
alongside the other literature sources.

**Still to come (not done this pass, per the approved plan's
checkpoint)**: an in-depth White 1964/1968 hydrology/geology review
focused on the LST (cross-sections, well logs, Steamboat Creek/Ditch
interaction); the gas-informed parent-fluid PHREEQC reconstruction
(NV26-1 + the fissure water sample); a hydraulic-conductivity/
AQTESOLV/MODFLOW advisory write-up; and the thesis conceptual-model/
LST-scope-shift rewrite (including removing the He-isotope/d13C
discussion per your no-isotope-gas decision). These are queued as the
next steps in `.posit/assistant/plans/2026-10-24-1632-plan.md`.

## 13. Gas-informed parent-fluid reconstruction and fluid-evolution flowpath (2026-10-24)

Built `scripts/phreeqc/15_gas_informed_parent_fluid.R` and
`scripts/analysis/fluid_evolution_flowpath.R`, extending the PHREEQC
gas-phase work from Session 49 into a first-pass parent-fluid
reconstruction (steam-loss correction + gas add-back at reservoir
pressure) and a full flowpath trace from the reconstructed parent
fluids through measured fissure/resort-tank discharge, a nearby well
(SBW_0001), and the two Steamboat Creek chloride-mass-balance stations
(SBRR, SBBV). Real results written to `data/derived/phreeqc/` and
`output/figures/manuscript/` (parent_fluid_comparison.png,
fluid_evolution_flowpath.png, lst_conceptual_flowpath.png).

- **Real, reported PHREEQC convergence failure**: the resort-tank
  sample's (815, SBW_0002) gas-equilibration step did not converge
  (pH 9 + imposed acid-gas load) -- see
  `data/derived/phreeqc/parent_fluid_diagnostics.csv`. The
  conservative-species (Cl, Na, etc.) reconstruction for that sample is
  still valid; only the re-equilibrated pH/saturation-index step
  failed. Worth trying a different database (SIT, Pitzer) or a smaller
  total_gas_moles if you want a converged result for this one later.
- **The conceptual figure's degassing-vs-seepage framing is a
  qualitative read of the thermal-infrared imagery already shared in
  chat, not a digitized layer** -- the underlying GeoTIFF/raster files
  are still not on disk (same gap as item 12). Dropping those files in
  would let this become a real spatial layer instead of a qualitative
  call.
- **Isotope data for all 5 real LST/creek samples lives in
  `Isotope_Analyses` under `d18O`/`d2H`** (not `dD` -- a naming detail
  worth remembering if you query it directly).

## 14. Database sensitivity, inverse modeling, and thermal-imagery sourcing (2026-10-24, continued)

- **Database sensitivity resolved the pH-9 convergence question, but
  raised a new one.** `phreeqc.dat` and `wateq4f.dat` both converge
  where LLNL fails for the resort-tank sample -- but they converge to a
  parent pH of ~2.0-2.1, dramatically more acidic than the fissure's
  own result (~5.5-5.7, where all three agree). This is reported as a
  real, unresolved database-sensitivity finding in the thesis, not
  picked one-and-moved-on. `data/derived/phreeqc/
  parent_fluid_database_sensitivity.csv` has the full 6-database x
  2-sample sweep if you want to dig further (e.g. check whether the
  pH-2 result is numerically real or an artifact of these simpler
  databases' more limited species list).
- **Inverse modeling with the parent fluid as end-member: 0 feasible
  models found for both real targets** (SBW_0001, SBW_0002), traced to
  the same tiny (~1e-9) numerical-residual PHREEQC quirk already
  documented in this project's synthetic self-tests (Session 14) --
  not a rejection of the parent-fluid hypothesis itself. See
  `data/derived/phreeqc/parent_fluid_inverse_modeling_summary.csv`.
- **Thermal-imagery data: no public source found.** Checked the
  Lindsey et al. (2026) paper on file (no data-availability/repository
  statement) and searched online for an NBMG or Stanford Geothermal
  Workshop data repository hosting the drone thermal-infrared survey
  rasters -- found none. This appears to be unpublished, internal NBMG
  monitoring-program data, not anything retrievable without asking the
  NBMG team (Cary Lindsey et al.) directly for the GeoTIFF files. No
  raster files exist anywhere in this project's `data/raw/` as of this
  check.

## 15. Database-sensitivity mystery resolved: starting pH, not database choice (2026-10-24, continued)

Root-caused via controlled PHREEQC experiments
(`data/derived/phreeqc/parent_fluid_pH_sensitivity_root_cause.csv`):
the resort tank's divergent/non-converging behavior is **not** a
database artifact. Its measured field pH (9.0, vs. 8.3 for the
fissure) leaves far less carbonate buffering capacity before the same
absolute imposed gas load drives the system into a strongly acidic
regime. Re-running the resort tank's real chemistry with only its
starting pH changed to 8.3 converges cleanly on all three databases
(LLNL included) and lands within 0.1 pH units of the fissure's result.
Ruled out along the way: boron (swapping it in/out of the fissure's
solution changes its final pH by <0.01 units).

**A real modeling-assumption flagged, not yet addressed**: the
reconstruction currently imposes the same total gas moles (10 mol)
regardless of each sample's own alkalinity/buffering capacity. Scaling
the imposed gas load to each sample's own water mass/buffering
capacity would likely reduce this kind of pH sensitivity -- worth
doing if you want the resort-tank parent-fluid pH/SI numbers to be
more directly comparable to the fissure's, rather than just noting the
sensitivity as done now.

## 16. Gas-load scaling tested: confirms, doesn't change, the pH finding (2026-10-24, continued)

`scripts/phreeqc/15_gas_informed_parent_fluid.R`'s `reconstruct_parent_fluid()`
now scales the imposed `GAS_PHASE` moles to each sample's own alkalinity
(buffering capacity) instead of a fixed 10 mol for every sample
(`total_gas_moles = NULL` by default now triggers this; pass a number
to override). Calibrated so sample 816 (the originally-validated case)
still gets ~10 mol. Re-ran the resort-tank reconstruction with this
real change: since 815's alkalinity is only ~6% higher than 816's, the
imposed gas load barely changes (10.56 vs. 10.00 mol) and the result is
essentially unchanged -- LLNL still fails to converge, `phreeqc.dat`/
`wateq4f.dat` still land at pH ~2.0-2.1. This is a real, useful
negative result: it rules out gas-load sizing as a contributing factor
and leaves the resort tank's own higher measured field pH (9.0 vs.
8.3) as the sole identified driver, exactly as the prior session's
root-cause investigation found. See
`data/derived/phreeqc/parent_fluid_gas_load_scaling_test.csv`.

## 19. Monitoring-network Cl/water-level plots, and a Session-30 inverse-model claim to revisit (2026-10-25, continued)

- **Deferred, "down the road" task**: build updated plots of the full
  monitoring network's real chloride and water-level data, pulling in
  NDEP PRR and other literature sources as they accumulate. Not started
  this session -- flagged here so it isn't lost.
- **A real parser bug was found and fixed in `scripts/phreeqc/
  11_run_phreeqc_inverse.R`** (see AGENTS.md Session 53): the production
  inverse-modeling runner was reporting "1 candidate solution" for a
  run that PHREEQC's own output says found 0 feasible models. This
  means the original Session 30 claim of "the first real inverse model
  found a feasible solution" (target: Soccer Field Monitoring Well,
  end-members: SBF_0001 + Boyd Domestic Well) is likely also a false
  positive -- re-running it with the fixed parser gives 0 feasible
  models too. **Done (Session 54)**: corrected every real instance of
  this claim across `manuscript/00_thesis_proposal.qmd`,
  `manuscript/02_geochemical_background.qmd`,
  `manuscript/03_methods.qmd`, `notebooks/06_phreeqc_geochemical_modeling.qmd`,
  and `ROADMAP.md`. Also tried a bounded phase/uncertainty exploration
  for the SBW_0001 inverse model (adding Quartz, varying balance
  elements, scanning 10-13% uncertainty) -- the residual is a genuine,
  Ca-specific infeasibility unaffected by phase/balance choices;
  11% uncertainty is the closest to feasible found (a single Mg
  residual at the 1e-5 noise floor) before the solver destabilizes at
  12%+. Not chased further (see AGENTS.md Session 54 for the full
  writeup) -- a real, still-open null result, not declared solved.
  **Still open**: `website/results.Rmd`'s own description of the
  mixing/inverse workflow as "synthetic-only" is separately stale
  (pre-dates Sessions 30/52/53/54 entirely) and was not touched this
  round -- worth a full website refresh pass at some point.

## 18. A real southwest/west groundwater sample is needed for the LST meteoric end-member (2026-10-25)

The Lower Sinter Terrace mixing/forward-model work (fissure + resort
well -> SBW_0001 + the three real LST springs) needs a real, dilute,
**geolocated** groundwater sample from southwest/west of Steamboat to
serve as the meteoric end-member -- the true upgradient recharge
direction per White's own documented Carson/Virginia Range mountain-
front recharge interpretation. Checked directly: **this project has
none on file.** Boyd Domestic Well (the end-member used until this
session) sits essentially due north of the fissure, not southwest/west
at all. Jumbo Grade Spring (now used instead, on real Ca/Mg/alkalinity
chemistry fit) has no coordinates in this database either -- its
assumed southwest/west position is a plausible guess from the place
name only, not verified.

**What would resolve this**: a real coordinate for Jumbo Grade Spring
(check Mariner & Janik 1995's own site map/description, or a modern
GPS fix if the spring is still accessible), or a new real sample from
a known southwest/west-of-Steamboat domestic well or spring. Either
would let the mixing/forward-model work swap in a confirmed, correctly-
positioned end-member instead of a chemistry-only best guess.

## 17. New conductivity data ingested, retrieval-artifact detector built, background/narrative pass (2026-10-25)

- **New conductivity shuttle readout (2026-10-12) ingested**, extending
  both loggers' continuous record from 2026-08-22 through 2026-10-10
  (~28,200 new rows). Copied into `data/raw/conductivity/raw/` with
  date-suffixed filenames since the shuttle export reused the existing
  files' basenames (which would otherwise have been silently skipped
  by the ingest script's file-level dedup).
- **A general "retrieval/relaunch ambient-air-exposure" detector was
  added to `scripts/qc/qc_conductivity_checks.R`** (this was flagged as
  worth building after the first, manually-caught instance of this
  artifact on 2026-08-22 -- now built after a second real instance on
  2026-10-10). It scans for a sharp EC drop relative to a local
  baseline immediately around any deployment-start marker or large time
  gap, flags the whole affected span (not just the single lowest
  point), and reproduces every previously hand-flagged row exactly
  while also catching a short 2026-08-22 relaunch dip and the full
  width of the 2026-10-10 excursion that a simple point-outlier check
  would have missed. No manual review needed on future downloads.
  `data/raw/conductivity/README.md` rewritten to describe this as a
  standing, durable fact rather than a session narrative.
- **Swept `data/raw/` broadly for other un-ingested files** (temperature
  loggers, field/lab/isotope chemistry, NDEP/NDWR, weather/pressure,
  photos) -- nothing else was newer than what's already reflected in
  the database; conductivity was the only genuinely new data this
  round.
- **Cl-conductivity calibration gap confirmed still open**: checked
  directly against the database as of 2026-10-24 -- zero real chloride
  samples fall after the loggers' 2026-07-15 deployment start, despite
  the conductivity record itself now running three months longer. The
  calibration campaign described in the thesis proposal (Chapter 6)
  is the only way to close this, and the proposal now recommends
  starting it as soon as possible rather than waiting for a later field
  season.
- **More White (1964, 1968) background material pulled into the
  thesis** beyond the already-done Low-Terrace-specific review: regional
  basement geology and the Steamboat Springs fault zone's topographic
  localization argument; a documented history of natural geysering at
  Steamboat back to 1860-1862 (the earliest published U.S. geyser
  record) through early-1900s mineral-deposition accounts and
  Gianella's 1939 wells-erupting-stibnite-from-depth account -- real
  historical precedent that the 2025 eruption is not unprecedented;
  and White's own 1968 pre-boiling parent-fluid chemistry (175 C,
  800-820 ppm Cl, used as a conservative tracer for total system heat
  flow decades before Sorey's own chloride mass-balance method), which
  is strikingly close to this project's own 2026 gas-informed
  parent-fluid reconstruction (781-797 mg/L). Added to both
  `manuscript/02_geochemical_background.qmd` and
  `00_thesis_proposal.qmd`'s Previous Work section, plus a new
  1860-1862 chronology-table row in `00_thesis_proposal.qmd` and
  `01_introduction.qmd`.
- **A planned thermal-infrared/mapped-feature overlay paragraph added**
  to `00_thesis_proposal.qmd`'s "Planned figures, not yet produced"
  section -- describes overlaying the TIR rasters (still not on disk,
  see item 12/14 above) against the new White/Geyser Society points,
  the `SBO_*` field-survey points, and other dated field observations,
  and what question it would answer. Not built, since the raster files
  are the blocker, not anything database-side.
- **The gas-informed parent-fluid/database-sensitivity/flowpath thread
  in `00_thesis_proposal.qmd` reorganized for readability**: new `##`
  section headers added throughout the previously header-less
  "Preliminary results" section, plus an explicit "What this section
  covers, in sequence" callout at the start of the gas thread
  recapping all six steps (reconstruction, convergence comparison,
  database sweep, pH root-cause, inverse modeling, flowpath) in one
  place for a reader who doesn't want to re-derive the story from six
  sessions' worth of additions. Also fixed a stale Methods-section claim
  that only one real inverse-modeling run existed (there are now two,
  with different outcomes).
- **New interpretive paragraphs added to `05_discussion_and_future_work.qmd`**:
  what the pH-9 database-sensitivity finding implies for how cautiously
  to treat PHREEQC pH/SI output on any high-pH (>=9) sample project-wide
  (a standing caveat now, not just a one-off note); and an explicit
  statement that the null inverse-modeling result means "not yet tested
  successfully," not "tested and rejected."
- **New figure**: `conductivity_timeseries.png` (both loggers' full
  record with the retrieval artifact highlighted), added to
  `00_thesis_proposal.qmd` and `04_results.qmd`. A separate combined
  "state of the LST conceptual model" summary figure was considered but
  judged redundant with the three figures that already cover this
  (`lst_conceptual_flowpath.png`, `fluid_evolution_flowpath.png`,
  `parent_fluid_database_sensitivity.png`) -- not built.
- **Road-ahead summary added** to `05_discussion_and_future_work.qmd`
  ("Immediate next steps, given this session's new data"): start the
  calibration campaign now; keep both logger networks on the same
  download cadence; the Collar & Huntley fault digitization and the
  NDEP/NBMG data requests remain the two biggest blockers, unchanged;
  revisit the inverse-modeling numerical quirk as a small, bounded fix.
- All three manuscript formats (html/pdf/docx) re-rendered cleanly
  (0 citation errors, correct sequential figure numbering) after every
  change this session.
- Database GeoPackage layers were **not** re-exported this session
  (the Curti Barn coordinate fix and the new conductivity data would
  both affect `locations`/future conductivity-adjacent layers) -- worth
  doing on the next full pipeline run.

## Collar (1990) thesis: follow-up items (2026-10-29)

1. **Georeference Plates 3 and 4 in ArcGIS** (`docs/literature/collar paper and plates/collar-plate3.tif`, `collar-plate4.tif`; Plate 1 for spring numbers). Use the 22 control points in `data/derived/historical_comparison/plate_georeferencing_features.csv` (Cox I-1, 23-5, 21-5, 83A-6, 28-32, PW-2/3, IW-2, OW-2, Steinhardt, Brown School, Herz, Curti, Boyd, Jeppson, Rogers, Peigh, GS-1, SBRR). Then digitize the four named faults (Steamboat Springs Fault Zone, Mud Volcano Basin, Silica Pit, Pleasant Valley) into `data/raw/arcgis/faults/` for `ingest_fault_traces.R`, and locate the 24 features marked "locate/digitize" (strat wells 2, 5-9, 13, 14; MacKay, Woods, Tangen, STMGID/Otten, Towne, Byers, Gerold, spa production well, springs 50/62/63).
2. **Confirm S10 = Rhodes Road and the S70 match to Geiger Grade** on Plate 4 once georeferenced; Table 4 stations are transcribed but are not in the database until their coordinates are known.
3. **Check the USGS gauge position relative to the Steamboat Ditch inflow (Collar's S20).** Collar's S10 (above the ditch) flowed 0.11-2.5 cfs; the SBRR flux uses the gauge's 11.2 cfs with a Cl of 17.1 mg/L. If the gauge is below the ditch inflow, the SBRR flux needs a ditch correction.
4. **Collar Appendix B** (about 20 NDWR driller's reports, thesis pp. 266-299) can be extracted and run through the existing well-log pipeline to get lithology and log numbers for the strat wells.
5. **Pressure transducer** in GS-1 (or the resort-tank well) is the direct modern equivalent of Collar's spa-well experiment; temperature loggers show no weekday cycle.
6. **Longer precipitation record** (Reno, NOAA GHCN-D USW00023185, 2018-2026) to repeat Collar's cumulative-departure test.
