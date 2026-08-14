# Statistical Analysis Plan

Version: 0.6 (Stage 6 executed the frozen Stage 5 Cox + multiple-imputation plan)
Status: population, primary endpoint, descriptive conventions, and inferential analysis rules remain locked. Stage 6 executed those rules. Changes after inspecting survival associations are SAP deviations (`docs/stage6_sap_deviations.md`).

Companion documents:

- `docs/primary_cohort_specification.md`
- `docs/baseline_covariate_source_rules.md`
- `docs/stage4_variable_definitions.md`
- `docs/stage4_analysis_extract.md`
- `docs/inferential_model_specification.md`
- `config/model_spec.yaml`
- `docs/target_aml_reconciliation_report.md`
- `artifacts/cohort_definition/`
- `artifacts/descriptive/`
- `artifacts/model_plan/`

## 1. Study Objective

Among children and adolescents with acute myeloid leukemia in public TARGET-AML data, estimate associations between prespecified baseline patient and disease characteristics and overall survival, while addressing censoring, missing data, statistical assumptions, and uncertainty.

This is an observational association study. Causal effects will not be claimed.

## 2. Scientific Hypotheses

Prespecified prognostic associations (not causal effects):

**Primary clinical model.** After adjustment for age and sex, protocol risk group and log2 WBC at diagnosis are associated with the hazard of all-cause death.

**Secondary molecular/cytogenetic model.** After adjustment for age, sex, and log2 WBC, FLT3/ITD, NPM, CEBPA, t(8;21), inv(16), MLL/KMT2A rearrangement, and monosomy 7 are associated with the hazard of all-cause death. This model does not include protocol risk group.

Variable inclusion is frozen above. It was not determined by univariable p-value screening against survival. Exploratory analyses, if added later, will be labeled as such.

## 3. Data Source

Primary public source: NCI Genomic Data Commons project **TARGET-AML** (`https://api.gdc.cancer.gov`), dbGaP accession phs000465.

Loaded sources:

- GDC Cases API entities: case, demographic, diagnosis, follow_up, treatment
- Five patient-level clinical-data workbooks, ingested separately
- CDE dictionary workbook (definitions, not patients)
- Tumor-content/RIN workbook (not used as a clinical covariate table)

Join comparison uses documented USI normalization (trim, uppercase; `join_barcode` = leading `TARGET-NN-TOKEN`). Original identifiers are retained. Analysis-person identity is the canonical six-character `TARGET-20` or `TARGET-21` USI when that structure is established.

TCGA-LAML and genomic files remain out of scope.

## 4. Study Population

The primary study population is TARGET-AML **analysis persons** (not GDC cases and not biospecimen aliquots) who:

- have an unambiguous canonical TARGET patient USI
- have a GDC diagnosis entity
- have GDC age at diagnosis
- were < 18 years of age at diagnosis
- have Alive or Dead vital status
- have a valid status-specific OS time

Age is computed as `diagnoses.age_at_diagnosis` days / 365.25. The <18 rule follows the scientific question (children and adolescents). It was not chosen to maximize N. TARGET-AML also contains young adults; they are excluded from the primary population and reserved for a prespecified age ≤21 sensitivity cohort.

## 5. Inclusion Criteria

1. TARGET-AML person with unambiguous analysis-person identity.
2. GDC diagnosis available.
3. GDC age at diagnosis available.
4. Age at diagnosis < 18 years.
5. GDC `demographic.vital_status` is Alive or Dead.
6. Valid status-specific OS time (see Primary Endpoint).

Candidate AML covariates (WBC, risk group, FLT3/ITD, NPM, CEBPA, FAB, race, ethnicity, supplement membership) are **not** inclusion criteria.

## 6. Exclusion Criteria

1. Ambiguous experimental identity (`TARGET-20-D#` and related constructs), cell-line / non-patient identifiers, or unresolved multi-case identity conflict.
2. No GDC diagnosis entity.
3. Missing age at diagnosis.
4. Age at diagnosis ≥ 18 years.
5. Vital status Unknown, Not Reported, or structurally missing. These are not coded as censored.
6. Dead without non-negative `days_to_death`.
7. Alive without non-negative `diagnoses.days_to_last_follow_up`.

Exclusions are counted in `artifacts/cohort_definition/cohort_attrition.csv` and stored person-by-person in `analytics.cohort_eligibility`.

## 7. Primary Endpoint

**Overall survival** from initial pathologic diagnosis to death from any cause.

| Element | Rule |
| --- | --- |
| Event source | GDC `demographic.vital_status` |
| Event | Dead = 1; Alive = 0 |
| Time, if Dead | `demographic.days_to_death` |
| Time, if Alive | `diagnoses.days_to_last_follow_up` |
| Units | days (years = days / 365.25 for descriptive conversion) |
| Time origin | Initial pathologic diagnosis |
| Censoring | Alive censored at diagnosis last follow-up |
| Unknown / Not Reported | Excluded from the primary OS cohort; never classified as censored |
| Supplement OS | QA / future sensitivity only; not the primary time |

