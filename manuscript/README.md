# manuscript/

The **scientific write-up**, distinct from `notebooks/` (which stays
living, code-paired database/pipeline documentation). This folder is
aimed at eventually becoming real thesis chapters or an article draft --
prose-first, figure-forward, with proper citations via `references.bib`
(Quarto/pandoc `[@key]` syntax + citeproc), not a notebook walkthrough.

## Structure

| File | Status |
|---|---|
| `00_thesis_proposal.qmd` | **Master document** -- title page, abstract, and the full proposal text in one standalone ~40-page file (HTML/PDF/Word). Note: unlike `notebooks/00_full_report.qmd`, this is **not** a literal `{{< include >}}` of `01`-`06` -- it's an independently-written, condensed version kept in sync with the chapter files by hand. Renders to HTML, PDF, and `.docx`. |
| `01_introduction.qmd` | **Drafted** -- study area/setting, a chronological table + timeline figure of Steamboat Hills events (1950-2026), the chloride-tracer/conductivity-proxy motivation, and the three thesis questions. |
| `02_geochemical_background.qmd` | **Drafted** -- chemistry/PHREEQC/statistics background and methods, with real citations, plus a "related literature" subsection summarizing reservoir-engineering/structural/regional-analog sources. |
| `03_methods.qmd` | **Drafted** -- database architecture/data sources/QA-QC, field methods (spring remapping, temperature/conductivity loggers), a condensed sampling plan, statistical/PHREEQC methods, and a hydrologic/Leapfrog/fault modeling-directions subsection. |
| `04_results.qmd` | **Drafted** -- real findings as flowing prose with figures: a live discharge estimate, the Cl/B ratio stability test, geothermometer divergence, hydrochemical facies clustering, and the sampling-frequency Monte Carlo result, closing with an explicit "what these results do not yet show" section. |
| `05_discussion_and_future_work.qmd` | **Drafted** -- revisits the three thesis questions, restates the chemistry-first modeling principle, and lays out the three sequenced roadblocks (real paired Cl/EC samples, in-field water levels, digitized faults) and what resolving each would make possible. |
| `06_calibration_sampling_proposal.qmd` | **Drafted** -- a decision-facing mini-proposal (n needed, analyte/isotope pairing, fissure/SBW site cost-benefit, tiered 20/40/60+ sample-count recommendation), kept separate from `notebooks/09`'s raw statistics per explicit request. |
| `gsa.csl` | Geological Society of America ("References Cited") citation style, fetched from the public Zotero/CSL style repository. UNR's own Geology graduate handbook says to follow "the guidelines of a refereed journal in your field for headings, citations ... and references cited" -- GSA style is that convention for this field, and matches both attached example UNR Geology (Faulds-advised) thesis proposals. Applied project-wide via `_quarto.yml`'s `csl:` key. |
| `references.bib` | Expanded to ~35 real citations (Sorey, Dhakal, Klein, Collar & Huntley, Mariner & Janik, Skalbeck, White/Thompson/Silberman, Lindsey et al. 2026, McCleskey et al., Giggenbach, Fournier, D'Amore & Panichi, PHREEQC, Akerley, Bjornsson, Combs & Goranson, Arehart, Johnson & Hulen, Cohen & Loeltz, Newman, Janik et al. -- the last two explicitly flagged as different-system methodological analogs). Drawn from `docs/literature/annotated_bibliography.qmd`'s 48-document reading-notes bibliography; extend further as needed. |

## Rendering

```r
quarto::quarto_render("manuscript/00_thesis_proposal.qmd")         # the full ~40-page proposal
quarto::quarto_render("manuscript/02_geochemical_background.qmd")  # one chapter
```

Renders to `output/reports/manuscript/` (HTML and PDF, same TinyTeX/
LuaLaTeX toolchain already used for `notebooks/00_full_report.qmd`).

## Relationship to other documents

- `notebooks/` -- database/pipeline documentation, stays separate.
- `docs/literature/annotated_bibliography.qmd` -- a broader reading-notes
  document (prose links, not citation keys); a different, complementary
  document, not superseded by `references.bib`.
- `ROADMAP.md` -- the strategic project-level view this manuscript's
  Discussion chapter should synthesize into prose.
- `notebooks/09_sampling_campaign_design.qmd` -- the full, reproducible
  sampling-design analysis this manuscript's Methods chapter condenses.

## Honest status (2026-10-01)

All six chapters are now drafted in full, and a new master document
(`00_thesis_proposal.qmd`) assembles them into a single ~40-page thesis
proposal with a title page, abstract, table of contents, and a
references section generated from `references.bib`. `references.bib`
was expanded from ~15 to ~35 entries. Three figures
(`steamboat_timeline.png`, `discharge_through_time.png`,
`u230_timeseries.png`) are produced on demand via
`scripts/analysis/manuscript_figures.R`. This is a first complete
draft, not a final thesis proposal -- see Chapter 5's own "concrete
roadblocks" section for what substantive work (real paired Cl/EC
samples, in-field water levels, digitized faults) still needs to
happen before the thesis's three central questions can be fully
answered, and expect further editorial passes as that work lands.

