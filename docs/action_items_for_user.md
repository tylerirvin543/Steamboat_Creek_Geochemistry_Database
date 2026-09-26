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
