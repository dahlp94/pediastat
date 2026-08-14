# R Statistical Analysis

R is the primary language for descriptive and inferential analysis after
the Python/PostgreSQL cohort is frozen.

## Stage 4 scripts

```text
00_setup.R
01_load_primary_cohort.R
02_baseline_descriptives.R
03_missingness.R
04_overall_survival.R
05_followup.R
06_generate_descriptive_outputs.R
run_stage4.R
```

These scripts read `analytics.stage4_primary_cohort_extract`. They do not
reimplement identity, age eligibility, event, or censoring rules. They do
not fit Cox models or compare predictors with survival.

`07_render_report.R` writes `reports/stage4_descriptive_analysis.html` from
aggregate artifacts when a complete Quarto CLI is not available. The
investigator narrative source remains `reports/stage4_descriptive_analysis.qmd`.

## Stage 5 scripts

```text
10_model_coding.R
11_preflight.R
run_stage5.R
tests/test_stage5.R
```

These scripts construct planned analysis variables (`age5`, `log2_wbc`,
standardized categories), check design-matrix rank, and write aggregate
planning artifacts. They do not call `coxph()` or `mice()`.

```bash
make model-plan
```

## Stage 6 scripts

```text
20_prepare_inferential_data.R
21_mi_specification.R
22_run_multiple_imputation.R
23_fit_cox_models.R
25_nonlinear_sensitivity.R
26_ph_diagnostics.R
27_influence_diagnostics.R
28_stratified_km.R
29_generate_model_outputs.R
30_render_stage6_report.R
run_stage6.R
tests/test_stage6.R
```

These scripts reuse Stage 5 coding and preflight. They do not rebuild
cohort eligibility. Complete-case sensitivity uses the same formulas as
the multiply imputed fits (`23_fit_cox_models.R`).

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
conda run -n pediastat-r Rscript analysis/R/run_stage4.R
```

## Environment

Preferred local environment:

```bash
conda env create -f analysis/R/environment.yml
conda activate pediastat-r
```

Packages: DBI, RPostgres, dplyr, tidyr, ggplot2, survival, gtsummary, gt,
broom, here, scales, yaml, jsonlite, testthat, renv, mice, nnet.

`mice` is used in Stage 6 multiple imputation. It is not called in
Stage 4 or Stage 5.