Verified GDC definitions (Data Dictionary / caDSR):

- `days_to_last_follow_up` (CDE 3008273): interval from last follow-up to initial pathologic diagnosis, days.
- `days_to_death` (CDE 6154724): days from the GDC index date to death.
- GDC policy: clinical dates are stored as intervals from initial pathologic diagnosis.
- In this extract, `index_date` is Diagnosis and `days_to_diagnosis` is 0 when populated among Alive/Dead cases.

Not used for the primary endpoint: follow-up first-event times, maximum arbitrary follow-up records, treatment dates, or supplement `Overall Survival Time in Days`.

Zero OS times, if present, are reported and not automatically dropped. Negative times exclude the person.

## 8. Secondary Endpoints

TBD — event-free survival or relapse will be included only if they can be defined unambiguously. They are not defined in Stage 3.

## 9. Candidate Covariates

Locked for the principal inferential models in Stage 5. Details: `docs/inferential_model_specification.md`.

**Primary clinical model:** age5, sex at birth, log2(WBC), risk group (Low / Standard / High).

**Secondary molecular/cytogenetic model:** age5, sex at birth, log2(WBC), FLT3/ITD, NPM, CEBPA, t(8;21), inv(16), MLL, monosomy 7. Risk group is excluded from this model.

**Excluded from both principal models**

- FAB (~56% not observed)
- primary cytogenetic code (NEEDS REVIEW; redundancy with lesion flags)
- race and ethnicity (not automatic biological risk factors; reserved for a separately framed analysis)
- CNS disease, marrow blasts, peripheral blasts (parsimony / redundancy; optional labeled expanded sensitivity later)

**NOT RECOMMENDED as ordinary baseline covariates**

- protocol identifier (possible stratifier only)
- unvarying Cases API diagnosis labels
- MRD, SCT in first CR, gemtuzumab, first event, treatment outcome

File precedence remains `docs/baseline_covariate_source_rules.md`. Association with survival was not used to classify or include variables.

## 10. Descriptive Analysis

Locked in Stage 4. Produced for the overall primary cohort only.

- Cohort size and exclusion counts, including identity accounting
- Table 1 of baseline characteristics for the full locked cohort (N = 1978)
- Table 1 is **not** stratified by vital status, death, or any survival outcome
- Table 1 contains **no p-values**
- Continuous variables: median (Q1, Q3); min–max and selected quantiles in companion summaries
- Categorical variables: n (%) with Unknown and Missing retained as distinguishable
- Percentages use the full cohort denominator unless a companion audit says otherwise
- Overall Kaplan–Meier survival at 1, 3, and 5 years with 95% confidence intervals
- Number at risk at 0, 1, 3, 5, and 10 years
- Follow-up duration by reverse Kaplan–Meier (deaths treated as censored)
- The median of observed `os_days` is not reported as median follow-up or as median OS

Stage 6 may add unadjusted KM curves for risk group and FLT3/ITD only. Those plots are descriptive, not variable-selection tools. Log-rank tests are not required; if shown they are unadjusted and secondary. Univariable survival screening is not used to include or exclude covariates.

## 11. Primary Statistical Analysis

Locked. Cox proportional hazards regression with Efron ties. **Executed in Stage 6** (`artifacts/inference/`, `reports/stage6_inferential_analysis.qmd`). The specification below is unchanged.

Primary formula:

`Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std`

- `age5` = age in years / 5 (linear; HR per 5 years)
- `sex_std`: Male vs Female (reference Female)
- `log2_wbc`: HR per doubling of baseline WBC
- `risk_group_std`: Standard and High vs Low (reference Low)

Secondary formula:

`Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + flt3_itd_std + npm_std + cebpa_std + cytogenetics_t821_std + cytogenetics_inv16_std + cytogenetics_mll_std + cytogenetics_monosomy7_std`

Binary flags: Yes vs No (reference No).

Estimates are associations, not causal effects. No stepwise, LASSO, elastic net, random survival forests, boosting, or automated feature selection. No interactions in either principal model.

Complexity descriptor (not power): 695 deaths; primary df = 5 (139 events/df); secondary df = 10 (69.5 events/df).

## 12. Model Assumptions and Diagnostics

Locked for Stage 6 execution. **Executed in Stage 6** (`artifacts/inference/ph/`, `artifacts/inference/nonlinear_sensitivity_summary.csv`). Diagnostic rules below are unchanged.

Proportional hazards: scaled Schoenfeld residuals, covariate-specific and global `cox.zph` tests, and plots. A p-value alone is not proof of a material violation.

Functional form: primary linear age5 and log2 WBC; spline sensitivities with 3 knots at Stage 4 10th/50th/90th percentiles.

Influence: deviance residuals, martingale residuals where useful, dfbeta. Concordance is descriptive. Influential observations are not deleted automatically.

