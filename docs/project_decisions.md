# Project Decisions

This log records architecture and statistical decisions so they remain
auditable. New entries should be appended rather than silently rewritten.
If a decision is reversed, add a later entry that supersedes it.

## Decision 1 — R as the primary statistical-analysis language

Date: 2026-08-13
Status: accepted

R will be the primary language for statistical analysis, including
descriptive tables, survival modeling, missing-data methods, and
sensitivity analyses. Expected packages include dplyr, tidyr, ggplot2,
survival, gtsummary, broom, and mice.

Rationale: these tools are standard in collaborative biostatistics and
produce investigator-facing tables and models with well-understood
assumptions.

## Decision 2 — Python for ingestion, validation, and data utilities

Date: 2026-08-13
Status: accepted

Python will handle data ingestion, raw-data validation, PostgreSQL loading,
and reproducible preprocessing utilities, with automated tests around that
infrastructure.

Rationale: Python is well suited to file handling, typed configuration,
database loading, and regression tests, while leaving the inferential
analysis in R.

## Decision 3 — PostgreSQL schemas for raw, staging, and analytics

Date: 2026-08-13
Status: accepted

PostgreSQL will store data in three schemas:

- `raw`: immutable source extracts as ingested
- `staging`: cleaned data after documented QA/QC
- `analytics`: analysis-ready cohort tables

Rationale: separating layers makes transformations reviewable and protects
the original extract from in-place edits. Clinical tables will be created
only after the source data are inspected.

## Decision 4 — Cox regression as the provisional primary survival framework

Date: 2026-08-13
Status: provisional

Cox proportional hazards regression is currently expected to be the primary
survival-analysis framework for associations between baseline
characteristics and overall survival.

This choice is provisional until the data are inspected, including event
counts, follow-up, missingness, and whether proportional-hazards
assumptions are tenable. The analysis will estimate associations, not
causal effects.

## Decision 5 — Bayesian modeling is secondary

Date: 2026-08-13
Status: accepted

Bayesian modeling will be considered only as a later sensitivity or
secondary analysis, and only if scientifically justified in the analysis
plan.

Rationale: the primary analysis should use interpretable standard methods
familiar to a clinical investigator audience unless a Bayesian approach is
needed to address a specific limitation.

## Decision 6 — Predictive machine learning is out of initial scope

Date: 2026-08-13
Status: accepted

Predictive ML models (risk scores, black-box classifiers, leaderboard-style
prediction) are intentionally outside the initial scope.

Rationale: the scientific question is about associations and robustness,
not about building a prediction product. Prediction and association will
be kept conceptually distinct if prediction is ever added later.

## Decision 7 — Analyses follow a written plan

Date: 2026-08-13
Status: accepted

Statistical analyses should follow the written statistical analysis plan
rather than being selected after inspecting favorable results. Deviations
will be recorded in the analysis plan.

Rationale: pre-specification reduces the risk of cherry-picking models,
covariates, or subgroups and makes the work closer to collaborative
biostatistics practice.

## Decision 8 — TARGET-AML remains the chosen public dataset

Date: 2026-08-14
Status: accepted

The public NCI GDC TARGET-AML project remains the intended source. TCGA-LAML
and other adult AML datasets will not be substituted. The Cases API returned
2492 TARGET-AML cases at the Stage 1 audit; that count is not permanent.

## Decision 9 — Overall survival is feasible with modifications

Date: 2026-08-14
Status: accepted

An overall-survival association study is feasible from public TARGET-AML
data, with modifications. At the Stage 1 audit, 2158 of 2492 cases had
Alive/Dead vital status and a non-negative death or last-follow-up time
(742 deaths). Unknown and not-reported vital status will not be treated as
censored.

The Cases API diagnosis table alone is not scientifically sufficient:
primary diagnosis and morphology have no variation, and AML-specific
baseline fields (risk group, FAB, FLT3, WBC, cytogenetics) are unpopulated
there.

## Decision 10 — Use Cases API plus open clinical supplements

Date: 2026-08-14
Status: accepted

The appropriate source is a **combination**:

- GDC Cases API for identifiers, demographic/vital status, nested
  diagnosis/follow-up/treatment structure, and GDC-normalized survival
  fields
- Open-access TARGET clinical supplements for AML-specific baseline
  covariates and a CDE-defined OS time

