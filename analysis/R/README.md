# R Statistical Analysis

R is the primary language for descriptive and inferential analysis after
the Python/PostgreSQL cohort is frozen.

## Environment

Create the environment from the repository root:

```bash
conda env create -f analysis/R/environment.yml
conda activate pediastat-r
```

The environment name is `pediastat-r`. Packages: DBI, RPostgres, dplyr,
tidyr, ggplot2, survival, gtsummary, gt, broom, here, scales, yaml,
jsonlite, testthat, renv, mice, nnet, knitr, rmarkdown, and Quarto.

`make` uses `$HOME/miniconda3/envs/pediastat-r/bin/Rscript` when that file
exists, and the Quarto binary beside it when `quarto --version` prints a
version. Otherwise it uses `Rscript` and the first `quarto` on `PATH` that
prints a version. `QUARTO_R` is the `R` executable next to that `Rscript`
(or `R` on `PATH` when no neighboring `R` exists). Activate `pediastat-r`,
or pass `RSCRIPT` and `QUARTO`, when the environment is installed somewhere
else. `QUARTO_DART_SASS`, if already set, is inherited by Quarto. Official
Quarto on Intel macOS 13 can need that variable for a compatible Sass
executable. It is not required on other systems, and no home-directory path
is built in.

`mice` is used in inferential multiple imputation. It is not called in
the descriptive analysis or model preflight.

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

Descriptive analysis reads `analytics.primary_cohort_extract`. It does not
reimplement identity, age eligibility, event, or censoring rules, fit Cox
models, or compare predictors with survival.

`render_descriptive_report.R` writes an abbreviated
`reports/descriptive_analysis.html` from aggregate artifacts when Quarto is
unavailable or Quarto rendering fails. That HTML is not the complete Quarto
scientific report. The investigator narrative source remains
`reports/descriptive_analysis.qmd`.

From the repository root, run the descriptive analysis and render the report:

```bash
make descriptive
```

`make descriptive` checks the Python environment, runs
`analysis/R/run_descriptive.R` against the frozen cohort in PostgreSQL, and
then renders `reports/descriptive_analysis.html` through
`analysis/R/render_quarto_or_fallback.sh`. That script attempts the `QUARTO`
executable. If that command fails, or Quarto cannot be run, it uses
`analysis/R/render_descriptive_report.R` and states that the HTML is an
abbreviated substitute. A failure in `run_descriptive.R` stops the target
before that fallback. If both Quarto and the fallback fail, make exits with
an error.

To run only the descriptive script, without rendering the report:

```bash
conda run -n pediastat-r Rscript analysis/R/run_descriptive.R
```

That command also needs the cohort database. Rendering HTML from aggregate
artifacts already on disk is separate; see the root `README.md`.

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

`make inference` renders the Quarto report once after the analysis script.
`run_inference.R` skips its own Quarto call on that path
(`INFERENCE_DEFER_REPORT_RENDER=1`). A direct
`Rscript analysis/R/run_inference.R` still attempts Quarto and, on failure,
writes the abbreviated substitute with `render_inference_report.R`. That
substitute is not the complete Quarto report. Its source remains
`reports/inferential_analysis.qmd`.

Person-level imputations, residuals, and dfbeta files under
`data/interim/inference/` are gitignored. Aggregate tables and figures are
written to `artifacts/inference/`.

## MICE cache reuse

Cache reuse is opt-in. `make inference` runs `mice()` unless
`INFERENCE_REUSE_MIDS=1` is set in the process environment. That setting
loads `data/interim/inference/mice_mids.rds` instead of starting MICE.
A normal inference run writes that file; it is gitignored.

Before reuse, the saved object is validated against the current imputation
data, patient identity, imputation configuration (methods, predictor matrix,
number of imputations, and seed), and iteration settings. If
`INFERENCE_REUSE_MIDS=1` and the file is missing or fails those checks,
inference stops with an error and does not start MICE. Run inference
without `INFERENCE_REUSE_MIDS=1` to create a new imputation and replace
the cache.

## 20-versus-100 iteration sensitivity

The 20-iteration MICE analysis remains primary. The 100-iteration
continuation is an optional post-analysis diagnostic and is not part of
`make inference`. With the saved 20- and 100-iteration objects in
`data/interim/inference/`:

```bash
Rscript analysis/R/run_mice_iteration_sensitivity.R
```

That command does not rerun MICE. It writes aggregate Cox estimates to
`artifacts/inference/mi_20_vs_100_cox_comparison.csv`. Reproduction details
are in `docs/analysis_deviations.md`.
