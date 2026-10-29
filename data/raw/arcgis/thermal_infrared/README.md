# Thermal-infrared / field-sketch imagery, Lower Sinter Terrace

Three real, user-supplied PDFs, added 2026-10-27, finally closing the
"thermal-infrared raster files are not yet on disk" gap flagged in
`docs/action_items_for_user.md` item 12 and in several `AGENTS.md`
session entries since September 2026.

| File | Source | What it shows |
|---|---|---|
| `thermalmap_broad_july2025.pdf` | NBMG/Owen Callahan drone TIR survey, flown July 2025 | A full Lower Sinter Terrace thermal overlay on satellite imagery, with labeled TGCP (thermal ground-control point) and water-temperature measurement locations, the resort well/pools area, and a visible warm channel tracking Steamboat Creek. |
| `fissure_system_zoomin_calibrated_july2025.pdf` | Same survey, calibrated | "Steamboat_Z_TIR_ortho_July_clp" -- a calibrated-temperature (7-44 C) thermal orthophoto of the fissure/western-margin area, showing discrete bright point sources along the terrace's western margin alongside a broader, diffuse warm signature tracking the creek channel itself -- the real image behind this project's previously qualitative-only description of "two visually distinct kinds of warm signature." |
| `busick_property_sketch_map_20250606.pdf` | Real, hand-annotated field sketch, June 6, 2025 visit | Active/dry fissure traces, driveway cracks, sulfur and red/orange staining, and named features (Driveway Spring 95.1 C, New North Fumarole 95.8 C, a 2024 small inactive fumarole, the Geyser/Pipe eruption site, Big Pool, and a small warm seep ~80 m away) at the Busick property, dated five days after the first documented June 2025 eruption pulse. |

All three are single-page, very large (up to ~80 MB) georeferenced
PDFs -- not committed to git (this whole directory sits under the
blanket-ignored `data/raw/`). Derived, resized figures for the
manuscript are built by
`prepare_thermal_imagery_figures()` in
`scripts/analysis/manuscript_figures.R`, written to
`output/figures/manuscript/` (also gitignored, regenerated on demand,
consistent with this project's standing "no static committed figures"
convention).