Neither source alone is the production extract yet. Controlled-access
files will not be downloaded.

## Decision 11 — Censoring rule remains unlocked

Date: 2026-08-14
Status: provisional

A candidate OS rule is: event if Dead, censored if Alive; time from
`demographic.days_to_death` or `diagnoses.days_to_last_follow_up`; time
origin at diagnosis. Last Contact follow-up times and supplement
`Overall Survival Time in Days` are sensitivity candidates.

This is not locked. Nested follow-up records mix Last Contact with
first-event (EFS-like) times. Concordance across API and supplements has
not been measured case-by-case.

## Decision 12 — Candidate baseline covariates from observed fields

Date: 2026-08-14
Status: provisional

High-priority candidates actually found: age at diagnosis (days), sex at
birth, and supplement WBC, risk group, FLT3/ITD, and cytogenetic/FAB
fields where populated.

Possible: race, ethnicity, year of diagnosis, protocol as a stratifier.

Not recommended as baseline covariates: unvarying Cases API diagnosis
labels; empty mapping fields such as ELN/CALGB risk on the Cases API;
post-baseline SCT, MRD, gemtuzumab, and treatment outcome; treatment
records without start days.

## Decision 13 — Cox PH remains provisional

Date: 2026-08-14
Status: provisional

Decision 4 is not locked by this audit. Event counts appear large enough
to consider Cox PH later, but proportional-hazards tenability, follow-up
completeness, missingness in supplement covariates, and the final cohort
definition are still unknown. No survival model was fit in Stage 1.

## Decision 14 — Keep one-to-many clinical entities until Stage 2

Date: 2026-08-14
Status: accepted

Diagnoses are one-to-one when present in this extract, but follow-ups and
treatments are one-to-many. Raw/staging tables should preserve that
cardinality. A one-row-per-patient analytics table will be built only
after follow-up timepoint rules and supplement de-duplication are
documented.

## Decision 15 — Raw-source architecture (Stage 2)

Date: 2026-08-14
Status: accepted

Raw GDC tables store typed join/QA columns plus the original entity JSON
in `payload` JSONB. Raw supplements store one workbook/sheet/row with
original column names in `cells` JSONB. Staging standardizes primitive
types and missingness classes without merging sources. Analytics cohort
tables were not created.

## Decision 16 — Source registry and ingestion runs

Date: 2026-08-14
Status: accepted

`raw.source_registry` catalogs every ingested dataset. `raw.ingestion_runs`
records each load. Reloads replace rows for a source inside a transaction.

## Decision 17 — Identifier normalization is join-only

Date: 2026-08-14
Status: accepted

Original identifiers are retained. Join comparison trims whitespace and
uppercases. `join_barcode` is the leading `TARGET-NN-TOKEN`. Suffixes such
as `-Unsorted` stay on `normalized_identifier`. Short experimental
`TARGET-20-D#` tokens are not patient keys.

## Decision 18 — Missing-value policy

Date: 2026-08-14
Status: accepted

Staging distinguishes structurally missing, not reported, unknown, not
applicable, sentinel, and observed. Spreadsheet `NA`/`N/A` maps to unknown.
Unknown/Not Reported vital status is not censoring. Raw values are kept.

## Decision 19 — Supplements remain source-identifiable

Date: 2026-08-14
Status: accepted

The seven XLSX files were not concatenated. Unique clinical-data USI union
is 2144. 1630 patients appear in one file; 475 in two; 38 in three; 1 in
four. AML1031 is largely disjoint from Discovery/Validation/LowDepth.

## Decision 20 — OS discordance delays endpoint lock

Date: 2026-08-14
Status: accepted

Vital status agrees closely across GDC and supplements. OS time does not:
Validation vs GDC candidate 68.89% exact; LowDepth vs Validation 47.38%
exact among 363 shared patients. No OS time source is implemented as
canonical.

## Decision 21 — Tentative source-precedence recommendations

Date: 2026-08-14
Status: provisional (not implemented)

Recommended later: GDC for vital status, age, sex at birth; AML1031 for
WBC/risk/FLT3/NPM/CEBPA where present; Discovery/Validation/LowDepth for
FAB; OS time unresolved. See the Stage 2 reconciliation report.

## Decision 22 — Age eligibility remains unresolved

Date: 2026-08-14
Status: provisional

