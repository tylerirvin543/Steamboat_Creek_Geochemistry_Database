# Plan (2026-11-08): permit-file matching, well classes, SBW_0003 lithology leads, TIR polygons, elevation fixes

Nothing below has been run or edited. Part A answers the questions that need no changes. Part B is the work to approve.

## Step 0 (do first, before the handoff): commit and push the current work

Current state: branch `main`, remote `origin` = github.com/tylerirvin543/Steamboat_Creek_Geochemistry_Database, last commit `62f7404`, 28 changed or untracked paths. This plan file sits in `.posit/` which git ignores, so a copy must be committed for an agent that works from a clone.

1. Copy this plan to `docs/handoff/2026-11-08-plan-permit-wells-lindsey-thermal.md` (tracked, so it can be pulled).
2. Stage normally: `AGENTS.md`, `data/raw/arcgis/README.md`, `database/schema/11_fault_traces_schema.R`, `docs/action_items_for_user.md`, `scripts/ingest/export_geopackage.R`, `ingest_fault_traces.R`, `scripts/leapfrog/README.md`, `export_leapfrog.R`, `scripts/run_pipeline.R`; new files `database/schema/25_*.R`, `26_*.R`, `27_*.R`; `scripts/analysis/cl_b_mixing_monitoring_wells.R`; `scripts/ingest/fill_well_collar_from_locations_3dep.R`, `helpers/parse_collar_appendix_a.R`, `ingest_collar_plate3_locations.R`, `ingest_collar_spring_observations.R`, `ingest_digitized_features.R`, `link_collar_logs_to_wells.R`, `register_sbw0003_and_boyd_fix.R`; `scripts/leapfrog/dem_helpers.R`, `export_leapfrog_structure.R`; `data/derived/collar_appendixA_spring_coverage.csv`, `collar_plate3_coordinate_comparison.csv`, `dem_elevation_discrepancies.csv`; `docs/figures/Skalbeck_wellcompletion_watertype_figure.png`; the handoff copy of this plan.
3. Force-add the hand-maintained raw files that `data/raw/` ignores (repo convention): `data/raw/wells/collar_private_wells.csv` (already tracked, modified), `data/raw/wells/collar_log_well_links.csv`, `data/raw/wells/sbw0003_identity_leads.csv`, `data/raw/historical/collar1990_appendixA_spring_observations.csv`, `data/raw/arcgis/excel ingest/collar_plate3_clean.csv`, `data/raw/arcgis/faults/Fault_Traces_Dhakal.gpkg`, `data/raw/arcgis/features/Steamboat_digitized_features.gpkg`, `data/raw/dem/README.md`. Do **not** add the DEM `.tif` tiles (about 1.6 GB), the databases, `output/`, or `docs/literature/`.
4. Leave out the stray scratch file `chronology_table_orig.txt` (ask the user if it should be deleted or kept).
5. Check `git status` shows nothing unexpected staged (no `.sqlite`, `.tif`, `.pdf`), commit with a message summarizing: Collar Plate 3 and Appendix A ingests, Jeppson/Rogers/Boyd/SBW_0002 links, SBW_0003 and identity leads, Dhakal faults, digitized fissures and polygons, DEM-based Z for all Leapfrog features, spring observations table; then `git push origin main`. Report the commit hash.

## Text to give the next agent

> Work in `C:/Projects/Steamboat/Steamboat_Geochemistry_Database` (repo `tylerirvin543/Steamboat_Creek_Geochemistry_Database`, branch `main`). `git pull` first. Read `docs/handoff/2026-11-08-plan-permit-wells-lindsey-thermal.md` (same file as `.posit/assistant/plans/2026-11-08-1929-plan.md` on the original machine) and follow its "Handoff" section: read the listed files in order, then execute Part B in the stated order, stopping at each checkpoint for my approval. Back up the database before writing, keep every step idempotent and fill-only, and do not commit unless I ask.

## Handoff: how a new session should pick this up

**Start by saying:** "Read `.posit/assistant/plans/2026-11-08-1929-plan.md` in `C:/Projects/Steamboat/Steamboat_Geochemistry_Database` and execute Part B, in the order below, stopping at the checkpoints."

