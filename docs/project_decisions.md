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