Among 2158 diagnoses with age: 2012 are <18 years, 2117 are ≤21, 33 are
22–29. No cutoff was chosen to maximize N.

## Decision 23 — Delay analytics cohort construction

Date: 2026-08-14
Status: accepted

Stage 2 stops after raw/staging ingestion and reconciliation. No
`analytics.patient_cohort`, survival dataset, Table 1, Kaplan–Meier, Cox
model, imputation, Bayesian analysis, or power calculation was produced.

## Decision 24 — Primary age eligibility is < 18 years

Date: 2026-08-14
Status: accepted

The primary OS cohort is restricted to age at diagnosis < 18 years, using
GDC `diagnoses.age_at_diagnosis` converted as days / 365.25. The cutoff
follows the scientific question (children and adolescents). It was not
chosen to maximize N. TARGET-AML young adults are reserved for a
prespecified age ≤21 sensitivity population and are not in the primary
analysis.

## Decision 25 — Primary OS event is GDC vital status

Date: 2026-08-14
Status: accepted

Dead = event 1; Alive = event 0, from GDC `demographic.vital_status`.
Unknown, Not Reported, and structurally missing vital status are excluded
from the primary OS cohort and are not classified as censored. Supplement
vital status is QA only and is not required to define the event.

## Decision 26 — Primary OS time is status-dependent GDC time

Date: 2026-08-14
Status: accepted

If Dead: `demographic.days_to_death`. If Alive:
`diagnoses.days_to_last_follow_up`. First-event follow-up times, maximum
arbitrary follow-up records, treatment dates, and supplement OS days are
not the primary endpoint. Supplement OS remains QA / future sensitivity
information. The endpoint was not switched to the source that maximizes N
or event count.

## Decision 27 — Time origin is initial pathologic diagnosis

Date: 2026-08-14
Status: accepted

Official GDC/caDSR definitions: `days_to_last_follow_up` is the interval
from last follow-up to initial pathologic diagnosis (CDE 3008273);
`days_to_death` is days from the GDC index to death (CDE 6154724); GDC
policy stores dates as intervals from initial pathologic diagnosis;
`age_at_diagnosis` is days since birth (CDE 3225640). In this extract,
`index_date` is Diagnosis and `days_to_diagnosis` is 0 when populated
among Alive/Dead cases. The fields share a coherent origin. A few cases
lack `index_date`; they are retained with a QA flag rather than used as
grounds to abandon the endpoint.

## Decision 28 — Analysis-person identity

Date: 2026-08-14
Status: accepted

The unit of analysis is the analysis person. Eligible identity is a
canonical six-character `TARGET-20` or `TARGET-21` USI. Extended
identifiers are collapsed to that USI only when the suffix is a documented
biospecimen qualifier (Unsorted / Sorted-…) and clinical fields are
compatible. Prefix similarity alone is not sufficient. Short
`TARGET-20-D#` experimental tokens, other experimental constructs,
cell-line names, and `TARGET-00-` barcodes are not primary person IDs.
Conflicting multi-case records exclude the person. Original GDC
identifiers are retained.

## Decision 29 — Cohort eligibility does not require covariate completeness

Date: 2026-08-14
Status: accepted

WBC, risk group, FLT3/ITD, NPM, CEBPA, FAB, race, ethnicity, and
supplement membership do not define primary cohort membership. Missing
covariate handling will be specified later, before model fitting. No
imputation was performed in Stage 3.

## Decision 30 — Baseline source precedence is locked from source quality

Date: 2026-08-14
Status: accepted

AML1031 is preferred for WBC, risk group, FLT3/ITD, NPM, CEBPA, CNS
disease, and lesion flags where present. FAB uses Discovery / Validation /
LowDepth, not AML1031. Conflicts set a flag and keep the precedence
winner. Values are not averaged. Survival association was not used to
choose precedence. See `docs/baseline_covariate_source_rules.md`.

## Decision 31 — Stage 3 freeze

Date: 2026-08-14
Status: accepted

Stage 3 created `analytics.patient_identity_crosswalk`,
`analytics.cohort_eligibility`, `analytics.primary_os_cohort`, and
`analytics.baseline_covariates_reconciled`. No Table 1, Kaplan–Meier,
log-rank, Cox model, hazard ratio, imputation, Bayesian model, or power
calculation was produced. Later changes to the locked population or
endpoint must be recorded as SAP deviations.