**Read first, in this order (about 15 minutes):**
1. `AGENTS.md`, the **Session 64** entry at the end (Plate 3, SBW_0003, faults, digitized features, DEM/Z policy), then Sessions 21-22 (NDOM permit ingest, the pattern B2 copies), 24-25 (well-log and Well_Work_Events patterns) and 36 (what broke when rebuilding the DEMO database).
2. `docs/action_items_for_user.md` section 0 (current priorities, decisions, field task for the capped pipe).
3. `scripts/leapfrog/README.md` (CRS, DEM and Z policy; `dem_helpers.R`) and `data/raw/dem/README.md`.
4. `data/raw/nbmg/README.md`, `data/raw/ndom/README.md`, `database/schema/README.md` (what each numbered schema file does; the next free numbers are 28 and 29).
5. Code to copy patterns from: `scripts/ingest/ingest_ndom_wells.R` (permit staging, name resolution, fill-only), `scripts/ingest/ingest_white_geyser_features.R` (chemistry rows via Sampling_Events/Samples/Lab_Analyses), `scripts/ingest/register_sbw0003_and_boyd_fix.R` and `database/schema/26_well_identity_leads_schema.R` (SBW_0003 and its leads), `scripts/ingest/ingest_digitized_features.R` (replace-per-source-layer idempotency), `scripts/analysis/conservative_tracer_ratios.R` and `scripts/phreeqc/08_build_phreeqc_tables.R` (ratios, charge balance, eligibility).
6. Source documents: `docs/literature/Lindsey_etal_2016_GeyserE_renewedA_steamboat.pdf` (really the Feb 2026 paper; Table 5 is the chemistry), `data/raw/nbmg/GEOTHERM06102019.csv` (identical to `C:/Users/tyler/Downloads/GEOTHERM06102019(main).csv`; UTM columns are mostly **NAD27**), `data/raw/nbmg/Geothermal_Wells.csv` (NBMG ArcGIS layer, NAD83 lat/lon, use it to validate the NAD27 conversion).

**Decisions already made by the user (do not re-ask):** put every real well in the record into the database with the Lower Sinter Terrace as focus; watch duplicates and make every step idempotent; SBG001 (pipe) goes on `SBW_0003`; SBG002 (runoff) goes on `SBF_0001` as a second sample; SBW_0001 is the unmarked abandoned well across the creek, not the eruption pipe; Pine Tree Ranch-2 and Peigh Pool screens stay as stored; Plate 3 is trusted to a few tens of metres; Z always comes from the DEM.

