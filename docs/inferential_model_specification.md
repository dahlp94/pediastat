# Inferential Model Specification

Stage: 5 — freeze inferential models, coding, missing-data strategy, and diagnostics  
Status: locked before any Cox fit or multiple imputation  
Companion: `config/model_spec.yaml`, `docs/statistical_analysis_plan.md`, `artifacts/model_plan/`

This document is the collaborator-facing lock of Stage 5. It does not contain hazard ratios, p-values, or predictor-specific survival results. Stage 6 will execute the plan.

Language throughout is prognostic association, not causal effect.

---

## 1. Scientific Objective

Among children and adolescents with AML in the frozen public TARGET-AML primary OS cohort (N = 1978; 695 deaths; 1283 censored), estimate associations between prespecified baseline characteristics and the hazard of all-cause death after diagnosis.

Causal effects, treatment effects, and language such as “causes,” “reduces mortality,” or “improves survival” are not claimed.

## 2. Statistical Estimand

Principal estimands are **adjusted hazard ratios** from Cox proportional-hazards regression for all-cause death, with time origin at initial pathologic diagnosis.

Time scale: `os_days`. Event: `os_event` (Dead = 1, Alive = 0), already locked in Stage 3.

Tied event times: Efron approximation.

Inference: ordinary Cox partial likelihood, pooled across imputations with Rubin’s rules on the **coefficient** scale.

Two related but distinct questions are answered by two models:

- **Model A (primary clinical):** protocol risk classification plus age, sex, and WBC.
- **Model B (secondary molecular/cytogenetic):** granular mutation and lesion indicators plus age, sex, and WBC, **without** protocol risk group.

Risk group is defined from cytogenetics and biomarkers. Putting risk group in the same principal model as FLT3/ITD and lesion flags would double-count overlapping clinical information. That separation is a design decision, not the result of survival screening.

## 3. Primary Clinical Cox Model

```text
coxph(
  Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std,
  ties = "efron"
)
```

Planned degrees of freedom: **5** (age 1 + sex 1 + WBC 1 + risk group 2).

Inferential emphasis: **risk group** and **WBC**. Age and sex are estimated and interpreted, but they also serve as adjustment variables.

No interaction terms.

## 4. Secondary Molecular/Cytogenetic Cox Model

```text
coxph(
  Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc +
    flt3_itd_std + npm_std + cebpa_std +
    cytogenetics_t821_std + cytogenetics_inv16_std +
    cytogenetics_mll_std + cytogenetics_monosomy7_std,
  ties = "efron"
)
```

Planned degrees of freedom: **10**.

Risk group is absent. Primary cytogenetic code is absent. Lesion flags are retained as separate CDE-defined baseline indicators; they are not collapsed into a composite karyotype.

Each included lesion/mutation field was verified as:

- a diagnostic/baseline CDE concept
- Yes/No coding after mixed-case harmonization
- sufficiently populated to appear as a dummy variable
- not a structural duplicate that would make the dummy design singular

Monosomy 7 is uncommon (38 Yes in the primary cohort) but is a CDE-defined baseline adverse lesion and is retained. Four persons have two lesion flags coded Yes; t(8;21) and inv(16) do not co-occur as Yes. That pattern does not create a structurally invalid design matrix.

## 5. Covariate Definitions

| Analysis variable | Source concept | Coding for inference |
| --- | --- | --- |
| `age5` | GDC age at diagnosis (years = days/365.25) | years / 5 |
| `sex_std` | GDC sex at birth | Female, Male |
| `log2_wbc` | Supplement WBC at diagnosis (×10³/mcL) | log2 of strictly positive observed WBC |
| `risk_group_std` | Supplement Risk group | Low, Standard, High |
| `flt3_itd_std` | FLT3/ITD positive? | Yes / No |
| `npm_std` | NPM mutation | Yes / No |
| `cebpa_std` | CEBPA mutation | Yes / No |
| `cytogenetics_t821_std` | t(8;21) | Yes / No |
| `cytogenetics_inv16_std` | inv(16) | Yes / No |
| `cytogenetics_mll_std` | MLL (KMT2A rearrangement) | Yes / No |
| `cytogenetics_monosomy7_std` | monosomy 7 | Yes / No |

