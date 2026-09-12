# ============================================================
# parse_well_log_pdf.R
#
# Purpose:
# Reusable parser for Nevada NDWR "WELL DRILLER'S REPORT" well-log
# PDFs -- designed to be called on ANY well log of this general
# layout, not just the Steamboat-area logs on hand today
# (data/raw/ndwr/Ormat_well_logs/). Extracts the fields needed for
# later 3-D subsurface visualization/modeling: location (lat/lon),
# total depth, screened/slotted interval, and static water level. A
# plain-text lithology block is always returned for manual review;
# structured per-interval extraction is attempted but not trusted
# blindly (see below).
#
# OCR SUPPORT (added 2026-09-05, session 10):
# Most NDWR well-log scans have no extractable text layer at all.
# When that's the case, this function renders each page to a PNG
# (pdftools::pdf_convert) and runs tesseract OCR on it. This previously
# failed in this project's sandboxed environment because the
# `tesseract` package's .onLoad tries to dir.create() a cache
# directory under the user's OS-level AppData folder (outside the
# project), which the sandbox blocks. Fixed by redirecting that cache
# into the project via the R_USER_DATA_DIR environment variable
# (which `rappdirs::user_data_dir()` -- what tesseract uses
# internally -- checks first, before falling back to the OS-specific
# path) BEFORE `library(tesseract)` is ever called. See
# `.ensure_tesseract()` below. This only needs to happen once per R
# session; harmless to call repeatedly.
#
# LAT/LON EXTRACTION -- THREE FALLBACK LEVELS, WHY:
# Ground-truthed against the actual scanned forms (2026-09-05,
# session 10) for three examples (log 125850, 123802, 103616):
#   1. Labeled field ("Latitude:"/"Longitude:") -- present and
#      OCR-readable on most forms (e.g. 103616: 39.40739 / 119.75474,
#      correctly read including the fact that this particular form
#      prints longitude WITHOUT a minus sign).
#   2. Some forms have the Latitude/Longitude field printed but OCR
#      fails to read the label cleanly, and the actual value shows up
#      elsewhere as a stray, often handwritten-looking annotation
#      (e.g. 125850's real 39.38951/-119.76694 appeared at the very
#      bottom of the OCR'd page as "39, 389599  \\9. 765920" -- no
#      "Latitude" label survived OCR at all near it). A broader,
#      unlabeled whole-text scan (`.scan_any_latlon()`) catches this,
#      landing within roughly 100-150 m of the true value in the one
#      case checked -- good enough to be useful, but flagged as lower
#      confidence since the pattern is inherently guess-prone.
#   3. Some forms have BOTH lat/lon fields left entirely BLANK (log
#      123802's actual form: "Latitude ____" / "Longitude ____", never
#      filled in) but DO have UTM Easting/Northing filled in instead.
#      `.extract_utm_latlon()` converts that (assuming NAD83 UTM Zone
#      11N, EPSG:26911, correct for the whole Steamboat/Reno area) to
#      decimal degrees via `sf::st_transform()`. Verified against
#      123802's printed UTM E=263623, N=4362985 -> -119.7445, 39.384,
#      which lands exactly in the expected Steamboat cluster.
# All three levels are tried in order; `latlon_method` on the output
# records which one actually supplied the value used.
#
# OTHER ACCURACY CAVEATS -- read before trusting output:
# OCR quality varies enormously across these scans, and INDIVIDUAL
# DIGITS are sometimes simply misread even when a field is located
# correctly -- e.g. log 103616's true Depth Drilled/Cased of 552/552
# ft (confirmed from the scanned image) came back as 582/852 from
# OCR. This is a character-recognition error, not a regex/formatting
# problem, and isn't something this function can safely detect or
# correct (unlike the "0 vs O" and "missing minus sign" cases, which
# have an unambiguous, principled fix). Depth/water-level/perforation
# numbers extracted via OCR should be treated as approximate until
# spot-checked against the source image for anything depth-critical.
# This function:
#   - extracts single-value fields (well name, county, lat/lon, depth
#     drilled, cased depth, static water level, perforation/slot
#     interval, completion date) via label-anchored regex tolerant of
#     several OCR noise patterns observed across examples;
#   - sanity-checks latitude/longitude against a Nevada bounding box;
#     for longitude specifically, if a plausible magnitude (113-121)
#     is found WITHOUT a negative sign, it is corrected (Nevada is
#     unambiguously west) and flagged, rather than either silently
#     trusting the positive value or discarding it;
#   - deliberately does NOT reliably parse the lithology/formation
#     table into structured intervals for most scans -- multi-column
#     layouts get word-wrapped and interleaved by OCR (columns bleed
#     into each other across rows). A best-effort row-level attempt
#     (`lithology_intervals` attribute) is made using a generic "text
#     ... FROM TO" numeric-pair heuristic, but it is explicitly
#     UNVALIDATED -- treat it as a starting point for human review,
#     not ground truth. The raw OCR text is always returned/stored
#     verbatim too (`lithology_raw_text`), for a human to read
#     directly.
#
# Returns a one-row data.frame (NA for anything not found) plus a
# `flags` character vector column noting anything suspect, and a
# separate `lithology_intervals` attribute (0-row data.frame if
# nothing found).
# ============================================================

