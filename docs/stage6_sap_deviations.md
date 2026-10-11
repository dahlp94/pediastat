# Stage 6 SAP deviations

Status: recorded during Stage 6 execution of the frozen Stage 5 inferential specification.

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

No deviations from the frozen Stage 5 principal models, missing-data methods (`m = 30`, seed `20260814`, PMM / polyreg / logreg), FDR family, reference categories, or cohort rules occurred.

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

This post-analysis sensitivity is reported separately in the [inferential report](../reports/stage6_inferential_analysis.qmd); it is **not** a change to the frozen analysis specification.
