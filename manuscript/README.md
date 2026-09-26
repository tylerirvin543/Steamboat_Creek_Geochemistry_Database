# manuscript/

The **scientific write-up**, distinct from `notebooks/` (which stays
living, code-paired database/pipeline documentation). This folder is
aimed at eventually becoming real thesis chapters or an article draft --
prose-first, figure-forward, with proper citations via `references.bib`
(Quarto/pandoc `[@key]` syntax + citeproc), not a notebook walkthrough.

## Structure

| File | Status |
|---|---|
| `01_introduction.qmd` | Stub -- not yet drafted |
| `02_geochemical_background.qmd` | **Drafted** -- chemistry/PHREEQC/statistics background and methods, with real citations |
| `03_methods.qmd` | Partial draft (sampling design section complete, field/lab methods still stub) |
| `04_results.qmd` | Partial draft (real-findings inventory as a checklist; not yet written as manuscript prose/figures) |
| `05_discussion_and_future_work.qmd` | Stub -- not yet drafted |
| `06_calibration_sampling_proposal.qmd` | **Drafted** -- a decision-facing mini-proposal (n needed, analyte/isotope pairing, fissure/SBW site cost-benefit, tiered 20/40/60+ sample-count recommendation), kept separate from `notebooks/09`'s raw statistics per explicit request |
| `references.bib` | Starter set of ~15 core citations (Sorey, Dhakal, Klein, Collar & Huntley, Mariner & Janik, White, Giggenbach, Fournier, D'Amore & Panichi, PHREEQC, Akerley). Extend as needed -- see `docs/literature/annotated_bibliography.qmd` for the full 39-document reading-notes bibliography this can draw from. |

## Rendering

```r
quarto::quarto_render("manuscript")                          # everything
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

## Honest status (2026-09-26)

Built this session: the project skeleton, `references.bib`, and Chapter 2
(geochemical background) drafted in full. Chapters 1, 5 are stubs;
Chapters 3-4 are partial. Full narrative prose for the remaining chapters
is real, ongoing work -- not something finished in one session -- and is
tracked as such rather than silently left incomplete.
