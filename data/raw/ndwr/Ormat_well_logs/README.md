# NDWR Well-Log PDFs -- Drop Folder

This folder holds Nevada Division of Water Resources (NDWR) "WELL
DRILLER'S REPORT" PDFs for wells in and around the Steamboat field.
`scripts/ingest/ingest_well_logs.R` (`ingest_well_logs(con)`, wired
into `run_pipeline.R` as `RUN_INGEST$well_logs`) reads every PDF in
this directory automatically -- **just drop new files in here and
re-run the pipeline**, no code changes needed.

This entire folder is gitignored (large public-record scans don't
belong in git -- see `.gitignore`). Nothing here is lost if you clone
the repo fresh; re-download from NDWR using the steps below.

## Where to get well logs

NDWR publishes these records through a few related tools -- start with
whichever one you already have information for (a log/permit number,
an owner name, or a map location):

- **Well Log Query** (search by log number, permit number, owner name,
  or basin/township/range):
  https://tools.water.nv.gov/WellLogQuery.aspx
- **Interactive well-log map** (NV Hydrology viewer -- click a well
  point to pull up its log directly, useful when you only know a
  location, not a log number):
  https://webgis.water.nv.gov/Html5Viewer/Index.html?configBase=http://webgis.water.nv.gov/Geocortex/Essentials/REST/sites/Hydrology/viewers/NV_Hydrology/virtualdirectory/Resources/Config/Default
- **NDWR's full list of web map applications** (if the above link ever
  moves, or you need a different NDWR layer -- e.g. water rights,
  basins):
  https://water.nv.gov/maps-and-gis-data/web-map-applications

Both the Well Log Query tool and the interactive map let you download
a PDF of the actual scanned driller's report. Some wells have **two
downloadable versions**: the original scanned form, and a newer
"reformatted/streamlined" re-scan. Download both if both are offered
(see naming convention below) -- they sometimes carry different
information (one may have a field the other doesn't, or a legible
value where the other is OCR-garbled), and the ingest pipeline merges
them automatically, preferring whichever source is more legible/
higher-confidence for each field.

## File naming (important -- this is how the pipeline groups files)

Save each PDF using the **NDWR log number as the filename**, exactly
as it appears in the Well Log Query results (the "Log" column):

| File | Meaning |
|---|---|
| `<log_number>.pdf` | The primary/original scanned report |
| `<log_number>(2).pdf` | The reformatted/streamlined re-scan of the *same* log, if NDWR offers one |

Examples already in this folder: `8188.pdf` + `8188(2).pdf`,
`104216.pdf` + `104216(2).pdf`.

Do **not** rename files any other way (e.g. by well name or owner) --
the pipeline identifies a log purely by this filename pattern. If your
browser saves a duplicate download with a suffix like `<log_number>
(1).pdf` (common when you accidentally download the same file twice),
you don't need to clean it up manually -- the pipeline detects
duplicate content by file hash and skips it automatically without
wasting time re-running OCR on it. It's fine to just leave it or
delete it, whichever is easier.

## What happens after you drop files in

Running the pipeline (or calling `ingest_well_logs(con)` directly) will,
for every new file:

1. OCR the scan (most of these are image-only PDFs with no text layer)
   and extract: well name, county, Section/Township/Range, latitude/
   longitude (via a labeled field, an unlabeled scan, UTM conversion,
   or -- as a last resort -- a Bureau of Land Management PLSS lookup
   from Section/Township/Range), depth drilled/cased, static water
   level + date, perforation interval, type of work (new / deepening /
   abandonment / reconstruction / repair / change of use), proposed use
   (domestic / monitor / geothermal / industrial / etc.), and hole/
   casing diameter.
2. Independently cross-reference the log number against NDWR's own
   Well Log Query basin exports already in `data/raw/ndwr/`, for owner
   name and location even when OCR can't read the scan.
3. Stage everything in the `Well_Log_Documents` table. **A log is never
   automatically linked to a specific named well** (e.g. "78-29") --
   that requires a human-confirmed entry in
   `data/raw/ndwr/well_log_document_map.csv` (columns: `log_number`,
   `well_name`, `notes`). Until then, a log with a real coordinate gets
   its own placeholder `Wells` row named `"Unidentified Well (NDWR Log
   <log_number>)"` so the data is visible and mappable without
   overstating how confident the identity match is.
4. A well's status history (new → deepened → abandoned, etc.) is
   tracked over time in `Well_Work_Events`, one row per report, so
   re-drilling or abandonment doesn't overwrite earlier information.
5. `scripts/qc/qc_well_log_matches.R` regenerates
   `data/derived/well_log_match_candidates.csv` -- a nearest-neighbor
   distance report for every still-unidentified log, to help you decide
   whether it matches an existing well before adding it to
   `well_log_document_map.csv`. It never guesses on its own.

Re-running the pipeline after adding more files is always safe --
already-processed files (matched by content, not just filename) are
skipped, so this only spends time OCR'ing genuinely new logs.