Source precedence remains the Stage 3 rules. Stage 5 does not rebuild the cohort.

### Risk-group tokens `10` and `30`

CDE permissible values for Risk group are **High Risk, Low Risk, Standard Risk** only.

The three primary-cohort rows coded `10` (n=2) or `30` (n=1) come solely from `TARGET_AML_ClinicalData_Validation_20230720.xlsx`. No overlapping supplement supplies a CDE label. There is no documented mapping.

**Decision:** original tokens are retained for QA; the inferential standardized value is **missing**; QA flag `unresolved_risk_group_token`. Numeric order was not used to guess Low/Standard/High.

### Mixed-case Yes/NO

Source `YES`/`NO` tokens are treated as the same clinical meaning as `Yes`/`No`. This is display/coding harmonization, not recategorization of distinct biology.

## 6. Functional Forms

Primary model:

- Age: linear in `age5` (HR per 5 years). Not categorized.
- WBC: linear in `log2_wbc` (HR per doubling). Chosen from the Stage 4 right-skewed, strictly positive distribution, **not** from association with OS.
- Extreme WBC values are not winsorized unless a source-data error is demonstrated.

Nonlinear **sensitivity** (not primary):

- Restricted cubic spline of `age_at_diagnosis_years` with 3 knots at the Stage 4 observed 10th, 50th, and 90th percentiles: 1.1417, 9.4839, 16.5656 years.
- Restricted cubic spline of `log2_wbc` with 3 knots corresponding to the Stage 4 observed WBC 10th, 50th, and 90th percentiles: 3.87, 26.7, 192.69 ×10³/mcL.

Knots are frozen from Stage 4 covariate quantiles. AIC, p-values, and survival association are not used to move knots or to replace the primary linear/log2 forms.

## 7. Reference Categories

| Variable | Reference | Reported comparison |
| --- | --- | --- |
| `sex_std` | Female | Male vs Female |
| `risk_group_std` | Low | Standard vs Low; High vs Low |
| Binary molecular/lesion flags | No | Yes vs No |

Unknown is not a reference level in either inferential model.

## 8. Missing-Data Strategy

Cohort membership remains independent of covariate completeness.

For inferential modeling, the following are **missing covariate information**, not biological categories:

- Unknown / Not Reported / Unspecified
- structurally missing
- unresolved tokens (`10`, `30`)
- lesion tokens Not Done / Not Applicable

Observed No/Negative remains observed. Observed WBC of 0 would remain observed (none in Stage 4). Only unobserved WBC is missing.

**Primary missing-data method:** multiple imputation.  
**Sensitivity:** complete-case Cox model with the same formulas, coding, and references.

Complete case is not primary merely because missingness is modest.

## 9. Multiple-Imputation Specification

Software: `mice`. Number of imputations: **m = 30**. Seed: **20260814**.

Do **not** impute: `analysis_person_id`, `os_event`, `os_days`/`os_years`, `age_at_diagnosis_years`/`age5`, `sex_std`.

Planned methods:

| Variable | mice method |
| --- | --- |
| `log2_wbc` | predictive mean matching (`pmm`) |
| `risk_group_std` | polytomous regression (`polyreg`) |
| FLT3, NPM, CEBPA, lesion flags | logistic (`logreg`) |

Impute `log2_wbc` rather than raw WBC.

The imputation model includes survival information **without imputing the outcome**:

- `os_event`
- Nelson–Aalen cumulative hazard at each person’s observed OS time, from the nonparametric Fleming–Harrington estimator, **not** from a Cox prognostic model

Rationale: imputation should preserve covariate–outcome relationships. Stage 4 missingness summaries do not prove MAR.

Auxiliary candidates: age, sex, WBC, risk group, molecular flags, lesion flags, marrow blasts, peripheral blasts, CNS (Yes/No; Unknown missing), race/ethnicity where coding permits, AML1031 source indicator, `os_event`, Nelson–Aalen cumulative hazard.

Forbidden auxiliaries without temporal justification: SCT in first CR, post-treatment MRD, gemtuzumab, treatment response, first-event outcomes.

Stage 6 diagnostics: iteration traces, observed vs imputed distributions, categorical frequency plausibility, impossible values, between-imputation variability. Strategy is not chosen to make hazard ratios more favorable.

