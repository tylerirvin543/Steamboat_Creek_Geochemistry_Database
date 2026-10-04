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
