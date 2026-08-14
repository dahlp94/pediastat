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
- Interpretive consequence: none for the frozen estimands. The collapse affects only the auxiliary imputation model.

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