library(stringr)
library(pdftools)
library(sf)

# ============================================================
# PLSS (Section/Township/Range) SUPPORT (added 2026-09-12, session 24)
#
# Some NDWR forms leave BOTH the decimal Lat/Lon field and the UTM
# field blank, but always carry a Section/Township/Range -- required
# by the form. This adds a 4th, last-resort lat/lon fallback level:
# look up the PLSS section polygon via BLM's public PLSS CadNSDI
# ArcGIS REST service (https://gis.blm.gov/arcgis/rest/services/
# Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer) and use its centroid.
# Confirmed reachable from this environment and correct before
# relying on it: queried Section 2, T17N R19E (Mount Diablo Meridian,
# BLM's own PRINMERCD='21' for this area) and confirmed its returned
# polygon geometrically contains the real, independently-known
# coordinate of the Shonnard well (39.36460, -119.8199), which sits
# in that exact section per NDWR's own site-naming convention.
# A bare section centroid is a ~1 sq-mi resolution guess -- assigned
# coordinate_uncertainty_m = 800 by the caller; quarter/quarter-
# quarter detail (when legible) would tighten this but is not always
# present on these forms, so is not assumed.
# ============================================================

#' Look up a PLSS section's centroid via BLM's public PLSS CadNSDI
#' REST service. Returns list(latitude=, longitude=) with NA on any
#' failure (network unavailable, no match found, etc.) -- never
#' errors out of the wider parse.
.convert_plss_to_latlon <- function(section, township_no, township_dir, range_no, range_dir, state = "NV") {
  fail <- list(latitude = NA_real_, longitude = NA_real_)
  if (any(is.na(c(section, township_no, township_dir, range_no, range_dir)))) return(fail)

  base <- "https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer"
  twn_pad <- sprintf("%03d", suppressWarnings(as.integer(township_no)))
  rng_pad <- sprintf("%03d", suppressWarnings(as.integer(range_no)))
  sec_pad <- sprintf("%02d", suppressWarnings(as.integer(section)))
  if (is.na(twn_pad) || is.na(rng_pad) || is.na(sec_pad)) return(fail)

  twn_where <- sprintf(
    "STATEABBR='%s' AND TWNSHPNO='%s' AND TWNSHPDIR='%s' AND RANGENO='%s' AND RANGEDIR='%s'",
    state, twn_pad, toupper(township_dir), rng_pad, toupper(range_dir)
  )
  twn_url <- paste0(base, "/1/query?where=", utils::URLencode(twn_where, reserved = TRUE),
                     "&outFields=PLSSID&returnGeometry=false&f=json")

  twn_res <- tryCatch(jsonlite::fromJSON(twn_url), error = function(e) NULL)
  plssid <- tryCatch(twn_res$features$attributes$PLSSID[1], error = function(e) NA_character_)
  if (is.null(plssid) || length(plssid) == 0 || is.na(plssid)) return(fail)

  sec_where <- sprintf("PLSSID='%s' AND FRSTDIVNO='%s'", plssid, sec_pad)
  sec_url <- paste0(base, "/2/query?where=", utils::URLencode(sec_where, reserved = TRUE),
                     "&outFields=FRSTDIVNO&outSR=4326&returnGeometry=true&f=json")

  sec_res <- tryCatch(jsonlite::fromJSON(sec_url), error = function(e) NULL)
  ring_raw <- tryCatch(sec_res$features$geometry$rings[[1]], error = function(e) NULL)
  if (is.null(ring_raw)) return(fail)
  # jsonlite may return this as either a 1 x n x 2 array (single ring)
  # or a plain n x 2 matrix, depending on feature count -- handle both.
  ring <- if (length(dim(ring_raw)) == 3) ring_raw[1, , ] else ring_raw
  if (is.null(ring) || NROW(ring) == 0) return(fail)

  list(latitude = mean(ring[, 2], na.rm = TRUE), longitude = mean(ring[, 1], na.rm = TRUE))
}

