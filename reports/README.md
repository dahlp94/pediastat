# Reports

Investigator-facing Quarto reports.

Stage 4:

- Source: `reports/stage4_descriptive_analysis.qmd`
- Rendered HTML is gitignored (`reports/**/*.html`)

Render after `make descriptive` has written aggregate artifacts, or as
part of that target when Quarto is available.

The Stage 4 report describes the locked primary cohort and overall
survival. It does not contain Cox models or predictor-stratified
Kaplan–Meier curves.
