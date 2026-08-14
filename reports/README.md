# Reports

Investigator-facing Quarto reports.

Stage 4:

- Source: `reports/stage4_descriptive_analysis.qmd`
- Rendered HTML is gitignored (`reports/**/*.html`)

Render after `make descriptive` has written aggregate artifacts, or as
part of that target when Quarto is available.

The Stage 4 report describes the locked primary cohort and overall
survival. It does not contain Cox models or predictor-stratified
Kaplan–Meier curves. Inferential rules are in
`docs/inferential_model_specification.md`.

Stage 6:

- Source: `reports/stage6_inferential_analysis.qmd`
- Rendered HTML is gitignored (`reports/**/*.html`)
- Aggregate model output: `artifacts/inference/`

Render after `make inference`, or as part of that target when Quarto is
available. `analysis/R/30_render_stage6_report.R` writes HTML from
aggregate artifacts when a complete Quarto CLI is not available.
