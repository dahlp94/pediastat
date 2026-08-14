# Stage 4 baseline variable definitions

Verified against `docs/baseline_covariate_source_rules.md`,
`docs/data_dictionary.md`, `artifacts/ingestion_audit/clinical_concept_source_map.csv`,
and GDC/CDE wording. Stage 4 does not change these definitions.

Unknown and structurally missing remain distinguishable. Values are never
averaged across sources.

| Concept | Timing | Units | Coding | Precedence | Unknown / missing |
| --- | --- | --- | --- | --- | --- |
| Age at diagnosis | Diagnosis | days (years = days / 365.25 for description) | GDC numeric | GDC only | Missing age is a Stage 3 exclusion, not a Table 1 missingness class in the primary cohort |
| Sex at birth | Baseline demographic | none | male / female / unknown | GDC | GDC unknown remains unknown; not replaced by supplement Gender |
| Race | Baseline demographic | none | GDC OMB-style groups | GDC | Unknown / not reported remain explicit |
| Ethnicity | Baseline demographic | none | GDC Hispanic/Latino grouping | GDC | Unknown / not reported remain explicit |
| WBC at diagnosis | Diagnosis | **x10^3/mcL** (CDE: absolute peripheral WBC) | numeric | AML1031 > Discovery > Validation > LowDepth > additional | Not required for cohort entry |
| Risk group | Baseline (cytogenetics- and biomarker-defined) | none | CDE: High / Low / Standard Risk | same as WBC | Unknown remains unknown. Unexpected tokens `10` and `30` are retained and flagged |
| FLT3/ITD | Baseline molecular | none | Yes / No / Unknown (source also has YES/NO) | same as WBC | Unknown remains unknown. Mixed case is a coding QA issue, not a new clinical level |
| NPM mutation | Baseline molecular | none | Yes / No / Unknown (plus YES/NO) | same as WBC | Same mixed-case note as FLT3/ITD |
| CEBPA mutation | Baseline molecular | none | Yes / No / Unknown (plus YES/NO) | same as WBC | Same mixed-case note as FLT3/ITD |
| FAB category | Baseline morphology | none | M0–M7 and related labels | Discovery > Validation > LowDepth > additional > AML1031 | AML1031 is nearly empty; structural missing is common |
| CNS disease | Baseline involvement | none | Yes / No / Unknown | same as WBC | Unknown remains unknown |
| Marrow blasts | Diagnosis | **percent** of nucleated marrow cells (CDE) | numeric 0–100 expected | same as WBC | Zero is retained as observed, not recoded to missing |
| Peripheral blasts | Diagnosis | **percent** (column name). CDE wording is thinner than marrow; unit is still treated as percent of peripheral leukocytes as labeled in the source column | numeric 0–100 expected | same as WBC | Zero is retained as observed |
| t(8;21), inv(16), MLL, monosomy 7 | Baseline cytogenetic lesion flags | none | Yes / No / Unknown | same as WBC | Not collapsed into a composite karyotype |
| Primary cytogenetic code | Baseline summary code | none | source labels (Normal, MLL, t(8;21), inv(16), PML-RARA, Other, Unknown) | Discovery > Validation > AML1031 > LowDepth > additional | **NEEDS REVIEW**; not assumed equivalent to lesion flags |

OS event and time are locked in Stage 3 and are not baseline covariates.