PH remediation (prespecified): minor departure → retain Cox as an average HR; material violation in a nuisance factor → consider strata; material violation in a scientifically important predictor → log(time) interaction sensitivity without replacing the primary model.

## 13. Missing Data

Primary cohort eligibility is **not** conditional on complete candidate covariates.

Unknown / Not Reported vital status is a cohort exclusion, not censoring.

Source encodings distinguished in staging/analytics:

- structurally missing
- not reported
- unknown (includes spreadsheet NA/N/A unless clearly not applicable)
- not applicable
- numeric sentinels (−99 / −999 / −9999)
- observed (including 0)

For inferential covariates, Unknown / Not Reported / structural missing / unresolved risk tokens `10`/`30` are missing information, not biological levels.

**Primary method:** multiple imputation with `mice`, m = 30, seed 20260814. Do not impute identifiers, OS time, OS event, age, or sex. Impute `log2_wbc` with PMM, risk group with polytomous regression, and binary flags with logistic regression. Include `os_event` and a nonparametric Nelson–Aalen cumulative hazard as auxiliaries. Rubin pooling is on the coefficient scale.

**Sensitivity:** complete-case Cox using the same specification.

MAR is a working assumption conditional on the imputation model. Stage 4 did not prove MAR. MNAR remains possible. No MNAR sensitivity is required for the portfolio MVP unless later justified.

**Executed in Stage 6.** Diagnostics: `artifacts/inference/mi/`. Completed person-level imputations are gitignored. No imputation was performed in Stages 3–5.

## 14. Sensitivity Analyses

Prespecified population sensitivities (eligibility flags only in Stage 3; not analyzed):

- Age at diagnosis ≤ 21 years, otherwise the same identity and OS rules
- No age restriction, otherwise the same identity, diagnosis, and OS rules
- Supplement OS time comparison if later justified by the documented discordance; the primary endpoint will not be switched to maximize N or event count

Locked analysis sensitivities (Stage 6; **executed**):

- Complete-case Cox vs primary MI, same formulas
- Restricted cubic splines for age and log2 WBC (3 knots; Stage 4 quantiles)
- PH remediation models only if diagnostics indicate a material violation, following the hierarchy in Section 12

Bayesian models, if used, will be secondary unless later justified in this plan.

## 15. Multiplicity

**Primary clinical model:** report adjusted HR, 95% CI, and nominal two-sided p-values. No automated correction across this small prespecified set. Emphasis on risk group and WBC.

**Secondary molecular/cytogenetic model:** report HR, CI, and nominal p, plus Benjamini–Hochberg q-values for the frozen family FLT3/ITD, NPM, CEBPA, t(8;21), inv(16), MLL, monosomy 7. FDR is not applied to age, sex, or WBC.

## 16. Sample Size / Power

This is a secondary use of an existing clinical dataset. Available sample size and event counts are described from the locked cohort in Stage 4. Any post-hoc precision or power calculations will be labeled as such and will not be presented as prospective trial design. Formal power analysis is not part of Stage 4.

## 17. Statistical Software

- Python 3.12+: ingestion, validation, cohort construction
- PostgreSQL: `raw`, `staging`, and `analytics` tables
- R: primary statistical analysis (expected packages include dplyr, tidyr, ggplot2, survival, gtsummary, broom, and mice)
- Quarto: investigator-facing report

Package versions used for the locked inferential analysis are recorded in `artifacts/inference/r_session_info.json` and `artifacts/inference/model_metadata.json`.

## 18. Deviations From the Analysis Plan

Stage 3 implemented the prespecified primary rules (age <18; GDC vital status; GDC death / diagnosis last-follow-up time; no covariate-completeness gate) without switching the endpoint after seeing survival associations.

No deviation from those prescribed Stage 3 rules was required by the GDC field definitions. Time origin was verified from official GDC/caDSR definitions and extract metadata before the endpoint table was created.

Later changes to the locked population or endpoint must be dated, described, and justified here.

Stage 4 descriptive findings that affected Stage 5 planning, but did **not** change frozen eligibility and were **not** chosen by survival association:

- WBC at diagnosis is strongly right-skewed → primary log2(WBC); spline sensitivity of log2(WBC)
- Risk-group tokens `10` and `30` (n = 3) have no CDE mapping → inferential missing plus QA flag
- Mixed-case Yes/NO molecular tokens → case-harmonized Yes/No
- FAB is too incomplete for ordinary CORE use → excluded from both principal models
- Risk group is potentially redundant with FLT3/ITD and cytogenetic lesion flags → separate primary vs secondary models
- Primary cytogenetic code remains NEEDS REVIEW versus lesion flags → excluded from both principal models

Stage 5 locked the inferential plan without fitting Cox models, running mice(), or examining predictor-specific survival. Stage 6 executed that plan. Deviations, including implementation details that do not change estimands, are recorded in `docs/stage6_sap_deviations.md`. Any later change after seeing survival associations must be recorded there and here.
