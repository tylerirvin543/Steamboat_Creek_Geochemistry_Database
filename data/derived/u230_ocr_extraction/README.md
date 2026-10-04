# OCR extraction of remaining NDEP compiled U230 pages (55-138)

Automated (tesseract OCR, targeted field crops) extraction of the
remaining 42 facility/sampling page-pairs in
`data/raw/ndep/PRR/PPR_05_26_2026/NDEP_compiled_U230_Steamboat_reports.pdf`
(pages 55-138), continuing from where manual transcription left off
at page 55 (2026-09-30 session).

## Method

Each page is rendered at 400 dpi, then specific field regions are
cropped (based on this form's fixed printed template), upscaled, and
OCR'd individually with `tesseract`, rather than OCR'ing the whole
page at once -- whole-page OCR was tried first and silently dropped
several handwritten rows entirely (confirmed directly: a full-page OCR
pass on page 56 dropped the pH line that a targeted crop of the same
region read correctly). This is a substantially better yield than the
whole-page OCR attempted in earlier sessions (which is why manual
transcription was the standing approach until now), but it is **not**
perfectly reliable, especially for the handwritten numeric fields.

## Known limitations -- read before using this data

- **pH is the least reliable field.** In many rows the OCR engine
  dropped the pH line from the field-measurements crop entirely (even
  though it's legible to a human eye); a secondary, more aggressive
  crop+recovery pass recovered about half of the ~36 initially-missing
  values. **Several recovered pH values start with "1." (e.g. 1.33,
  1.31, 1.21) -- these are almost certainly a "7" misread as "1"** by
  the OCR engine (a pH of ~1.3 is chemically implausible for every one
  of these sites; visually confirmed on at least one page that the
  true digit is a 7). These rows are flagged in the `pH_flag` column.
  **Do not use any pH value from this file without checking the
  original scanned image first.**
- **Temperature and conductivity are read more reliably but still have
  occasional digit-transposition/drop errors** (confirmed directly on
  one page: OCR read "32 6°C" from an image that visually reads
  "33.6°C"). The `raw_field_meas` column preserves the full raw OCR
  text for every row so you can sanity-check the parsed value against
  it, but a genuine misread in the raw text itself won't show up that
  way -- if a conductivity/temperature value looks physically
  implausible relative to that location's other readings this session,
  assume it's a misread and check the original PDF page.
- **`sample_time_clean` strips leading OCR noise** (often a stray "1"
  or "4" from a nearby checkbox border) but is not independently
  verified.
- **Conductivity values follow this session's established
  "X.XXXus" -> value-in-uS/cm-times-1000 convention is NOT applied
  here** -- the `conductivity` column is the literal OCR'd number
  (already often in the 300-9900+ range without needing that
  multiplication, unlike the earlier hand-transcribed samples). Check
  the `raw_field_meas` text for the exact "us"-suffixed string before
  assuming units.
- Well/location names, dates, and locations-sample-taken text are
  generally accurate (these are typed/stamped or written in large,
  clean block print) but still worth a quick visual scan -- a few rows
  have `NA` where OCR genuinely failed to find the field at all.
- Rows are ordered by page number, which corresponds to chronological
  sampling rounds visible in `sample_date` (10/29/25, 10/24/25,
  11/25/25, 11/21/25, 12/10/25, 12/12/25 -- six rounds of the same
  ~13-14 site sequence: five plant outlets [Galena 1/2/3, SB2, SB3,
  SBHR] followed by Soccer Field, Herz Dom, Herz Deep, Eich, NDOT, Boyd
  Domestic, Jeppson Domestic, Rogers Domestic).

## Recommended workflow

1. Open `u230_pages_55_138_extracted.csv` in a spreadsheet.
2. Scan `pH_flag` first -- fix any flagged "1.xx" values by opening
   the corresponding page number in the source PDF.
3. Spot-check `temperature`/`conductivity` against `raw_field_meas`
   and against this location's other readings this session for
   plausibility.
4. Once satisfied a row is correct, it can be inserted into the
   database the same way every other 2025 U230 sample this session
   was (new Sampling_Events/Samples/Field_Measurements rows, following
   the pattern already documented in AGENTS.md's Session 42
   addenda) -- this has NOT been done automatically for any of these
   42 rows; the CSV is a review draft only.
