# Reports

Investigator-facing Quarto reports for the completed analysis.

Descriptive analysis:

- Source: `reports/descriptive_analysis.qmd`
- Rendered HTML is gitignored (`reports/**/*.html`)

Render after `make descriptive` has written aggregate artifacts, or as
part of that target. If Quarto is unavailable or rendering fails,
`analysis/R/render_descriptive_report.R` writes an abbreviated HTML
substitute. It is not the complete Quarto report.

The descriptive report describes the locked primary cohort and overall
survival. It does not contain Cox models or predictor-stratified
Kaplan–Meier curves. Inferential rules are in
`docs/inferential_model_specification.md`.

Inferential analysis:

- Source: `reports/inferential_analysis.qmd`
- Rendered HTML is gitignored (`reports/**/*.html`)
- Aggregate model output: `artifacts/inference/`

Render after `make inference`, or as part of that target.
`analysis/R/render_inference_report.R` writes an abbreviated HTML
substitute from aggregate artifacts when Quarto is unavailable or
rendering fails. It is not equivalent to the complete Quarto report.
The source remains `reports/inferential_analysis.qmd`.
