# PediaStat — Pediatric AML Survival Analysis

## Problem

Among children and adolescents with acute myeloid leukemia (AML), clinicians and investigators routinely ask which baseline characteristics are associated with overall survival. Public TARGET-AML data can support that question, but only after the sources, identities, and endpoint are defined carefully.

PediaStat is an observational prognostic association study using open NCI Genomic Data Commons TARGET-AML clinical data. The analysis estimates adjusted associations with overall survival. It does not estimate causal treatment effects and is not a validated clinical prediction tool.

## Why the Analysis Was Nontrivial

The scientific question is familiar. The data work was not.

TARGET-AML arrives as more than one source. The GDC Cases API provided demographics, diagnosis timing, and survival fields for 2,492 cases. Standard AML baseline characteristics—white-blood-cell count, protocol risk group, FLT3/ITD, NPM, CEBPA, and common cytogenetic lesions—were not adequately populated there. Those variables lived in seven open clinical-supplement workbooks and 13 sheets. The workbooks overlapped and could not be concatenated blindly.

Survival itself required a source decision. Vital status agreed almost perfectly between GDC and the supplements, but some supplement overall-survival time fields were substantially discordant. GDC therefore became the primary endpoint source: death times from `demographic.days_to_death` and censoring times from `diagnoses.days_to_last_follow_up`, both measured from initial pathologic diagnosis.

Identity was another source of error. Not every GDC case is a patient. Experimental constructs, cell-line names, and ambiguous barcodes were present. One hundred thirty-eight such identifiers were excluded rather than guessed. Eighteen persons had multiple compatible GDC cases and were consolidated only after vital status, times, age, and sex were checked for conflict.

Missing baseline covariates were common enough that dropping incomplete rows would have changed the analysis population after the cohort had already been frozen. That is a design problem, not a software problem. The cohort, endpoint, and models were therefore specified before any predictor–survival association was examined.

## Data

The study uses only public TARGET-AML data. Controlled-access genomic files were not used.

After identity resolution, 2,315 unique valid analysis persons remained. The primary population was restricted to diagnosis before age 18 years, a usable GDC diagnosis record, and a valid Alive/Dead overall-survival endpoint. Unknown or missing vital status was not treated as censoring. Predictor completeness was not an inclusion criterion.

The locked primary cohort contains 1,978 patients, 695 deaths, and 1,283 censored observations. Median age at diagnosis was 9.5 years. Median WBC was 26.7 ×10³/mcL and was strongly right-skewed. Protocol risk group was Standard in 935 patients, Low in 679, High in 250, and unknown in 88.

## Statistical Approach

Overall survival was summarized with Kaplan–Meier estimates. Potential follow-up was summarized with the reverse Kaplan–Meier estimator.

The primary clinical Cox model included age per five years, sex, WBC per doubling, and protocol risk group. The secondary model replaced risk group with FLT3/ITD, NPM, CEBPA, t(8;21), inv(16), MLL/KMT2A rearrangement, and monosomy 7. Risk group was kept out of the secondary model because protocol classification already uses some of the same biological information. There were no interactions and no stepwise selection.

Missing covariates were handled with 30-fold multiple imputation by chained equations. The imputation model included the event indicator and a Nelson–Aalen cumulative hazard so that the missingness model was compatible with the survival analysis. Survival time and event status were never imputed. Complete-case analysis was reserved as a sensitivity analysis.

Prespecified checks included restricted cubic splines for age and WBC, Schoenfeld residual proportional-hazards diagnostics, and influence diagnostics. A Benjamini–Hochberg FDR family was frozen for the seven secondary biological predictors before those results were seen.

## Key Results

Overall survival in the primary cohort was 82.7% at 1 year (95% CI 80.9%–84.3%), 66.8% at 3 years (64.6%–68.8%), and 63.1% at 5 years (60.8%–65.3%). Median overall survival was not reached. Median potential follow-up was 5.39 years (95% CI 5.29–5.49).

In the multiply imputed primary model, both Standard and High protocol risk groups had substantially higher adjusted hazards than Low risk (HR 3.85, 95% CI 3.10–4.78; and HR 3.50, 95% CI 2.71–4.53). The global two-degree-of-freedom risk-group test was *p* = 3.7×10⁻³². The point estimates do not support a monotonic Standard-then-High story. WBC was associated with higher hazard (HR 1.08 per doubling; 95% CI 1.05–1.12). Age had a modest positive association (HR 1.12 per five years; 95% CI 1.05–1.20). Sex was compatible with no association.

In the secondary model, NPM, CEBPA, t(8;21), and inv(16) were associated with lower adjusted hazard. Monosomy 7 was associated with higher adjusted hazard (HR 1.72; 95% CI 1.13–2.62; *q* = 0.016). FLT3/ITD and MLL/KMT2A were compatible with no association. Descriptive concordance was 0.658 in the primary model and 0.665 in the secondary model. Those values were not optimized and do not validate a prediction model.

## Robustness and Diagnostics

Complete-case fits used the same formulas (primary N = 1,861; secondary N = 1,825) and were substantively similar to the multiply imputed results. Nonlinear spline checks gave little evidence that the linear age or log2-linear WBC specifications needed replacement. Global proportional-hazards tests were *p* = 0.076 (primary) and *p* = 0.053 (secondary). WBC showed a minor Schoenfeld departure that did not meet the prespecified remediation threshold; its hazard ratio is therefore an average relative hazard over follow-up. No observation was removed because it was influential. Sparse predictors such as CEBPA and monosomy 7 had influential points that were valid and retained.

The only recorded SAP deviation was a collapse of sparse auxiliary race categories in the imputation model. That decision was made before hazard ratios were viewed. Race is not a predictor in either Cox model.

## What I Built

The repository is a complete applied-biostatistics workflow: a Python package and PostgreSQL layer for source-faithful ingestion and cohort construction; locked analysis-plan documents; R scripts for descriptive analysis, MICE, Cox models, and diagnostics; and investigator-facing Quarto reports. Aggregate tables and figures are committed. Patient-level extracts, imputations, and residuals are not.

## Limitations

The analysis is observational. Residual confounding remains possible. TARGET public data may not represent all pediatric AML populations. Baseline variables were assembled from overlapping supplements. Multiple imputation relies on a Missing At Random working assumption. Some molecular categories are sparse. There is no external validation. Concordance should not be read as predictive performance.

## Skills Demonstrated

Study-question formulation; clinical-data QA/QC and source reconciliation; cohort and endpoint definition; prespecified statistical analysis; Kaplan–Meier and reverse Kaplan–Meier estimation; multiple imputation; Cox regression; model diagnostics and sensitivity analysis; and investigator-facing statistical reporting in R and Python.