.ensure_tesseract <- function() {
  if (requireNamespace("tesseract", quietly = TRUE) && "tesseract" %in% loadedNamespaces()) {
    return(invisible(TRUE))
  }
  if (is.na(Sys.getenv("R_USER_DATA_DIR", NA))) {
    cache_dir <- normalizePath(file.path(getwd(), ".tesseract_cache"), mustWork = FALSE)
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
    Sys.setenv(R_USER_DATA_DIR = cache_dir)
  }
  ok <- requireNamespace("tesseract", quietly = TRUE)
  if (!ok) message("[parse_well_log_pdf] tesseract package not available -- OCR fallback disabled.")
  invisible(ok)
}

#' OCR a PDF page-by-page (only called when there's no text layer).
.ocr_pdf <- function(path, dpi = 400) {
  if (!.ensure_tesseract()) return("")
  n_pages <- tryCatch(pdf_info(path)$pages, error = function(e) 0)
  if (n_pages == 0) return("")
  page_texts <- vapply(seq_len(n_pages), function(p) {
    img <- tryCatch(
      pdf_convert(path, format = "png", pages = p, dpi = dpi,
                  filenames = file.path(tempdir(), paste0("ocr_tmp_p", p, "_", basename(path), ".png")),
                  verbose = FALSE),
      error = function(e) NA_character_
    )
    if (is.na(img)) return("")
    txt <- tryCatch(tesseract::ocr(img), error = function(e) "")
    unlink(img)
    txt
  }, character(1))
  paste(page_texts, collapse = "\n---PAGE---\n")
}

#' Broad, unlabeled whole-text scan for a plausible Nevada lat/lon
#' pair, used only when the labeled scan finds nothing. Tolerates a
#' comma in place of a decimal point (an OCR misread observed in
#' practice). Longitude recovery is best-effort only -- a missing or
#' garbled leading "-1" is common and not something this can safely
#' guess back; when only a latitude-like token is found, longitude is
#' left NA rather than fabricated.
.scan_any_latlon <- function(text) {
  lat_hits <- str_match_all(text, "\\b(3[4-9]|4[0-3])[.,]\\s*(\\d{3,8})\\b")[[1]]
  lon_hits <- str_match_all(text, "-?1[1-2]\\d[.,]\\s*(\\d{3,8})\\b")[[1]]
  lat <- if (nrow(lat_hits) > 0) as.numeric(paste0(lat_hits[1, 2], ".", lat_hits[1, 3])) else NA_real_
  lon <- if (nrow(lon_hits) > 0) {
    raw <- as.numeric(gsub(",", ".", lon_hits[1, 1]))
    if (!is.na(raw) && raw > 0) -raw else raw
  } else NA_real_
  list(latitude = lat, longitude = lon)
}

