# Analysis deviations

Status: recorded during inferential execution of the frozen model specification.

Companion: `docs/inferential_model_specification.md`, `config/model_spec.yaml`, `docs/statistical_analysis_plan.md`.

---

## Implementation choice that does not change estimands

**Auxiliary race coding for MICE (decision made before viewing Cox results).**

- Original plan: include race as an auxiliary imputation predictor “where coding permits.”
- Issue: source OMB race cells include Native Hawaiian / Other Pacific Islander (n = 8) and American Indian / Alaska Native (n = 13). Polytomous regression with those cells is unstable.
- Change: for the imputation model only, race was collapsed to White / Black or African American / Asian / Other. Unknown / not reported remained missing.
- Race is **not** a predictor in either principal Cox model.
- Interpretive consequence: the frozen estimands and principal-model covariates were unchanged. Because race was an auxiliary imputation predictor, this recoding could affect imputed values and numerical estimates.

---

## Model-specification deviations

No deviations from the frozen principal models, missing-data methods (`m = 30`, seed `20260814`, PMM / polyreg / logreg), FDR family, reference categories, or cohort rules occurred.

In particular:

- No stepwise selection
- No predictor was removed or added because of a p-value
- The secondary FDR family was not modified after seeing results
- Cohort eligibility was not changed
- Unresolved risk-group tokens `10` / `30` were not guessed
- Hazard ratios were pooled on the coefficient scale
- The primary models were not silently replaced by spline, complete-case, or PH-remediation fits

---

## Additional post-analysis diagnostic (not an SAP deviation)

**MICE iteration-extension sensitivity.** The primary analysis used 30 imputations and 20 iterations. After categorical chain-mean traces showed drift at iteration 20, the same 30 MICE chains were continued to iteration 100 in a separate diagnostic exercise. This did not replace or overwrite the original pooled Cox results.

Across the 15 primary- and secondary-model Cox coefficients, the maximum absolute relative hazard-ratio change was 2.38%. No coefficient changed direction, no 95% confidence interval changed its inclusion/exclusion of HR = 1, and none of the seven prespecified secondary BH decisions changed at 0.05. These findings support numerical stability with additional iterations but do not establish convergence at iteration 20 or 100, nor do they validate the Missing At Random assumption.

This post-analysis sensitivity is reported separately in the [inferential report](../reports/inferential_analysis.qmd); it is **not** a change to the frozen analysis specification.

The 20-iteration analysis remains primary. The 100-iteration continuation is a post-analysis sensitivity and is not part of `make inference`. Reproducing it writes `artifacts/inference/mi_20_vs_100_cox_comparison.csv`, an aggregate table of pooled Cox estimates. That table does not contain patient identifiers, survival times, imputations, or residuals.

From the repository root, with the `pediastat-r` environment and the saved objects below:

- `data/interim/inference/mice_mids.rds` (30 imputations, 20 iterations, seed 20260814)
- `data/interim/inference/mice_mids_100iter_diagnostic.rds`
- `data/interim/inference/coded_primary_cohort.rds`

```bash
Rscript analysis/R/run_mice_iteration_sensitivity.R
```

The default command loads those objects, refits the frozen primary and secondary Cox models, and does not call `mice()` or `mice::mice.mids()`. It does not replace `mice_mids.rds` or the primary Cox tables.

Create the extended object only when `mice_mids_100iter_diagnostic.rds` is absent:

```bash
Rscript analysis/R/run_mice_iteration_sensitivity.R --continue-missing
```

That continues the validated 20-iteration object with `mice::mice.mids(imp20, maxit = 80)` and writes only the extended file. Replacing an extended object that already exists requires `--overwrite-extended`.
