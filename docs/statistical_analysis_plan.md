# Statistical Analysis Plan

This document is a **template**. Sections will be completed after the source
data and accompanying documentation have been inspected. Unresolved items
are marked TBD rather than invented.

Version: 0.2 (Stage 2 ingestion evidence added)
Status: draft — not ready for analysis lock. Age cutoff, OS time
precedence, covariate set, exclusions, and analysis N remain TBD.

## 1. Study Objective

TBD — finalize after inspecting the source data and documentation.

Provisional objective: among children and adolescents with acute myeloid
leukemia, evaluate associations between baseline patient and disease
characteristics and overall survival, while addressing censoring, missing
data, statistical assumptions, and uncertainty.

This is an observational association study. Causal effects will not be
claimed.

## 2. Scientific Hypotheses

TBD — finalize after inspecting the source data and documentation.

Hypotheses will be stated before primary modeling. They will distinguish
pre-specified associations of scientific interest from exploratory
analyses.

## 3. Data Source

Primary public source: NCI Genomic Data Commons project **TARGET-AML**
(`https://api.gdc.cancer.gov`), dbGaP accession phs000465.

Stage 1 inspected the Cases API and seven open Clinical Supplement XLSX
files (`docs/target_aml_source_audit.md`). Stage 2 ingested those sources
into PostgreSQL (`raw` / `staging`) and quantified overlap and discordance
(`docs/target_aml_reconciliation_report.md`).

Loaded sources:

- GDC Cases API entities: case, demographic, diagnosis, follow_up,
  treatment (2492 cases at the Stage 2 load; follow-ups and treatments
  remain one-to-many)
- Five patient-level clinical-data workbooks, ingested separately
- CDE dictionary workbook (definitions, not patients)
- Tumor-content/RIN workbook (not used as a clinical covariate table)

Join comparison uses a documented USI normalization (trim, uppercase;
`join_barcode` = leading `TARGET-NN-TOKEN`). Original identifiers are
retained. Short experimental `TARGET-20-D#` tokens must not be treated as
patient keys.

TCGA-LAML and genomic files remain out of scope.

TBD — lock the extract date, the final USI crosswalk rule for suffix
barcodes, and supplement-file precedence before analysis lock.

## 4. Study Population

TBD — age eligibility is not locked.

The target language remains children and adolescents with AML. GDC
`diagnoses.age_at_diagnosis` (days / 365.25) among 2158 diagnoses with
age:

| Band | n |
| --- | ---: |
| <1 | 170 |
| 1–4 | 490 |
| 5–9 | 394 |
| 10–14 | 554 |
| 15–17 | 404 |
| 18–21 | 113 |
| 22–29 | 33 |
| ≥30 | 0 |

Candidate thresholds among those 2158 (not a cohort rule):

- age < 18: 2012
- age ≤ 18: 2012 (no one is exactly 18.0 years)
- age ≤ 21: 2117

Including 18–29 would expand beyond a strictly pediatric interpretation.
Excluding them solely because the project title says pediatric is not an
acceptable rationale; the cutoff needs an explicit scientific rule.

303 of 2492 GDC cases have no diagnosis/demographic entity. Those cases
cannot currently contribute age or GDC OS fields.

## 5. Inclusion Criteria

TBD — finalize after inspecting the source data and documentation.

## 6. Exclusion Criteria

TBD — finalize after inspecting the source data and documentation.

Exclusions from the analytical cohort will be counted and reported in a
cohort-construction flow (for example, a CONSORT-style diagram).

## 7. Primary Endpoint

TBD — OS time precedence is not locked.

Provisional primary endpoint: overall survival from diagnosis to death
from any cause. Units: days.

Stage 2 concordance (QA only, not a locked rule):

- Event indicator: GDC `demographic.vital_status` and supplement
  `Vital Status` agree at or above 99.78% in overlapping observed pairs.
  One Discovery vs GDC Dead/Alive conflict exists.
- Unknown / Not Reported / missing vital status will **not** be coded as
  censored.
- Time: a GDC candidate (death time if Dead, `days_to_last_follow_up` if
  Alive) matches AML1031 and LowDepth OS days almost exactly, matches
  Discovery at 90.83%, and matches Validation at only 68.89%. LowDepth and
  Validation OS days agree in only 47.38% of 363 shared patients.

Competing time sources remain: GDC death time, GDC last follow-up, GDC
Last Contact follow-up, and each supplement `Overall Survival Time in Days`.
The source that yields the largest N will not be selected for that reason.

Time origin TBD (diagnosis is the leading candidate because
`days_to_diagnosis` is 0 when present and supplement OS is defined from
diagnosis).

## 8. Secondary Endpoints

TBD — finalize after inspecting the source data and documentation.