#' Extract UTM Easting/Northing (labeled "UTM E"/"UTM N" on the form)
#' and convert to decimal degrees, for forms that leave the decimal
#' Latitude/Longitude fields blank. Assumes NAD83 UTM Zone 11N
#' (EPSG:26911) -- correct for the entire Reno/Steamboat area this
#' project covers; would need generalizing (a zone parameter) for use
#' well outside northwestern Nevada.
.extract_utm_latlon <- function(text) {
  e_raw <- str_match(text, "(?i)UTM\\s*E[:=\\s]{0,5}(\\d{5,7})")[1, 2]
  n_raw <- str_match(text, "(?i)(?:UTM\\s*)?\\bN\\b[:=\\s]{0,5}(\\d{6,8})")[1, 2]
  if (is.na(e_raw) || is.na(n_raw)) return(list(latitude = NA_real_, longitude = NA_real_))
  pt <- tryCatch(
    sf::st_sfc(sf::st_point(c(as.numeric(e_raw), as.numeric(n_raw))), crs = 26911),
    error = function(e) NULL
  )
  if (is.null(pt)) return(list(latitude = NA_real_, longitude = NA_real_))
  coords <- sf::st_coordinates(sf::st_transform(pt, 4326))
  list(latitude = coords[1, "Y"], longitude = coords[1, "X"])
}

