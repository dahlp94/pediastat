# R Statistical Analysis

R is the primary language for descriptive and inferential analysis after
the Python/PostgreSQL cohort is frozen.

## Descriptive scripts

```text
setup.R
descriptive.R
run_descriptive.R
tests/test_descriptive.R
```

`setup.R` provides the shared analysis setup, frozen-cohort validation,
database connection, and cohort-loading functions. `descriptive.R` contains
the baseline summaries, missingness analysis, overall Kaplan-Meier
analysis, reverse-Kaplan-Meier follow-up, provenance, and descriptive output
generation.

Descriptive analysis reads `analytics.stage4_primary_cohort_extract`. It does not
reimplement identity, age eligibility, event, or censoring rules, fit Cox
models, or compare predictors with survival.

`render_descriptive_report.R` writes `reports/descriptive_analysis.html` from
aggregate artifacts when a complete Quarto CLI is not available. The
investigator narrative source remains `reports/descriptive_analysis.qmd`.

## Model-preflight scripts

```text
model_setup.R
run_model_preflight.R
tests/test_model_preflight.R
```

These scripts construct planned analysis variables (`age5`, `log2_wbc`,
standardized categories), check design-matrix rank, and write aggregate
planning artifacts. They do not call `coxph()` or `mice()`.

```bash
make model-plan
```

## Inference scripts

```text
model_setup.R
imputation.R
models.R
diagnostics.R
render_inference_report.R
run_inference.R
tests/test_inference.R
```

These scripts reuse model-preflight coding and checks. They do not rebuild
cohort eligibility. Complete-case sensitivity uses the same formulas as
the multiply imputed fits (`models.R`). `diagnostics.R` contains the
prespecified nonlinear sensitivity, PH diagnostics and remediation,
influence diagnostics, stratified Kaplan-Meier displays, and inference
aggregate-output generation.

```bash
make inference
```

Person-level imputations, residuals, and dfbeta files under
`data/interim/stage6/` are gitignored. Aggregate tables and figures are
written to `artifacts/inference/`.

## Environment

Run from the repository root:

```bash
make descriptive
```

or

```bash
conda run -n pediastat-r Rscript analysis/R/run_descriptive.R
```

## Environment

Preferred local environment:

```bash
conda env create -f analysis/R/environment.yml
conda activate pediastat-r
```

Packages: DBI, RPostgres, dplyr, tidyr, ggplot2, survival, gtsummary, gt,
broom, here, scales, yaml, jsonlite, testthat, renv, mice, nnet.

`mice` is used in inferential multiple imputation. It is not called in
the descriptive analysis or model preflight.
