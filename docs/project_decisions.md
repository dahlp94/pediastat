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