#' Parse one NDWR "WELL DRILLER'S REPORT" PDF.
#'
#' @param path Path to the PDF.
#' @param use_ocr If TRUE (default), fall back to OCR when the PDF has
#'   no extractable text layer.
#' @return A one-row data.frame, or NULL if no text could be obtained
#'   (no text layer, and either use_ocr = FALSE or OCR unavailable).
parse_well_log_pdf <- function(path, use_ocr = TRUE) {

  pages <- pdf_text(path)
  full_text <- paste(pages, collapse = "\n")
  source_method <- "native_text"

  if (nchar(trimws(full_text)) == 0) {
    if (!use_ocr) {
      message("[parse_well_log_pdf] ", basename(path), " has no extractable text and use_ocr = FALSE.")
      return(NULL)
    }
    message("[parse_well_log_pdf] ", basename(path), " has no extractable text layer -- running OCR.")
    full_text <- .ocr_pdf(path)
    source_method <- "ocr"
    if (nchar(trimws(full_text)) == 0) {
      message("[parse_well_log_pdf] OCR produced no text for ", basename(path), ".")
      return(NULL)
    }
  }

  flags <- character(0)

  extract1 <- function(pattern, text = full_text, group = 1) {
    m <- str_match(text, pattern)
    if (is.na(m[1, 1])) NA_character_ else trimws(m[1, group + 1])
  }

  # Well name: appears after a ")" on the line containing "NAME"
  well_name <- extract1("(?i)NAME[^\\n]*\\)\\s*([A-Z0-9\\-]{2,20})")

  # County
  county <- extract1("(?i)County[.:]?\\s+([A-Za-z]+)")

  # PLSS -- Section/Township/Range. Kept as raw text always (even when
  # lat/lon is already known some other way), since it's an
  # independent cross-check and this project's coordinate-conflict
  # QC (see qc_well_log_matches.R) can flag disagreements. Tolerant of
  # a few common OCR renderings ("T17N", "17 N", "R19E", "19 E").
  section_raw <- extract1("(?i)Sec(?:tion)?[.:]?\\s*(\\d{1,2})")
  township_no_raw <- extract1("(?i)T(?:ownship)?[.:]?\\s*(\\d{1,3})\\s*[NnSs]")
  township_dir_raw <- extract1("(?i)T(?:ownship)?[.:]?\\s*\\d{1,3}\\s*([NnSs])")
  range_no_raw <- extract1("(?i)R(?:ange)?[.:]?\\s*(\\d{1,3})\\s*[EeWw]")
  range_dir_raw <- extract1("(?i)R(?:ange)?[.:]?\\s*\\d{1,3}\\s*([EeWw])")

  # Type of work -- one label may match several ways across form
  # revisions; first match wins so more specific labels (e.g.
  # "Deepening") aren't shadowed by a generic later mention of "New".
  work_type <- NA_character_
  work_type_patterns <- list(
    abandonment = "(?i)\\b(Abandon(?:ment|ing)?|Plug(?:ging|ged)?)\\b",
    deepening = "(?i)\\bDeepen(?:ing)?\\b",
    reconstruction = "(?i)\\bReconstruct(?:ion)?\\b",
    change_of_use = "(?i)\\bChange\\s*of\\s*Use\\b",
    repair = "(?i)\\bRepair(?:ing)?\\b",
    new = "(?i)\\bNew\\s*Well\\b"
  )
  for (wt in names(work_type_patterns)) {
    if (str_detect(full_text, work_type_patterns[[wt]])) { work_type <- wt; break }
  }

  # Proposed use / well purpose.
  proposed_use <- NA_character_
  use_patterns <- list(
    geothermal = "(?i)\\bGeothermal\\b",
    monitor = "(?i)\\b(Monitor(?:ing)?|Piezometer|Observation)\\b",
    domestic = "(?i)\\bDomestic\\b",
    industrial = "(?i)\\bIndustrial\\b",
    irrigation = "(?i)\\bIrrigation\\b",
    municipal = "(?i)\\b(Municipal|Public\\s*Supply)\\b",
    stock = "(?i)\\bStock\\b",
    test = "(?i)\\bTest\\s*Well\\b"
  )
  for (u in names(use_patterns)) {
    if (str_detect(full_text, use_patterns[[u]])) { proposed_use <- u; break }
  }

  # Hole / casing diameter (inches) -- distinguishes a small domestic/
  # monitor pipe from a full-scale geothermal production well.
  hole_diameter_in <- suppressWarnings(as.numeric(extract1("(?i)Diameter\\s*of\\s*[Hh]ole[:=_.\\s]{0,10}(\\d{1,3}(?:\\.\\d+)?)")))
  casing_diameter_in <- suppressWarnings(as.numeric(extract1("(?i)Diameter\\s*of\\s*[Cc]asing[:=_.\\s]{0,10}(\\d{1,3}(?:\\.\\d+)?)")))

  # Latitude / Longitude -- level 1: labeled field, tolerant of OCR
  # noise in the label itself ("Latrtude", "Longitude") but anchored
  # on the numeric decimal-degree value.
  lat_raw <- extract1("(?i)Lat[a-z]*tude\\s*[:=]?\\s*(-?\\d{1,3}\\.\\d+)")
  lon_raw <- extract1("(?i)Long[a-z]*tude\\s*[:=]?\\s*(-?\\d{1,3}\\.\\d+)")
  latitude <- suppressWarnings(as.numeric(lat_raw))
  longitude <- suppressWarnings(as.numeric(lon_raw))
  latlon_method <- if (!is.na(latitude) || !is.na(longitude)) "labeled_field" else NA_character_

  # Level 2: unlabeled whole-text scan (some forms' Lat/Lon labels
  # don't survive OCR near the value at all -- see module docstring).
  if (is.na(latitude) && is.na(longitude)) {
    fallback <- .scan_any_latlon(full_text)
    if (!is.na(fallback$latitude) || !is.na(fallback$longitude)) {
      latitude <- fallback$latitude
      longitude <- fallback$longitude
      latlon_method <- "unlabeled_scan"
      flags <- c(flags, "latitude/longitude found via unlabeled whole-text scan, not a labeled field -- lower confidence, cross-check against an independent source (e.g. NDWR WellLogQuery cross-reference) before trusting")
    }
  }

  # Level 3: UTM E/N -> decimal degrees, for forms that leave the
  # decimal Latitude/Longitude fields blank entirely (confirmed on a
  # real example, log 123802).
  if (is.na(latitude) && is.na(longitude)) {
    utm <- .extract_utm_latlon(full_text)
    if (!is.na(utm$latitude) && !is.na(utm$longitude)) {
      latitude <- utm$latitude
      longitude <- utm$longitude
      latlon_method <- "utm_conversion"
      flags <- c(flags, "no decimal Latitude/Longitude field found (some forms leave it blank) -- derived from the form's UTM E/N instead, assuming NAD83 UTM Zone 11N")
    }

  # Level 4: PLSS (Section/Township/Range) -> centroid, for forms
  # that leave lat/lon AND UTM blank but always carry a PLSS location
  # (a required field). Last resort -- section-level resolution only
  # (~800 m), and depends on a live call to BLM's public REST
  # service (see .convert_plss_to_latlon() above), so this can fail
  # for reasons unrelated to the PDF itself (e.g. no network) -- that
  # failure is silent (NA) and simply leaves lat/lon unset, not an
  # error.
  if (is.na(latitude) && is.na(longitude) &&
      !is.na(section_raw) && !is.na(township_no_raw) && !is.na(township_dir_raw) &&
      !is.na(range_no_raw) && !is.na(range_dir_raw)) {
    plss_ll <- tryCatch(
      .convert_plss_to_latlon(section_raw, township_no_raw, township_dir_raw, range_no_raw, range_dir_raw),
      error = function(e) list(latitude = NA_real_, longitude = NA_real_)
    )
    if (!is.na(plss_ll$latitude) && !is.na(plss_ll$longitude)) {
      latitude <- plss_ll$latitude
      longitude <- plss_ll$longitude
      latlon_method <- "plss_section_centroid"
      flags <- c(flags, "no lat/lon, UTM found -- derived from PLSS Section/Township/Range section centroid via BLM PLSS CadNSDI (~800 m resolution); verify against a tighter source before trusting for anything precision-sensitive")
    }
  }
  }

  # Nevada sanity bounding box (roughly): lat 34-43, lon -121 to -113.
  if (!is.na(latitude) && (latitude < 34 || latitude > 43)) {
    flags <- c(flags, paste0("latitude ", latitude, " is outside a Nevada sanity range -- likely OCR error, verify against the source PDF"))
  }
  if (!is.na(longitude)) {
    if (longitude > 0 && longitude >= 113 && longitude <= 121) {
      # Missing negative sign is a common OCR/transcription slip
      # (confirmed on a real example, log 103616, which prints
      # longitude with no minus sign at all); Nevada is unambiguously
      # west, so correct it but flag clearly.
      flags <- c(flags, paste0("longitude was recorded as positive (", longitude, ") -- corrected to -", longitude, " (Nevada is west longitude); verify against the source PDF"))
      longitude <- -longitude
    } else if (longitude < -121 || longitude > -113) {
      flags <- c(flags, paste0("longitude ", longitude, " is outside a Nevada sanity range -- likely OCR error (e.g. a misread leading digit), verify against the source PDF"))
    }
  }
  if (is.na(latitude) && is.na(longitude)) {
    flags <- c(flags, "no lat/lon found by the labeled field, the unlabeled scan, UTM conversion, or PLSS lookup -- rely on an independent cross-reference (e.g. NDWR WellLogQuery by log number) for this well's location")
  }

  # Depth drilled / cased depth (feet) -- tolerate '=', '_', '.', and
  # extra spaces as OCR filler between the label and the number, and
  # OCR misreads of "Drilled" (e.g. "Dr" + garbled tail). Note: even
  # when this locates the right field, individual OCR'd digits can
  # still be wrong (see module docstring) -- not detectable here.
  depth_drilled_ft <- suppressWarnings(as.numeric(extract1("(?i)Depth\\s*Dr[a-z]{2,8}ed?[:=_.\\s'\u2018\u2019]{0,10}(\\d+)")))
  cased_depth_ft    <- suppressWarnings(as.numeric(extract1("(?i)(?:Depth\\s*)?Cased[:=_.\\s]{0,10}(\\d+)\\s*Feet")))

  # Fallback for the older "Total depth" phrasing (seen in pre-Form-4013
  # logs), which has no separate "Cased" figure in the same field.
  if (is.na(depth_drilled_ft)) {
    depth_drilled_ft <- suppressWarnings(as.numeric(extract1("(?i)Total\\s*depth[:=_.\\s]{0,10}(\\d+)")))
  }

  # Static water level (feet below land surface) -- anchor on the
  # reliably-OCR'd suffix rather than the noisy label, and tolerate
  # arbitrary short OCR filler (e.g. "=", "_") between the number and
  # "feet", plus digit/letter confusion (0<->O/o) within the number.
  static_water_level_raw <- extract1("([\\dOo]+)[^a-zA-Z\\d]{0,4}[Ff]eet\\s*below\\s*land\\s*surface")
  static_water_level_ft <- suppressWarnings(as.numeric(
    if (is.na(static_water_level_raw)) NA_character_ else gsub("[Oo]", "0", static_water_level_raw)
  ))

  # Perforation / slotted interval -- "From <n> ... To <n>" within a
  # short window after the word "perforation".
  perf_block <- str_match(full_text, "(?is)perforation.{0,150}?From\\s*[:=_]?\\s*(\\d+)[^0-9]{1,15}?[Tt]o\\s*[:=_]?\\s*(\\d+)")
  slot_from_ft <- suppressWarnings(as.numeric(perf_block[1, 2]))
  slot_to_ft   <- suppressWarnings(as.numeric(perf_block[1, 3]))

  # Completion date
  completion_date_raw <- extract1("(?i)Date\\s*co[a-z]*ed[:=_.\\s]{0,10}([A-Za-z0-9,./ ]{4,20})")

  # ------------------------------------------------------------
  # BEST-EFFORT lithology interval extraction (UNVALIDATED -- see
  # module docstring). Looks for lines ending in a "<from> <to>"
  # numeric pair (allowing an optional foot-mark after each), and
  # takes everything before the numbers as the description. Skipped
  # entirely (0 rows) rather than guessed when no such lines are
  # found.
  # ------------------------------------------------------------
  lith_lines <- strsplit(full_text, "\n")[[1]]
  lith_matches <- str_match(lith_lines, "^(.{3,60}?)\\s+(\\d{1,4})\\s*['\u2018\u2019]?\\s+(\\d{1,4})\\s*['\u2018\u2019]?\\s*$")
  lith_df <- data.frame(
    description = trimws(lith_matches[, 2]),
    depth_from_ft = suppressWarnings(as.numeric(lith_matches[, 3])),
    depth_to_ft = suppressWarnings(as.numeric(lith_matches[, 4])),
    stringsAsFactors = FALSE
  )
  lith_df <- lith_df[!is.na(lith_df$depth_from_ft) & !is.na(lith_df$depth_to_ft) &
                       lith_df$depth_to_ft > lith_df$depth_from_ft &
                       nchar(lith_df$description) >= 3, ]
  row.names(lith_df) <- NULL

  if (is.na(well_name)) flags <- c(flags, "well_name not confidently extracted -- check manually")
  if (nrow(lith_df) > 0) flags <- c(flags, paste0(nrow(lith_df), " candidate lithology interval(s) extracted -- UNVALIDATED, review before trusting"))

  result <- data.frame(
    source_file = basename(path),
    source_method = source_method,
    well_name = well_name,
    county = county,
    section = section_raw,
    township_no = township_no_raw,
    township_dir = township_dir_raw,
    range_no = range_no_raw,
    range_dir = range_dir_raw,
    work_type = work_type,
    proposed_use = proposed_use,
    hole_diameter_in = hole_diameter_in,
    casing_diameter_in = casing_diameter_in,
    latitude = latitude,
    longitude = longitude,
    latlon_method = latlon_method,
    depth_drilled_ft = depth_drilled_ft,
    cased_depth_ft = cased_depth_ft,
    static_water_level_ft = static_water_level_ft,
    slot_from_ft = slot_from_ft,
    slot_to_ft = slot_to_ft,
    completion_date_raw = completion_date_raw,
    lithology_raw_text = full_text,
    flags = if (length(flags) == 0) NA_character_ else paste(flags, collapse = " | "),
    stringsAsFactors = FALSE
  )
  attr(result, "lithology_intervals") <- lith_df
  result
}