**Order of work and checkpoints:**
1. B2 report only (matching list, new-wells list, NAD27 validation); **stop and show the user** before writing to the database.
2. B1 well classes, then B2 load, then B3 lithology (show parsed intervals first), B4 elevation/coordinate fixes (list each proposed change for approval).
3. B7 Lindsey chemistry and comparison (independent of the rest; can run first if it is quicker).
4. B5 thermal polygons last (needs the user's survey dates and cutoffs).
5. B6 documentation, then re-run `export_leapfrog_*` and `export_geopackage` and report counts.

**Rules that matter in this repo:**
- Back up `database/geochem_operational.sqlite` to `database/archive/` before any write; test a new ingest on a scratch copy first; fill-only, never overwrite a stored value; log disagreements to `data/derived/`; re-run each script twice to prove it adds 0 rows.
- Wire new stages into `scripts/run_pipeline.R` the same way as the last ones (flag in all three presets, help text line, schema `source()` in both places, `run_step`). The `edit` tool often fails on exact matches in this repo; use `readLines()`/`writeLines()` splices and check with `parse()` and `grep -c $'\r\r'`.
- All UTM is NAD83 / zone 11N except the NBMG compilation (NAD27 unless the row says 83). Elevations: leave empty and let `refresh_dem_elevations()` fill them.
- New files under `data/raw/` need `git add -f`. Do not commit unless asked. Plan mode applies until the user approves.

## Part A. What I found (read-only)

### A1. What Lindsey et al. (2026) say about the geysering pipe
- Described as "an uncapped shallow pipe, of unclear origin" and later "an uncapped, shallow (~15-20 m) pipe" (about 49-66 ft). Figure 1a calls it "an uncapped shallow well on the Lower Sinter Terrace".
- 3 June 2025: it "briefly discharged boiling water and steam nearly 30 meters into the air"; episodic discharge in mid-June, then it was capped. Discharge then moved laterally to new small springs and spouters on the northern margin of the sinter mound.
- The paper says legacy wells and pipes in the area "locally intersect shallow hydrothermal zones" and can act as artificial vents. It calls the eruption the first geyser-like activity "in many decades".
- Measurements: a temperature logger was put in the pipe after the eruption stopped; sample SBG001 was taken from the pipe during discharge and SBG002 from the runoff channel. Both fluids are chemically similar (that is already in the project).
- **Not given anywhere in the paper:** casing diameter, exact depth, driller, year, lithology, water level. So there is no log or lithology to take from the paper; the depth range is the only construction number.

### A2. The best lead for the pipe in the new permit file (NBMG GEOTHERM06102019, identical to `data/raw/nbmg/GEOTHERM06102019.csv`)
The file has 150 Steamboat Springs rows. The entry that fits a geysering legacy well best is:
- **API 27-031-80032, "No. 32 Geyser Well"**, Steamboat Resort(?), NW/4 SE/4 Sec 33 T18N R20E, drilled before or during 1945, abandoned, TD 43 ft (13 m), TD temperature 115 C, no cuttings. Remark: "Reported geysering 70' at nearly one week intervals between 1945-1952."
- Your plate point `32 "Well"` (White's well 32) is the same well. It is already a lead on SBW_0003, but this remark makes it much stronger: it is a documented geyser well. Depth (13 m) is a little under Lindsey's 15-20 m; the pipe may have been deepened or the depths are approximate.
- Other nearby resort wells in the file: Steamboat No. 2 (120 ft, 1945, obstructed 1947) and No. 4 (225 ft, 1947-48, 83 C at 19 ft to 155 C at 184 ft, lithology: alluvium and sinter over older alluvium, 6 in hole cased to 93 ft), both in the same quarter-quarter; South Steamboat Well (275 ft, 1946-47, 15 C at 6 ft to 74 C at 275 ft).
- **Caveat that affects all matching:** the UTM columns in this file are **NAD27 zone 11** (145 of 148 rows say NAD 27; 3 say NAD 83). NAD27 coordinates must be converted with EPSG:26711, not 26911 (we found a 214 m offset between the two earlier). Distances to the pipe, fissure and plate points must be computed after that conversion.

### A3. Is the Leapfrog export consistent for the Lower Sinter area?
- CRS: every X/Y is NAD83 / UTM 11N and Z comes from the DEM (done last session). The Skalbeck UTM columns were verified as NAD83.
- Coverage at the Lower Sinter Terrace is thin. In a box around it (39.372-39.390 N, 119.748-119.734 W) there are only **5 of 241 Skalbeck depth-model points**. The Skalbeck horizons and grid are a regional model; near the terrace they are extrapolated, so they should not be used to infer shallow structure there.
- Wells in that box: 23 records. Only GS-5 (3 rows), SBW_0002 (5 rows, from the spa-well log) and the three Skalbeck-classified rows have lithology; the 8 other lithology rows have no formation unit. The Ormat wells in Sec 33 (14A-33, 43-33, 23-33RD) have no lithology at all, and neither do GS-1, GS-3, GS-4, GS-8, the five 2025 monitor-well logs, or the Boyd/Towne logs.
- The permit file's `TOPS` column holds a depth-prefixed lithology string for many Steamboat wells (for example Observation Well No. 1: "Surface Sinter, clay; 125' Andesite; 320' Granodiorite"). This is the main untapped source of Lower Sinter lithology. Part B3 parses it.
- So the answer to "do the lower sinter wells and their lithology have a place": the tables exist (`Well_Lithology`, `lithology.csv`), but most terrace wells have no lithology yet. The permit file and White's auger holes (13 holes, 8 in Sec 33) can fill that.

### A4. Direction for the chemistry (my recommendation)
1. **Core thesis deliverable:** a calibrated chloride-conductivity relation that gives a continuous chloride and thermal-discharge record at SBRR/SBGG (needs paired samples during logger deployment; the sampling plan is the blocker).
2. **Interpretation layer:** the PHREEQC mixing/reaction-path work as a one-time baseline of the terrace fluids (parent fluid, mixing fractions, process by feature type), to be repeated when new samples arrive.
3. **Spatial layer:** attach chemistry to the 3-D model as point and interval attributes (Cl, Cl/B, temperature, facies), sampled at wells, springs and the pipe, not as an interpolated volume. Use fault-bounded compartments only once faults are better constrained.
4. **Test of the eruption question:** conservative tracer ratios (Cl/B, Na/Cl) through time at the terrace features and monitoring wells.
Nothing here needs a code change now.

### A5. How to convert the thermal PDFs to GeoTIFF and make threshold polygons in ArcGIS Pro
Important first: the three PDFs are rendered colour images, so temperature has to be recovered from the colour bar. The original radiometric GeoTIFF from NBMG would be better; ask Cary Lindsey for it if possible.
1. **Add the PDF.** Map > Add Data and pick the geospatial PDF; Pro reads the embedded georeference and shows it as a raster layer. If it does not load, run **Data Management > Raster > Raster Dataset > Copy Raster** with the PDF as input, or convert it outside Pro with GDAL (`gdal_translate in.pdf out.tif`), which is what the R route in B5 does.
2. **Export.** Right-click the layer > Data > Export Raster. Format TIFF, pixel type 8-bit unsigned, 3 bands (RGB), coordinate system NAD 1983 UTM Zone 11N, cell size as the source. Save to `data/raw/arcgis/thermal_infrared/`.
3. **Check the georeference** against known points (fissure, pipe, wells). If it is off by more than a few metres, use Imagery > Georeference with control points.
4. **Make a temperature raster.** Sample the colour bar (Spatial Analyst > Extract Values to Points on a short line drawn along the bar) to get RGB for each temperature, then assign each pixel the nearest bar colour. In Pro the practical route is **Image Analyst > Classify > Iso Cluster Unsupervised Classification** with as many classes as bar intervals, then **Reclassify** each class to its temperature. (In R with `terra` this is exact nearest-colour matching and is reproducible; I propose to do it there.)
5. **Threshold and polygonize.** Reclassify to 1 where temperature >= the cutoff (for example 20, 30, 40 C) and 0 elsewhere, run **Conversion > Raster to Polygon**, keep value 1, **Dissolve**, and optionally **Eliminate Polygon Part** / smooth to remove speckle.
6. **Attributes:** `survey_date` (July 2025 survey flown 7-8 July; October survey 1 Oct 2025), `cutoff_c`, `source` (file name), `method` (colour-bar classification), `uncertainty_c`.

## Part B. Work to do after approval

### B1. Well-class vocabulary for GIS and the Locations layer
- Today `Wells.well_role` is limited to production, injection, monitor, domestic, unknown (a CHECK constraint that SQLite cannot widen), and `Locations.site_type` has no well categories.
- Add, without touching the constraints: `Wells.well_use` (production, injection, observation, thermal_gradient, stratigraphic_test, domestic, resort_spa, historical_exploration, abandoned_unmarked, eruption_pipe, unknown) and `Wells.well_status` (in_use, shut_in, idle, plugged_abandoned, abandoned_unplugged, unknown), seeded from `well_role`, NDOM class/status, and the Well_Work_Events P&A rows.
- Seed rules: SBW_0002 = resort_spa; SBW_0001 = abandoned_unmarked; SBW_0003 = eruption_pipe; GS and auger holes = historical_exploration; Ormat/SB Geo wells by NDOM class.
- Add a derived `feature_group` to the GeoPackage `locations` and `wells` layers (via the existing views) so ArcGIS can symbolize production / injection / monitoring / domestic / abandoned / resort / eruption pipe separately. Keep `display_status`.
- Check: counts per group; every Wells row with a coordinate appears in a layer exactly once.

### B2. Match the permit file to our wells and make the "new wells" list
- Read `data/raw/nbmg/GEOTHERM06102019.csv` for Steamboat rows (KGRA "Steamboat Springs" plus Washoe T17N-T18N R19E-R20E), convert UTM with the file's own datum column (NAD27 → EPSG:26711; NAD83 rows → 26911), match to `Wells` by API, NDOM permit, and normalized name/aliases.
- Outputs (new, derived, no database writes yet): `data/derived/nbmg_steamboat_well_matching.csv` (matched, with distance between the permit coordinate and ours, flagged above 100 m) and `data/derived/nbmg_steamboat_new_wells.csv` (not in our database, with a "useful for" note and priority).
- Expected high-value additions: Observation Wells 1-4 and Injection/Production Wells 2-3 (SB Geo, with lithology), TG 1-3 (thermal-gradient holes, Sec 28), the resort wells (No. 2, No. 4, South Steamboat, No. 32 Geyser Well), Auger Holes 3, 4, 5, 6, 11, 12, 13 (Sec 33), Geohl/Gerold domestic (permit 0047, 460 ft, hot, 210 Rhodes Road: matches your plate "Gerold"), MTH 12-33 / 24-33 and 21-33 (Sec 33), Reno Retail 24-28, 87-29, 16-28, 26-28, 25-28-1/-2, 36-28, and the Phillips ST holes.
- **New alias evidence to check against Dhakal names:** permit 0298 Well No. 36-28 is recorded as "Formerly ... Well PW-2-4, IW-6"; permits 0288/0289/0290/0291 (16-28, 26-28, 25-28-2, 25-28-1) were originally Steamboat Development Corporation wells 1-16, 2-16, 3-25, 4-25. These may be the missing PW 2-2/2-4 and PW 3-x identities; proposed as aliases only after your confirmation.
- **Decision (2026-11-08): put every well in the record into the database**, with the Lower Sinter Terrace (Sec 28/29/32/33 T18N R20E plus Sec 5/6 T17N R20E) as the focus. Design so a re-run never duplicates:
  1. **Staging table** `NBMG_Compilation_Records` (new, schema file 28): one row per source row, all 150 Steamboat rows kept verbatim (including expired, not-drilled and project-area rows), unique on (api, permit, well name), plus `match_method`, `matched_well_id`, `loaded_to_wells`, and a hash of the row so a changed source row is noticed rather than silently re-added.
  2. **Wells are created only for rows that are real wells** (status Drilled, Production, Injection, Observation, Shut-in, Idle, P&A, Abandoned, Domestic, etc.). Rows with status Expired / Not drilled / Unknown with no TD, and the two project rows (`27-031-80077` Project Area, `N-12085` 16-32 Project), stay in staging only, flagged `permit_only`, because a permit is not a well.
  3. **Match order before any insert:** API number → NDOM permit number → normalized name (strip "Well No.", "Industrial Production Well", "Injection Well", "Observation Well", "Domestic") → `Well_Aliases` → existing known variants (21-5 = 21-5R, 13-5 = 13-5R, 83B-6 = 83B-6R, 46-28-2 = 46-28, and so on). A row that matches exactly one well only fills empty fields; a row matching more than one well, or whose coordinate is more than 200 m from the matched well, is held for review, not merged.
  4. **Known same-name collisions to handle explicitly:** 13-5 (permits 205 and 340), 65-32 (188 and 215), 77-29 (302 and 386), 45-21 style redrills, two Steamboat No. 2/No. 4 wells (Steamboat Resort 1940s vs Nevada Thermal Power 1960 vs SB Geo), and Towne permits 201/226/227 (proposed, expired, not wells). Multiple permits for one real well are stored as separate staging rows pointing to one `Wells` row.
  5. **Coordinates:** UTM converted as NAD27 (EPSG:26711 → NAD83 lat/lon) per the file's own datum column, after checking the conversion against the NBMG ArcGIS latitude/longitude for the same API numbers (they should agree to a few metres if the datum is right). Rows with no UTM (0,0) are loaded without a coordinate.
  6. **Elevation:** the file's elevation (feet, often "estimated") is stored in staging and in notes only; `Wells.elevation_m` for new wells is left empty so the DEM refresh fills it (consistent with the DEM policy).
  7. **Fields:** api_number, ndom_permit, operator, spud/completion dates, status, class, total depth, remarks, and the `TOPS`/`LOGS`/`SAMPLES` text go to staging; `Wells` gets only identifiers, dates, depth, well_use/well_status (B1) and coordinate with source `nbmg_geothermal_compilation_nad27_converted`.
  8. **Idempotency checks to run after the load:** second run inserts 0 rows and changes 0 fields; no two `Wells` share an API number; no `Wells.well_name` duplicates; row counts per status reported; every previously matched well keeps its `well_id` and its coordinate unless explicitly approved.
  9. The review lists from the first bullets are still produced before anything is written, so the first load is a report, then approved, then applied.

### B3. Lithology from the `TOPS` column
- Parse strings such as "Surface Sinter, clay; 125' Andesite; 320' Granodiorite" into depth intervals (feet) for matched/new Steamboat wells, classify into the existing formation units where unambiguous, and store in `Well_Lithology` with a confidence flag. Show the parsed intervals for review first; do not write to the database until you approve.
- Do not assign any of this to SBW_0003. For the pipe, record the Lindsey parameters (15-20 m, uncapped, jet about 30 m, SBG001) in its notes and `Well_Identity_Leads`, and add the No. 32 Geyser Well remark (geysered about 70 ft every week, 1945-1952, TD 115 C) to that lead. For 3-D modelling the pipe gets an "expected column" from the nearest logs (Steamboat No. 4, South Steamboat Well, Towne 5711, auger holes 11-13, GS-1) as a clearly labelled proxy, not as its own lithology.

### B4. Fix the elevation and coordinate disagreements
- Gather, for 83B-6R, 83C-6ST1, 13-5R and STMGID MW1: NDOM xlsx elevation/UTM, the permit-file elevation/UTM (NAD27), NBMG ArcGIS lat/lon, plate or ArcGIS point, and the DEM at each.
- Early findings: 83B-6R's stored elevation (1243.6 m = 4080 ft, from NDOM) is not credible; the permit file gives 5760 ft for the same pad (83-6 family, about 1755 m) and the DEM says 1748 m. 83C-6ST1's stored elevation (1749 m) matches the 83-6 pad but its coordinate (39.3720, -119.7610) is about 1 km east of that pad, so the coordinate looks wrong. 13-5R's NDOM elevation (1625 m, 5330 ft) differs from the permit file (5600 ft) and DEM (1724 m). STMGID MW1 is outside the Steamboat field (Reno side) and needs its NDWR record.
- Proposed fix: use the permit-of-record coordinate (converted from NAD27) and the DEM elevation; record the old values in notes and in `data/derived/well_coordinate_review.csv`; no silent overwrite, and each change listed for your confirmation.

### B5. Thermal imagery to GeoTIFF and threshold polygons (R route, matching A5)
- Convert the PDFs with GDAL through `terra`/`sf` (already installed) into `data/raw/arcgis/thermal_infrared/*.tif`, check georeference against known points, calibrate colour-to-temperature from the legend, and write threshold polygons with the attributes in A5.
- New table `Thermal_Areas` (polygon, survey_date, cutoff_c, source_file, method, uncertainty_c) plus an export layer and Leapfrog 3-D shapefile with Z from the DEM.
- Needs from you: the survey date for each PDF (I assume 7-8 July 2025 for the first two and 6 June 2025 for the field sketch, which is not thermal), and the cutoffs you want (default 20, 30, 40 C).

### B6. Documentation
- `docs/action_items_for_user.md`: add the Geyser Well lead, the NAD27 warning, the alias candidates, and the questions below. `AGENTS.md` and `scripts/leapfrog/README.md`: record the well-class fields and the NAD27 rule for the permit file.

### B7. Store Lindsey et al. (2026) fissure chemistry and compare it with ours

**What the paper gives (Table 5, "samples from the lower sinter terrace"):** two samples, no sample temperature, no date beyond "June 2025 onward" (SBG001 was taken "directly from the geysering pipe during active discharge", so between 3 June and the capping; SBG002 from "a nearby runoff channel receiving overflow from the same feature"). Values as printed:

| | pH | EC uS/cm | TDS | Na | K | Ca | Mg | Cl | SO4 | Alk (as HCO3) | Si | B | Li | As |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SBG001 pipe | 8.9 | 3660 | 2300 | 704 | 53.6 | 6.49 | 0.166 | 913 | 153 | 215 | 114.5 | 40200 | 6990 | 2040 |
| SBG002 runoff | 8.8 | 2620 | 1720 | 597 | 45.3 | 4.83 | 0.13 | 638 | 112 | 158 | 105.5 | 34100 | 5840 | 1750 |

Units: mg/L except B, Li, As in ug/L (the text confirms B 34-40 mg/L, Li 5.8-7.0 mg/L, As 1.75-2.04 mg/L). Stable isotopes are only plotted (Fig. 8), not tabulated.

**Our closest samples (already in the database, 2026-04/05):** SBF_0001 fissure (816): Cl 815, Na 656, K 48.6, SO4 132, alkalinity 299 (HCO3 basis), Si 106.5, B 36.0, Li 6.45, As 1.6 mg/L; SBW_0002 resort tank (815): Cl 849, Na 686, K 55.5, SO4 158, B 37.1, Si 102, Li 7.21.

**First read (to be confirmed by the computation, not a result yet):** the pipe sample is the most concentrated of the set (Cl 913 vs 815 at the fissure, about 12% higher; Na, K, SO4, Si, B, Li all 5-13% higher) but the proportions agree: Cl/B is 22.7 for SBG001 and 22.6 for SBF_0001, and charge balance for SBG001 works out to about 0.3% from the printed values. SBG002 (runoff) is diluted by roughly 30% in Cl with the Cl/B ratio lower (18.7). **Inconsistency to flag:** the text gives alkalinity as 660-905 mg/L as CaCO3, but Table 5 gives 215 and 158 as HCO3; the table values balance the charges, so I will use the table and record the discrepancy.

**Steps**
1. Raw file `data/raw/historical/lindsey2026_table5_chemistry.csv` with the table above, original units and a notes column (no temperature; date "2025-06, exact day not stated"; Alkalinity discrepancy). Needs `git add -f` later like other raw CSVs.
2. Ingest script `scripts/ingest/ingest_lindsey2026_chemistry.R` in the same style as `ingest_white_geyser_features.R`: new `Data_Sources` row; **SBG001 (the pipe) attached to the existing `SBW_0003` Location; SBG002 (the runoff) attached to the existing `SBF_0001` Location** (the fissure logger, A005), as a second, separate sample there, not a new location. Per your answer: the runoff sample is the equivalent of where you sampled, in the fissure and downstream of the pipe; `SBF_0002` (fumarole, A008) is the second point you placed inside the fissure closer to the well and has no chemistry yet. No new Locations are created. `Sampling_Events`/`Samples`/`Lab_Analyses` with the project's analyte codes (`Alkalinity` on the HCO3 basis, `Si` as element, B/Li/As converted to mg/L, `pH`, `SC`, `TDS`); date stored as 2025-06-01 with the precision noted in the event notes. Idempotent by external event id. Samples without temperature are not PHREEQC-eligible, so nothing is fed to PHREEQC (an optional later run if Cary Lindsey supplies the sample temperature).
3. Comparison, as a read-only view `vw_lindsey_vs_field` plus `data/derived/lindsey2026_vs_field_comparison.csv`. **Main pair: SBG002 (June 2025) against our sample 816 taken at the same Location SBF_0001 (April-May 2026).** Secondary: SBG001 (pipe) against 816 and against SBW_0002 (815). For each analyte: all four values with percent differences; ratios (Cl/B, Na/Cl, Na/K, Li/Cl, Si/Cl, SO4/Cl); charge balance computed with the project's equivalent weights; Na/K (Giggenbach) and quartz geothermometer temperatures for all four so the two sample sets are compared on the same footing.
4. One figure (`output/figures/lindsey_vs_field_chemistry.png`): a Schoeller-style panel of the four samples on a log axis and a ratio panel (Cl/B, Na/K, Li/Cl, SO4/Cl), with the caption stating the sample dates, that the sets come from different labs, and that this is two samples against two samples, not a trend.
5. Notes for interpretation, to be written in the comparison file and `docs/action_items_for_user.md`: the offset between June 2025 and April-May 2026 samples could reflect real change after the eruption, the pipe-versus-fissure position, steam loss, or lab differences; it cannot be separated with these samples. No change to the thesis text unless you ask.
6. Isotopes: not entered. Ask Cary Lindsey for the delta-18O and delta-D values for SBG001/SBG002 and the sample temperatures and dates; if you prefer, I can digitize Fig. 8 approximately, clearly flagged as read off a plot.

## Questions for you (decide before B2 ingestion)
1. Is it acceptable to treat the permit-file UTMs as NAD27 where the file says so and verify it on a few wells before using any coordinate?
2. ~~Which wells become records~~ Answered: all wells in the record, focus on the Lower Sinter Terrace, with the duplicate and idempotency safeguards in B2. Still to confirm: expired and never-drilled permits stay in staging only (not as Wells), as in B2 item 2?
3. Thermal cutoffs and survey dates for B5.
4. ~~Where SBG001/SBG002 go~~ Answered: SBG001 on SBW_0003, SBG002 on SBF_0001. Still open: do you want isotope values digitized from Lindsey's Fig. 8, or wait for the numbers from Cary?
