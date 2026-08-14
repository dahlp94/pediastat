# Statistical Analysis Plan

Version: 0.3 (Stage 3 primary population and OS endpoint locked)
Status: population and primary endpoint locked; multivariable model, missing-data method for covariates, and inferential analysis remain TBD.

Companion documents:

- `docs/primary_cohort_specification.md`
- `docs/baseline_covariate_source_rules.md`
- `docs/target_aml_reconciliation_report.md`
- `artifacts/cohort_definition/`

## 1. Study Objective

Among children and adolescents with acute myeloid leukemia in public TARGET-AML data, estimate associations between prespecified baseline patient and disease characteristics and overall survival, while addressing censoring, missing data, statistical assumptions, and uncertainty.

This is an observational association study. Causal effects will not be claimed.

## 2. Scientific Hypotheses

TBD — the primary multivariable model is not locked. Hypotheses will distinguish prespecified associations of scientific interest from exploratory analyses before model fitting. Variable inclusion will not be determined by univariable p-value screening against survival.

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

The final multivariable model is **not** locked. Source-supported baseline candidates:

**CORE CANDIDATE**

- age at diagnosis (GDC; also an eligibility variable)
- sex at birth (GDC)
- WBC at diagnosis (supplements; AML1031 preferred)
- risk group (supplements; AML1031 preferred)
- FLT3/ITD, NPM, CEBPA (supplements; AML1031 preferred)

**SECONDARY CANDIDATE**

- FAB (Discovery/Validation/LowDepth preferred; not AML1031)
- CNS disease
- marrow and peripheral blast percentages
- cytogenetic lesion flags: t(8;21), inv(16), MLL, monosomy 7
- race, ethnicity (GDC; substantial Unknown)

**NEEDS REVIEW**

- primary cytogenetic code (source disagreements; not equivalent to lesion flags)

**NOT RECOMMENDED as ordinary baseline covariates**

- protocol identifier (possible stratifier only)
- unvarying Cases API diagnosis labels
- MRD, SCT in first CR, gemtuzumab, first event, treatment outcome

File precedence: `docs/baseline_covariate_source_rules.md`. Conflicts set a flag and keep the precedence winner. Values are not averaged. Association with survival was not used to classify variables.

## 10. Descriptive Analysis

TBD in Stage 4. Planned elements, not produced in Stage 3:

- Cohort size and exclusion counts (attrition already produced)
- Table 1 of baseline characteristics, including missingness
- Follow-up summaries
- Crude survival summaries (Kaplan–Meier) for the locked cohort only after Stage 3 freeze

## 11. Primary Statistical Analysis

TBD — finalize before model fitting.

Provisional primary method: Cox proportional hazards regression for associations between prespecified baseline covariates and overall survival.

This choice remains provisional until event counts, missingness, follow-up, and proportional-hazards tenability are assessed in later stages. Effect estimates will be reported as hazard ratios with confidence intervals. The analysis estimates associations, not causal effects.

Covariates will not be selected by univariable screening against the outcome.

## 12. Model Assumptions and Diagnostics

TBD — finalize before the primary fit is treated as final.

Assumptions to be assessed for a Cox model, if retained: proportional hazards, functional form of continuous covariates, influence of individual observations, and adequacy of follow-up and event counts.

## 13. Missing Data

Primary cohort eligibility is **not** conditional on complete candidate covariates.

Unknown / Not Reported vital status is a cohort exclusion (or missingness class), not censoring.

Source encodings distinguished in staging/analytics:

- structurally missing
- not reported
- unknown (includes spreadsheet NA/N/A unless clearly not applicable)
- not applicable
- numeric sentinels (−99 / −999 / −9999)
- observed (including 0)

Missing-covariate handling (complete case, multiple imputation, or another method) will be specified in a later stage **before** model fitting. No imputation was performed in Stage 3.

## 14. Sensitivity Analyses

Prespecified population sensitivities (eligibility flags only in Stage 3; not analyzed):

- Age at diagnosis ≤ 21 years, otherwise the same identity and OS rules
- No age restriction, otherwise the same identity, diagnosis, and OS rules
- Supplement OS time comparison if later justified by the documented discordance; the primary endpoint will not be switched to maximize N or event count

Other anticipated sensitivities, pending later specification: alternative missing-data methods, alternative covariate coding, and proportional-hazards violations.

Bayesian models, if used, will be secondary unless later justified in this plan.

## 15. Multiplicity

TBD — the primary analysis will be distinguished from secondary and exploratory analyses. Any multiplicity adjustment, or a decision not to adjust, will be stated explicitly before model fitting.

## 16. Sample Size / Power

This is a secondary use of an existing clinical dataset. Available sample size and event counts will be described from the locked cohort. Any post-hoc precision or power calculations will be labeled as such and will not be presented as prospective trial design. Formal power analysis is not part of Stage 3.

## 17. Statistical Software

- Python 3.12+: ingestion, validation, cohort construction
- PostgreSQL: `raw`, `staging`, and `analytics` tables
- R: primary statistical analysis (expected packages include dplyr, tidyr, ggplot2, survival, gtsummary, broom, and mice)
- Quarto: investigator-facing report

Package versions used for the locked inferential analysis will be recorded at analysis time.

## 18. Deviations From the Analysis Plan

Stage 3 implemented the prespecified primary rules (age <18; GDC vital status; GDC death / diagnosis last-follow-up time; no covariate-completeness gate) without switching the endpoint after seeing survival associations.

No deviation from those prescribed Stage 3 rules was required by the GDC field definitions. Time origin was verified from official GDC/caDSR definitions and extract metadata before the endpoint table was created.

Later changes to the locked population or endpoint must be dated, described, and justified here.