Possible secondary endpoints (event-free survival, relapse, treatment
response) will be included only if they can be defined unambiguously from
the source data.

## 9. Candidate Covariates

TBD — final covariate set is not locked. File precedence is not
implemented.

Primary candidates actually observed:

- age at diagnosis (GDC `diagnoses.age_at_diagnosis`; 100% agreement with
  supplements in overlap)
- sex at birth (GDC `demographic.sex_at_birth`; supplement `Gender`
  matched after case-fold but is CDE-defined as gender)
- WBC at diagnosis (supplements; 100% agreement in overlaps)
- risk group (supplements; small LowDepth disagreements)
- FLT3/ITD, NPM mutation, CEBPA mutation (supplements; AML1031 most
  complete)
- FAB category (supplements other than AML1031, where FAB is 99.35%
  missing)
- cytogenetic lesion flags / primary cytogenetic code (supplements)
- CNS disease (supplements)

Possible adjustment / descriptive:

- race, ethnicity (substantial Unknown)
- year of diagnosis
- protocol identifier as a stratifier, not a biological exposure

Excluded as baseline:

- unvarying Cases API diagnosis labels (AML NOS / 9861/3)
- empty GDC ELN/CALGB/FAB mapping fields
- post-baseline SCT, MRD, gemtuzumab, treatment outcome, relapse sites
- treatment records without start days

Race/ethnicity missingness and FAB file-dependence may force a smaller
complete-case N or a later missing-data method. That method is not chosen
here.

## 10. Descriptive Analysis

TBD — finalize after inspecting the source data and documentation.

Planned elements, pending data inspection:

- Cohort size and exclusion counts
- Table 1 of baseline characteristics, including missingness
- Follow-up summaries (for example, reverse Kaplan–Meier for censoring time)
- Crude survival summaries

## 11. Primary Statistical Analysis

TBD — finalize after inspecting the source data and documentation.

Provisional primary method: Cox proportional hazards regression for the
association between pre-specified baseline covariates and overall survival.

This choice is provisional until the data are inspected (sample size,
event count, missingness, and follow-up). Effect estimates will be reported
as hazard ratios with confidence intervals. The analysis estimates
associations; it does not estimate causal effects.

## 12. Model Assumptions and Diagnostics

TBD — finalize after inspecting the source data and documentation.

Assumptions to be assessed for a Cox model, if that framework is retained:

- Proportional hazards
- Functional form of continuous covariates
- Influence of individual observations
- Adequacy of follow-up and event counts for the planned model

Diagnostic methods will be specified before the primary fit is treated as
final.

## 13. Missing Data

TBD — primary missing-data method is not locked. No imputation was
performed in Stage 2.

Source encodings distinguished in staging:

- structurally missing (null/blank)
- not reported
- unknown (includes spreadsheet NA/N/A unless the string is clearly
  not applicable)
- not applicable
- numeric sentinels (−99 / −999 / −9999)
- observed (including 0)

Unknown vital status is not combined with Alive as censoring.

Missingness is file-dependent (for example FLT3 Unknown in ~80% of the
additional sorted-cells file; FAB missing in 99.35% of AML1031). A later
complete-case analysis, if used, must report whose data are dropped by
file and by variable.

## 14. Sensitivity Analyses

TBD — finalize after inspecting the source data and documentation.

Anticipated sensitivity analyses, pending data inspection:

- Alternative cohort definitions or time origins
- Alternative missing-data methods
- Alternative covariate coding
- Assessment of proportional-hazards violations (for example, stratified
  Cox or time-varying effects)

Bayesian models, if used, will be secondary unless later justified in this
plan.

## 15. Multiplicity

TBD — finalize after inspecting the source data and documentation.

The primary analysis will be distinguished from secondary and exploratory
analyses. Any multiplicity adjustment, or a decision not to adjust, will be
stated explicitly.

## 16. Sample Size / Power

TBD — finalize after inspecting the source data and documentation.

This is expected to be a secondary use of an existing clinical dataset.
Available sample size and event counts will be described. Any post-hoc
precision or power calculations will be labeled as such and will not be
presented as prospective trial design.

## 17. Statistical Software

- Python 3.12+: ingestion, raw-data validation, and reproducible data
  utilities
- PostgreSQL: storage of raw, staging, and analytics tables
- R: primary statistical analysis (expected packages include dplyr, tidyr,
  ggplot2, survival, gtsummary, broom, and mice)
- Quarto: investigator-facing report

Package versions used for the locked analysis will be recorded at analysis
time.

## 18. Deviations From the Analysis Plan

TBD — finalize after inspecting the source data and documentation.

Deviations will be dated, described, and justified. They will be recorded
here rather than silently changing the analysis after seeing results.
