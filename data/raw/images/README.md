# `data/raw/images/` — Field Photos/Video and EXIF-GPS Extraction

## What this is

Photo and video assets from field work and the 2025 Lower Sinter
Terrace eruption/response, used two ways: (1) automatic EXIF-GPS
extraction to register or QC-check `Locations` coordinates, and (2)
direct visual review (e.g. for the website Timeline page and this
project's own historical-figure/literature-page rendering).

## Subfolders

- **`exiftool/`** — the bundled `exiftool.exe` binary (no system
  install required) used to read EXIF/GPS tags from photos and videos.
- **`exiftool_csv_data/output.csv`** — a cached bulk-exiftool CSV
  export (regenerable; not authoritative on its own).
- **`image_drop/`** — **the actual raw-media drop folder**: place new
  field photos/videos here. `scripts/ingest/ingest_image_locations.R`
  scans this folder automatically (mp4/mov/m4v video formats included,
  not just still images) and extracts any embedded GPS/`GPSHPositioningError`
  tag into `Photo_Location_Candidates` — a two-step, deliberately
  non-automatic process (see below).
- **`image_location_map.csv`** (not shown above but read by the same
  script) — the human-maintained mapping from a specific filename to
  an `external_station_code`/`site_type`/`name`, the *only* thing that
  actually creates or touches a `Locations` row from a photo. A new
  code registers a new location; an existing code gets a distance
  comparison logged to `Photo_Location_QC` rather than silently
  overwriting an existing coordinate.

## Ingestion behavior (two-step, by design)

1. **Automatic**: `ingest_image_locations.R` extracts whatever GPS
   data a photo/video actually has into `Photo_Location_Candidates`
   (append-only, keyed by filename) — most drone/phone video checked
   so far carries **no** embedded GPS at all, which the pipeline
   handles by skipping cleanly, not erroring.
2. **Manual**: a human fills in `image_location_map.csv` to actually
   register or cross-check a `Locations` row. See
   `notebooks/04_photo_location_workflow.qmd` for a full worked example.

## Known limitations

- Most video assets checked so far have no embedded GPS — the
  pipeline is ready for geotagged video, but the real 2025-2026 event
  clips on hand needed a manual coordinate/station code like any
  un-geotagged photo would.
- Full-resolution original photos/videos live here (gitignored — this
  is real raw media, not something to commit); compressed copies used
  on the public website live separately under `website/assets/`.