**2026-10-01 update**: Chapter 4 gained a new section ("A real
three-month, 14-site field-parameter time series") covering the
Sept-Dec 2025 U230 field-form data (AGENTS.md Session 42's "42-row OCR
batch" addendum) -- the systematic pH gap between injection-side ports
and the shallow monitoring/domestic well network, and two concrete
real multi-month trends (Herz Deep's rising conductance, NDOT's
falling temperature). Chapter 5 gained a matching short section on
what this implies for modeling choice (reactive-transport vs.
conservative mixing framing). A new, separate talking-points document
for a groundwater-hydrology-advisor meeting,
`docs/outreach/professor_talking_points.qmd`, draws on the same data
and figure but is written for a 15-20 minute spoken conversation, not
the thesis itself.

**2026-10-04 update**: Added a real "PHREEQC workflow: sample
eligibility, databases, and interpretation" subsection to both
`00_thesis_proposal.qmd` (Methods) and `03_methods.qmd` -- covers
sample eligibility criteria, data provenance/unit handling (including
the real CaCO3-to-HCO3 alkalinity conversion and the charge-balance
bug it fixed), end-member grouping, the four-ratio conservative-tracer
check, and an honest statement of the mixing/inverse-modeling
workflow's current real limitations (one representative, not
time-paired, end-member pair; a known parser gap on the inverse-model
output). Written to cross-reference rather than repeat the
equations/database table already given in the Background chapter.
Switched citations project-wide to GSA style (`gsa.csl`, see table
above); this also surfaced and fixed a real formatting bug -- pandoc's
BibTeX reader auto-converts Title Case article titles to sentence
case, which was incorrectly lowercasing proper nouns (e.g. "steamboat
hills", "washoe county") since they weren't protected with `{braces}`
in `references.bib`; every title field was corrected.
`00_thesis_proposal.qmd` also gained a `docx` output format (alongside
html/pdf) and an accessibility pass: `lang: en` metadata, and a
`show_fig()` helper rewrite so every figure carries a short, distinct
screen-reader description (via Quarto's `fig-alt`) separate from its
longer visible caption, rather than one long string doing double duty
as both. Verified in rendered output: the HTML exposes the short
description via `aria-label` on the `<img>`, and the `.docx` exposes
it via Word's own Alt Text "Description" field (confirmed by unzipping
the `.docx` and inspecting `word/document.xml`) -- both real,
structural accessibility info, not just a plan. **What's still a
manual, outside-this-pipeline step** (per UNR's own documented
accessibility guidance at unr.edu/accessibility): LaTeX-produced PDFs
are not reliably tagged for screen readers, so the actual
submission-ready accessible PDF should be generated by opening the
`.docx` in Word and exporting to PDF with "Document structure tags for
accessibility" checked, not by using the PDF this pipeline builds
directly from LaTeX. Running Word's/Acrobat's own accessibility
checker on the final file is also a manual step I can't do from this
environment. One minor, known cosmetic artifact (not chased further):
the `.docx`'s image "Title" field (distinct from the "Description"
field that actually carries the real alt text) shows the local
absolute file path each figure was rendered from -- harmless, but
worth clearing manually in Word before final submission if you want a
fully clean file.