Pooling: Rubin’s rules on coefficients; then exponentiate the pooled log HR. Do not average HRs across imputations.

## 10. Complete-Case Sensitivity Analysis

Same predictors, functional forms, and reference groups as the corresponding MI analysis. Rows with missing model covariates are omitted from that fit only. The frozen cohort table is not rewritten.

Purpose: robustness to missing-data handling, not a search for significance.

## 11. Nonlinear Sensitivity Analyses

See Section 6. Spline models are sensitivity checks for functional-form adequacy. A statistically significant spline does not silently replace the primary linear/log2 specification.

## 12. Proportional-Hazards Diagnostics

After Stage 6 fitting, assess PH with scaled Schoenfeld residuals, covariate-specific tests, a global test, and plots (`cox.zph` or equivalent).

A p-value alone is not proof of a material violation. Interpret test result, residual pattern, and practical importance together.

## 13. PH Remediation Rules

Defined before seeing diagnostics:

**Case A — minor / clinically unimportant departure.** Retain Cox. Report the finding. Interpret the HR as an average relative hazard over follow-up.

**Case B — material violation in a nuisance adjustment variable.** Consider stratified Cox if scientifically sensible. Do not report an HR for a stratified factor.

**Case C — material violation in a scientifically important predictor.** Fit a prespecified extended Cox sensitivity with a log(time) interaction. Do not search arbitrary cutpoints. Do not silently replace the primary model.

## 14. Influence Diagnostics

Deviance residuals, martingale residuals where useful, dfbeta, and concordance as **descriptive** performance.

Influential observations are not deleted automatically. Exclusion requires a data error or a prespecified eligibility rule, not influence alone.

## 15. Multiplicity

**Primary clinical model.** Small prespecified coefficient set. Report adjusted HR, 95% CI, and nominal two-sided p-values. No automated multiplicity correction. Do not reduce results to “significant / nonsignificant.”

**Secondary molecular model.** Report HR, 95% CI, and nominal p. For the frozen secondary biological family, also report Benjamini–Hochberg q-values:

- `flt3_itd_std`
- `npm_std`
- `cebpa_std`
- `cytogenetics_t821_std`
- `cytogenetics_inv16_std`
- `cytogenetics_mll_std`
- `cytogenetics_monosomy7_std`

FDR is **not** applied to age, sex, or WBC in the secondary model.

## 16. Interaction Policy

Primary and secondary models contain **no interaction terms**. All-pairwise interaction searches are not performed. A future interaction must be labeled exploratory and recorded as an SAP deviation or extension.

## 17. Predictor-Stratified KM Policy

Stage 6 may produce unadjusted KM curves for **risk group** and **FLT3/ITD** only. These are descriptive. They are not used for variable selection. Log-rank tests are not required; if shown, they are unadjusted and secondary. No large battery of stratified KM plots.

## 18. Interpretation Rules

- Report associations, not effects of intervening on a covariate.
- Preferred wording: associated with; adjusted hazard ratio; prognostic association; higher/lower observed hazard.
- Primary emphasis: risk group and WBC.
- Uncertainty (CI) is part of the result, not an afterthought.

## 19. Deviations From This Plan

None at lock. Any later change after inspecting survival associations must be dated, described, and justified here and in `docs/statistical_analysis_plan.md`.

## 20. Variables Deliberately Excluded From Both Principal Models

| Variable | Reason (not survival association) |
| --- | --- |
| FAB | ~56% not observed; file-dependent completeness |
| Primary cytogenetic code | NEEDS REVIEW; source conflicts; redundancy with lesion flags |
| Race, ethnicity | Not automatic biological risk factors; reserved for a separately framed analysis |
| CNS disease, marrow blasts, peripheral blasts | Parsimony and redundancy; optional labeled expanded sensitivity later |
| Protocol, MRD, SCT, gemtuzumab, first event | Not ordinary baseline covariates (already Stage 3) |

## 21. Events-Per-Parameter Descriptor

Deaths = 695.

- Primary clinical: 695 / 5 = **139** events per model df
- Secondary molecular: 695 / 10 = **69.5** events per model df

This is not a formal power calculation. Neither model is obviously overparameterized. Predictors are not dropped by an events-per-variable rule.
