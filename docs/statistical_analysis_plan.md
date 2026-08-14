# Statistical Analysis Plan

This document is a **template**. Sections will be completed after the source
data and accompanying documentation have been inspected. Unresolved items
are marked TBD rather than invented.

Version: 0.1 (template)
Status: draft — not ready for analysis lock

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

TBD — finalize after inspecting the source data and documentation.

Expected source: NCI TARGET-AML clinical data. The specific files, data
versions, access method, and data-use constraints will be recorded here
once inspected. No source variables are listed until they are observed.

## 4. Study Population

TBD — finalize after inspecting the source data and documentation.

The target population is children and adolescents with acute myeloid
leukemia. The operational analysis population will be defined from the
source extract after reviewing eligibility fields, diagnosis coding, and
follow-up availability.

## 5. Inclusion Criteria

TBD — finalize after inspecting the source data and documentation.

## 6. Exclusion Criteria

TBD — finalize after inspecting the source data and documentation.

Exclusions from the analytical cohort will be counted and reported in a
cohort-construction flow (for example, a CONSORT-style diagram).

## 7. Primary Endpoint

TBD — finalize after inspecting the source data and documentation.

Provisional primary endpoint: overall survival, defined as time from a
to-be-specified time origin (for example, diagnosis or study entry) to
death from any cause, with administrative censoring at last known follow-up
for patients not observed to die.

The time origin, event indicator, censoring rules, and units of time will
be defined from the source documentation. These definitions will not be
improvised from memory.

## 8. Secondary Endpoints

TBD — finalize after inspecting the source data and documentation.

Possible secondary endpoints (event-free survival, relapse, treatment
response) will be included only if they can be defined unambiguously from
the source data.

## 9. Candidate Covariates

TBD — finalize after inspecting the source data and documentation.

Baseline patient and disease characteristics will be listed here only after
the data dictionary and observed fields are reviewed. Variables will be
classified as:

- primary covariates of scientific interest
- adjustment covariates
- descriptive-only variables
- excluded variables, with a reason

No TARGET field names are recorded in this version.

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

TBD — finalize after inspecting the source data and documentation.

Missingness will be described by variable and, where feasible, by observed
covariates. Primary handling of missing data will be chosen after reviewing
the missingness pattern. Missing values will not be silently dropped.
Complete-case analysis, if used, will be justified and accompanied by a
sensitivity analysis.

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
