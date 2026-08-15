# TARGET-AML Source Audit

This document is the Stage 1 source and schema audit. It records what the
public NCI Genomic Data Commons (GDC) currently exposes for TARGET-AML. It
does not define a locked analysis cohort, does not fit survival models, and
does not invent variables that were not observed.

Machine-readable companions:

- `artifacts/source_audit/project_metadata.json`
- `artifacts/source_audit/clinical_field_availability.csv` (identifier example lists omitted from the committed file)
- `artifacts/source_audit/survival_field_audit.json`
- `artifacts/source_audit/entity_cardinality.json`
- `artifacts/source_audit/open_clinical_files.csv`
- `artifacts/source_audit/open_clinical_supplement_columns.json`
- `artifacts/source_audit/open_clinical_supplement_key_fields.json`

## 1. Audit Date

- Audit timestamp (UTC): **2026-08-14T01:24:42+00:00**
- API base URL: `https://api.gdc.cancer.gov`
- GDC contents can change across data releases. Counts below are not
  permanent.

Open-access clinical supplements were downloaded immediately after the Cases
API pull (approximately 2026-08-14T01:24:51Z to 2026-08-14T01:24:56Z). MD5
checksums matched the GDC Files API for all seven files.

## 2. Official Data Source

| Item | Value |
| --- | --- |
| Program / project | TARGET-AML |
| API | NCI GDC Search and Retrieval API |
| Project endpoint | `GET /projects/TARGET-AML` |
| Cases endpoint | `POST /cases` with `project.project_id = TARGET-AML` |
| Files endpoint | `POST /files` with Clinical data category |
| Mapping endpoint | `GET /cases/_mapping` |
| Data dictionary | [GDC Data Dictionary](https://docs.gdc.cancer.gov/Data_Dictionary/) |
| Project page | [TARGET AML publication summary](https://gdc.cancer.gov/content/target-aml-publication-summary) |
| dbGaP accession | phs000465 |

TCGA-LAML, other adult AML projects, Kaggle copies, and genomic files were
not used.

## 3. TARGET-AML Project Metadata

Observed from `GET /projects/TARGET-AML`:

| Property | Value at audit |
| --- | --- |
| `project_id` | TARGET-AML |
| `name` | Acute Myeloid Leukemia |
| `disease_type` | Myeloid Leukemias; Not Applicable |
| `primary_site` | Hematopoietic and reticuloendothelial systems; Unknown |
| `releasable` | true |
| `released` | true |
| `state` | open |
| `dbgap_accession_number` | phs000465 |
| Project summary `case_count` | 2492 |
| Project summary `file_count` | 52213 |
| Clinical data category | 7 files; 2181 cases (project summary) |

`demographic.gender` is **not** in the current cases `_mapping`. The current
sex field is `demographic.sex_at_birth`.

## 4. Current Case Count

The Cases API pagination total for TARGET-AML at this audit was **2492**.
The audit retrieved 2492 case records.

This count must be re-queried before any later ingestion. It is not a
locked sample size.

Of 2492 cases:

- 2189 have a demographic entity and a diagnosis entity
- 303 have neither demographic nor diagnosis clinical entities in the
  returned Cases API payload
- 2151 have follow-up and treatment entities

## 5. GDC Clinical Data Structure

Observed entity relationships in the current Cases API payload:

```text
case
 ├── demographic          (0 or 1 object per case)
 ├── diagnoses[]          (0 or 1 diagnosis per case in this extract)
 │    └── treatments[]    (0 to 5 treatment records nested under diagnosis)
 └── follow_ups[]         (0 to 33 follow-up records at case level)
```

Follow-up records are **case-level**, not nested under diagnosis, in the
payload inspected here (`n_cases_with_follow_ups_nested_under_diagnosis = 0`).

Treatments are nested under diagnoses.

Identifiers:

| Field | Role |
| --- | --- |
| `case_id` | GDC UUID. Stable internal identifier. |
| `submitter_id` | TARGET barcode (pattern `TARGET-20-XXXXXX` or `TARGET-21-XXXXXX`). Human-readable / project identifier. |
| `project.project_id` | Always `TARGET-AML` in this extract. |

`case_id` should be the stable internal key. `submitter_id` is the join key
to TARGET clinical supplements (`TARGET USI`).

`index_date` is `Diagnosis` for 2181 cases and missing for 311. When present,
`diagnoses.days_to_diagnosis` is 0, consistent with diagnosis as the time
origin.

## 6. Survival Outcome Availability

GDC documents survival calculations using `demographic.vital_status` with
time from `demographic.days_to_death`, `diagnoses.days_to_last_follow_up`,
and/or `follow_ups.days_to_follow_up`, restricted to alive/dead vital status.
This audit inspected all three time fields. No final endpoint was created.

| Concept | Exact GDC Field | Available N | Missing N | Missing % | Notes |
| --- | --- | --- | --- | --- | --- |
| Vital status | `demographic.vital_status` | 2189 | 303 | 12.16 | Alive 1416; Dead 742; Not Reported 30; Unknown 1. Usable Alive/Dead N=2158. |
| Death time | `demographic.days_to_death` | 742 | 1750 | 70.22 | Present for all 742 Dead cases. Range 1 to 3243 days. No negatives or zeros. |
| Diagnosis last follow-up | `diagnoses.days_to_last_follow_up` | 2158 | 334 | 13.40 | Range 1 to 4134 days. No negatives or zeros. At most one diagnosis per case. |
| Follow-up time | `follow_ups.days_to_follow_up` | 2151 | 341 | 13.68 | Range 0 to 4134. 156 zero values. Multiple timed records per case. |
| First-event time (not OS) | `follow_ups.days_to_first_event` | 2151 | 341 | 13.68 | Aligns with EFS-like `first_event`, not overall survival. |

Vital-status class counts (N=2492):

| Class | N | How classified |
| --- | --- | --- |
| alive | 1416 | `Alive` |
| dead | 742 | `Dead` |
| other | 31 | `Not Reported` (30) + `Unknown` (1) |
| missing | 303 | field absent / null |

Unknown and not-reported vital status were **not** treated as censored.

Construction checks (not a locked rule):

- Dead cases with `days_to_death`: **742 / 742**
- Alive cases with `diagnoses.days_to_last_follow_up`: **1416 / 1416**
- Alive cases with `follow_ups.days_to_follow_up`: **1412 / 1416**
- Cases with multiple follow-up times: **2151**
- Max follow-up time vs diagnosis last follow-up disagreement: **0**
- Death time vs diagnosis last follow-up disagreement: **0**
- Death time vs max follow-up time disagreement: **0**
- Negative times: **none** in the three OS-related time fields
- Cases with a possible GDC-style alive/dead survival time: **2158**

Nested follow-up records do not all represent the same concept.
`timepoint_category` is `Last Contact` (n=2151 records) and `Follow-up`
(n=2151 records). `first_event` on the Follow-up records is Censored (1039),
Relapse (764), Induction Failure (187), Death (111), Death without Remission
(47), or Second Malignant Neoplasm (3). For 1029 cases, the nested
`days_to_follow_up` values disagree with each other. Taking the maximum
across follow-ups happened to match diagnosis last follow-up in this extract;
that is an observation, not a rule.

Possible future rules and approximate N with required fields:

| Candidate rule | N with required fields | Consequence |
| --- | --- | --- |
| Event if Dead, censored if Alive; time from `days_to_death` or `diagnoses.days_to_last_follow_up` | 2158 | Closest to current GDC alive/dead restriction. Excludes 334 cases with missing/other vital status. |
| Same event rule; living cases use max `follow_ups.days_to_follow_up` | 2154 | Similar N, but mixes Last Contact with first-event times unless restricted by `timepoint_category`. |
| Same event rule; living cases use only diagnosis last follow-up | 2158 | Avoids follow-up multiplicity. Agreed with max follow-up time in this extract. |

The exact censoring field is **not** locked.

## 7. Demographic Variable Availability

| Concept | Exact GDC Field | Type | Available N | Missing % | Candidate for Analysis? |
| --- | --- | --- | --- | --- | --- |
| Age at diagnosis (days) | `diagnoses.age_at_diagnosis` | long | 2158 | 13.40 | Yes — preferred age field. Range 3 to 10898 days (~0 to 29.8 years). |
| Age at index (years) | `demographic.age_at_index` | long | 2151 | 13.68 | Possible — years, includes 170 zeros (age <1 year). Redundant with age at diagnosis. |
| Days to birth | `demographic.days_to_birth` | long | 2151 | 13.68 | Possible derived check. Values are negative by GDC convention (−10898 to −3). |
| Sex at birth | `demographic.sex_at_birth` | keyword | 2189 (usable 2158) | 12.16 | Yes. male 1136; female 1022; unknown 31. |
| Gender | `demographic.gender` | — | 0 | 100 | No. Not in current mapping. |
| Race | `demographic.race` | keyword | 2189 (usable 1943) | 12.16 null; additional Unknown/not reported codes | Possible, with explicit missingness handling. |
| Ethnicity | `demographic.ethnicity` | keyword | 2189 (usable 2078) | 12.16 null; additional Unknown/not reported codes | Possible, with explicit missingness handling. |
| Year of birth / death | `demographic.year_of_birth`, `year_of_death` | long | 0 | 100 | No — unpopulated. |
| Cause of death | `demographic.cause_of_death` | keyword | 0 | 100 | No — unpopulated. |

Race values among non-null records: white 1551; black or african american 251;
Unknown 216; asian 97; not reported 30; other 22; american indian or alaska
native 13; native hawaiian or other pacific islander 9.

Ethnicity values: not hispanic or latino 1693; hispanic or latino 385;
Unknown 81; not reported 30.

Age is represented in three related ways. `diagnoses.age_at_diagnosis` is
days since birth. `demographic.age_at_index` is integer years on the index
date. `demographic.days_to_birth` is the signed GDC offset from index to
birth. Observed ages extend to 29 years, so the extract is not limited to
children under 18.

## 8. Diagnosis / Disease Variable Availability

| Concept | Exact GDC Field | Type | Available N | Missing % | Candidate for Analysis? |
| --- | --- | --- | --- | --- | --- |
| Primary diagnosis | `diagnoses.primary_diagnosis` | keyword | 2189 | 12.16 | Descriptive only. All values are `Acute myeloid leukemia, NOS`. No subtype variation. |
| Morphology | `diagnoses.morphology` | keyword | 2189 | 12.16 | Descriptive only. All values are `9861/3`. |
| FAB morphology | `diagnoses.fab_morphology_code` | keyword | 0 | 100 | Not in Cases API data. Present later in open supplements. |
| ELN risk | `diagnoses.eln_risk_classification` | keyword | 0 | 100 | Unpopulated in Cases API. |
| CALGB risk | `diagnoses.calgb_risk_group` | keyword | 0 | 100 | Unpopulated in Cases API. |
| Tissue of origin | `diagnoses.tissue_or_organ_of_origin` | keyword | 2189 | 12.16 | Descriptive only. All `Bone marrow`. |
| ICD-10 | `diagnoses.icd_10_code` | keyword | 2181 | 12.48 | Descriptive. All `C92.0`. |
| Year of diagnosis | `diagnoses.year_of_diagnosis` | long/mixed | 2155 | 13.52 | Possible era covariate. Range 1996–2017. Mixed numeric/string encoding. |
| Classification | `diagnoses.classification_of_tumor` | keyword | 2181 | 12.48 | All `primary` when present. |
| Days to diagnosis | `diagnoses.days_to_diagnosis` | long | 2181 | 12.48 | All 0. Supports diagnosis as index date. |
| Prior malignancy | `diagnoses.prior_malignancy` | keyword | 0 | 100 | Unpopulated. |
| Prior treatment | `diagnoses.prior_treatment` | keyword | 0 | 100 | Unpopulated. |
| Site of resection/biopsy | `diagnoses.site_of_resection_or_biopsy` | keyword | 2189 (usable 141) | 12.16 | Mostly `Not Reported`. |
| Case disease type | `disease_type` | keyword | 2492 | 0 | Myeloid Leukemias 2422; Not Applicable 70. |
| Case primary site | `primary_site` | keyword | 2491 | 0.04 | Hematopoietic and reticuloendothelial systems 2422; Unknown 69. |

AML-specific baseline attributes that would usually matter for pediatric AML
survival — FAB category, cytogenetic lesions, FLT3/ITD, NPM1, CEBPA, WBC,
CNS disease, and protocol-defined risk group — are **not populated** on the
normalized Cases API diagnosis entity. They are present in open clinical
supplement spreadsheets (Section 11).

## 9. Follow-Up Structure

| Entity | 0 records | 1 record | >1 records | Min | Max |
| --- | --- | --- | --- | --- | --- |
| Diagnoses per case | 303 | 2189 | 0 | 0 | 1 |
| Follow-ups per case (any `follow_up_id`) | 341 | 0 | 2151 | 0 | 33 |
| Follow-ups with `days_to_follow_up` | 341 | 0 | 2151 | 0 | 3 |
| Treatments per case | 341 | 0 | 2151 | 0 | 5 |

There is no case with exactly one follow-up record. Many `follow_up_id`
values are stub records without clinical fields (up to 33 IDs per case).
Usable timed follow-ups are 2–3 per case among the 2151 cases that have
them.

The future analytics table should be one row per patient for primary OS
analysis. Raw/staging schemas should keep diagnosis, follow-up, and
treatment as one-to-many tables. Do not flatten follow-ups to a single
arbitrary record during ingestion.

## 10. Treatment Data Availability

Treatment records exist for 2151 cases, nested under diagnosis, typically
several records per patient.

| Field | Available N | Notes |
| --- | --- | --- |
| `diagnoses.treatments.protocol_identifier` | 2151 | AAML1031 1115; AAML0531 798; AAML03P1 100; AAML0631 71; CCG2961 67. |
| `diagnoses.treatments.treatment_type` | 2151 | Stem Cell Transplantation, NOS (2151); Pharmaceutical Therapy, NOS (876). The GDC definition says this is not proof the treatment was given. |
| `diagnoses.treatments.treatment_or_therapy` | 2151 | yes / no / unknown across multiple records per case. |
| `diagnoses.treatments.therapeutic_agents` | 876 | Only `Gemtuzumab Ozogamicin` observed. |
| `diagnoses.treatments.days_to_treatment_start` | 0 | Timing relative to baseline **cannot** be determined from this field. |
| `diagnoses.treatments.days_to_treatment_end` | 0 | Unpopulated. |
| `diagnoses.treatments.treatment_outcome` | 2117 | Complete Response / Unknown. Post-baseline. |
| `diagnoses.treatments.timepoint_category` | 2151 | End of Treatment Course; First Complete Response. Post-baseline. |

Protocol identifier is a study-enrollment attribute and may be usable later
as a stratification or era variable, not as a biological exposure.

Stem-cell transplant, gemtuzumab, course-level response, and MRD (in
supplements) are post-baseline. Using them as ordinary baseline covariates
would invite immortal-time bias and time-varying-exposure problems. They
are not recommended as primary baseline predictors. This audit does not
perform causal analysis.

## 11. Open Clinical Supplement Files

The Files API returned **7** TARGET-AML files with `data_category = Clinical`.
All seven are `data_type = Clinical Supplement`, `data_format = XLSX`,
`access = open`. No controlled-access clinical files were queried for
download.

| file_id | file_name | access | file_size | associated project | n_associated_cases |
| --- | --- | --- | --- | --- | --- |
| `5f8b7137-c1e1-4191-aee5-a5ea55d32ca7` | TARGET_AML_ClinicalData_Validation_20230720.xlsx | open | 201188 | TARGET-AML | 626 |
| `68170d63-c297-4d93-a21b-7bb43b451a96` | TARGET_AML_ClinicalData_AML1031_20230720.xlsx | open | 290224 | TARGET-AML | 1069 |
| `129e5399-6892-4cb7-99a8-1406309a2e4d` | TARGET_AML_ClinicalData_LowDepthRNAseq_20230720.xlsx | open | 154424 | TARGET-AML | 449 |
| `e58771ff-8501-4100-9c0a-c6dfa7dfb503` | TARGET_AML_ClinicalData_Discovery_and_Validation_Tumor_Content_and_RIN_Supplement_20230720.xlsx | open | 27199 | TARGET-AML | 133 |
| `3bf97830-865d-4e66-aaf1-d5bac81f119a` | TARGET_AML_ClinicalData_Discovery_20230720.xlsx | open | 149626 | TARGET-AML | 465 |
| `52fd584b-9ca3-4f7e-bdd5-fd9dce3d630b` | TARGET_AML_CDE_20230524.xlsx | open | 27667 | TARGET-AML | 2181 |
| `727dbb38-32fc-4444-9db2-13c8eb427fa2` | TARGET_AML_ClinicalData_AAML1031_AAML0631_additionalCasesForSortedCellsAndCBExperiment_20230720.xlsx | open | 35422 | TARGET-AML | 89 |

Source URL pattern: `https://api.gdc.cancer.gov/data/{file_id}`. Checksums
matched the Files API `md5sum`. Downloads are stored under
`data/raw/gdc_open_clinical_supplements/` and are gitignored. They are
**not** the production ingestion source yet.

These supplements contain fields **not** exposed as populated Cases API
properties, including:

- Overall Survival Time in Days
- Event Free Survival Time in Days
- First Event
- WBC at Diagnosis
- Bone marrow leukemic blast percentage
- Peripheral blasts
- CNS disease
- Chloroma
- FAB Category
- Cytogenetic indicators (t(8;21), inv(16), MLL, monosomy 7, etc.)
- FLT3/ITD, FLT3 PM, NPM mutation, CEBPA mutation, WT1, c-Kit
- Risk group (CDE: High / Low / Standard, cytogenetics- and biomarker-defined)
- MRD at end of course 1/2 (post-baseline)
- SCT in 1st CR (post-baseline)
- Gemtuzumab ozogamicin treatment

`TARGET_AML_CDE_20230524.xlsx` is a data-element dictionary, not a
patient-level table. It defines supplement columns, including OS time as
days from diagnosis to last follow-up or death.

The clinical-data spreadsheets are cohort slices (Discovery, Validation,
AML1031, LowDepthRNAseq, additional sorted-cell cases), not one
non-overlapping table. Unique `TARGET USI` union across those clinical-data
files was **2144**, with overlaps (for example Discovery ∩ Validation = 111;
LowDepthRNAseq ∩ Validation = 363). Completeness of AML-specific fields
varies by file (FAB is nearly empty in the AML1031 file and populated in
Discovery/Validation).

## 12. Data Quality Concerns

- **303 cases** have no demographic and no diagnosis in the Cases API.
- **31 cases** have vital status Not Reported or Unknown; these must not be
  recoded as censored.
- Follow-up is one-to-many, including stub IDs and two clinically different
  timepoints (Last Contact vs first event).
- 156 zero `follow_ups.days_to_follow_up` values; timepoint of those zeros
  is not yet classified.
- `diagnoses.year_of_diagnosis` is mixed numeric/string.
- Cases API diagnosis fields that look AML-specific in the GDC mapping
  (`fab_morphology_code`, `eln_risk_classification`, `calgb_risk_group`)
  are empty for TARGET-AML.
- Primary diagnosis and morphology have **no variation**.
- Race and ethnicity include substantial Unknown / not reported codes.
- Observed age extends to 29 years; the scientific question specified
  children and adolescents.
- Open supplements overlap and are stratified by TARGET subcohort; they
  cannot be row-bound without a USI crosswalk and discordance check.
- Treatment start/end days are missing, so treatment timing is unclear.
- Project summary Clinical case_count (2181) is close to, but not identical
  to, Cases API diagnosis N (2189).

These issues are recorded, not “fixed.”

## 13. Can TARGET-AML Support Our Proposed Study?

**YES, WITH MODIFICATIONS**

Overall survival can be constructed for most TARGET-AML cases from the
public Cases API: 2158 of 2492 cases (86.6%) have Alive/Dead vital status
and a non-negative death or last-follow-up time, including 742 deaths.

A scientifically meaningful pediatric AML association study cannot rest on
the Cases API diagnosis table alone. That table does not populate risk
group, FAB, cytogenetics, FLT3, WBC, or other standard baseline disease
characteristics; `primary_diagnosis` is uniformly AML, NOS.

The public open clinical supplements do contain those baseline disease
fields, plus a precomputed OS time. Using them requires a later
reconciliation with the Cases API (identifiers, overlapping files, and
possible discordance in vital status or times). Genomic features remain
out of scope.

If Stage 2 cannot produce a documented, non-duplicative analysis table
from Cases API plus open supplements, the study would need to be narrowed
further or judged not supportable from public data alone.

## 14. Recommended Primary Endpoint Definition

**Proposed, not finalized.**

- Time origin: diagnosis (`index_date = Diagnosis`; `days_to_diagnosis = 0`
  when present).
- Event: 1 if `demographic.vital_status` is Dead; 0 if Alive.
- Exclusion from the OS risk set: missing, Unknown, or Not Reported vital
  status. These are not censored observations.
- Candidate time:
  - Dead: `demographic.days_to_death`
  - Alive: `diagnoses.days_to_last_follow_up`
  - Sensitivity: Last Contact `follow_ups.days_to_follow_up`, and/or
    supplement `Overall Survival Time in Days`

Unresolved before lock:

- Whether Last Contact, diagnosis last follow-up, and supplement OS time
  agree case-by-case
- How to handle zero follow-up times
- Whether first-event follow-up records must be ignored for OS
- Age eligibility (pediatric/adolescent vs observed 0–29 years)
- Whether 303 cases without clinical entities can ever be recovered from
  supplements

## 15. Candidate Baseline Covariates

Only variables actually found are listed.

### HIGH PRIORITY

| Variable | Why |
| --- | --- |
| `diagnoses.age_at_diagnosis` | Populated, baseline, clear GDC definition (days). |
| `demographic.sex_at_birth` | Populated, baseline. |
| Supplement `WBC at Diagnosis` | Standard AML baseline burden marker; not in Cases API. |
| Supplement `Risk group` | CDE-defined cytogenetic/biomarker risk (High/Low/Standard). Requires provenance review. |
| Supplement `FLT3/ITD positive?` | Standard AML molecular marker; well populated in inspected supplements. |
| Supplement cytogenetic indicators / FAB (where populated) | Clinically meaningful baseline disease biology; file-dependent completeness. |

### POSSIBLE

| Variable | Why |
| --- | --- |
| `demographic.race` | Available but substantial Unknown/not reported. |
| `demographic.ethnicity` | Available with the same missingness issue. |
| `diagnoses.year_of_diagnosis` | Era/calendar-time proxy. Mixed types. |
| `diagnoses.treatments.protocol_identifier` or supplement `Protocol` | Study/eligibility context, not a biological exposure. Possible stratifier. |
| `demographic.age_at_index` | Inferior duplicate of age at diagnosis. |
| Supplement CNS disease, chloroma, blast percentages, NPM, CEBPA | Present in supplements; missingness and coding need QA. |

### NOT RECOMMENDED

| Variable | Why |
| --- | --- |
| `diagnoses.primary_diagnosis`, `morphology` | No variation in this extract. |
| Cases API `fab_morphology_code`, `eln_risk_classification`, `calgb_risk_group` | Unpopulated. |
| `demographic.gender` | Not in current mapping. |
| SCT, gemtuzumab, treatment outcome, MRD, `first_event` as a covariate | Post-baseline. Immortal-time / time-varying issues. |
| Treatment type without `days_to_treatment_start` | Timing unknown. |

## 16. Proposed Analysis Cohort

Conceptual future cohort, not created:

- Project TARGET-AML
- Acute myeloid leukemia at the case/diagnosis level
- One row per `case_id` / TARGET USI after de-duplicating supplements
- Known Alive or Dead vital status
- Non-negative overall-survival time from a documented rule
- Age restriction still TBD (children/adolescents vs include older TARGET
  cases up to 29 years)
- Exclusions counted (no clinical entities; unknown vital status; missing
  time; duplicate USI; non-AML if any appear after supplement join)

Raw data will remain one-to-many. The analytics table will be built only
after identifier and time-field reconciliation.

## 17. Questions to Resolve Before Stage 2

1. Should the analysis population be restricted to age <18, a COG
   pediatric bound, or all TARGET-AML ages observed (0–29 years)?
2. Which OS time source is primary: Cases API diagnosis last follow-up,
   Last Contact follow-up, supplement OS days, or a documented hierarchy?
3. How should overlapping Discovery / Validation / AML1031 / other
   supplement files be de-duplicated?
4. Do Cases API vital status and times agree with supplement Vital Status
   and Overall Survival Time in Days?
5. What is the provenance of supplement `Risk group`, and is it a baseline
   (pre-treatment) classification?
6. How should Unknown/not reported race, ethnicity, and sex be handled in
   the SAP (explicit missingness, not silent recoding)?
7. Are the 303 Cases API cases without demographic/diagnosis recoverable
   from supplements?
8. Which follow-up zeros are Last Contact vs first event?
9. Is protocol a stratifier, an adjustment variable, or descriptive only?
10. Confirm that Stage 2 ingestion keeps follow-up and treatment as
    one-to-many tables and does not flatten them in `raw`.

No Kaplan–Meier estimates, Cox models, imputations, or power calculations
were performed in this stage.
