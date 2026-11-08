# `data/raw/dem/` : elevation rasters

USGS 3DEP 1 m DEM tiles (project NV_USFSR4_D23), NAD83 / UTM zone 11N, metres, NAVD88. Downloaded 2026-11-07 from the National Map (prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/NV_USFSR4_D23/TIFF/).

| Tile | Covers | Used for |
|---|---|---|
| `USGS_1M_11_x26y437_...tif` | E 260-270 km, N 4360-4370 km | the Steamboat core (faults, fissures, springs, most wells) |
| `x25y437`, `x25y436`, `x26y436` | the Skalbeck (2001) grid to the west and south | Z for the 63,840 grid cells and 241 horizon points |
| `x25y438`, `x26y438` | north of the core | Z for 42 northern collars |

Every `.tif` in this folder is mosaicked automatically (`scripts/leapfrog/dem_helpers.R`), so adding a tile is enough; nothing else needs editing. Tiles to the west (x24y436-438) would cover the 3 collars still using a stored elevation. Raster values do not depend on how the layer is displayed in ArcGIS (recomputing statistics changes only the stretch). Raw rasters are gitignored with the rest of `data/raw/`.
