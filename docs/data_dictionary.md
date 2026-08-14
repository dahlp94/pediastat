# Data Dictionary

This dictionary records fields verified in the Stage 1 TARGET-AML source
audit and ingested in Stage 2. It is **not** the final analytics data
dictionary. Availability counts are release-specific.

Stage 2 source-precedence recommendations are documented in
`docs/target_aml_reconciliation_report.md` section 15. They are not
implemented as a merged patient table.

Missingness classes in staging: structurally_missing, not_reported,
unknown, not_applicable, sentinel, observed. Unknown/Not Reported vital
status is not censoring.

Proposed future analytics names, if shown, are labeled **PROPOSED**.

Analysis roles: primary endpoint / secondary endpoint / covariate of
interest / adjustment covariate / descriptive only / excluded / uncertain.


---

## A. GDC Cases API fields

Ingested to `raw.gdc_*` / `staging.gdc_*`. Missingness below is the Stage 1
case-level audit (denominator 2492) unless noted. Stage 2 load counts:
2492 cases, 2189 demographics, 2189 diagnoses, 61746 follow-ups, 9477
treatments.

| Variable | Source Field | Source Entity | Type | Definition | Units / Levels | Missingness | Analysis Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GDC case UUID | `case_id` | case | keyword | GDC identifier for the case. | UUID | 0 / 2492 missing | Identifier (stable internal key) |
| TARGET barcode | `submitter_id` | case | keyword | Project-specific identifier (TARGET USI analog). | e.g. TARGET-20-XXXXXX | 0 / 2492 missing | Identifier (join to supplements) |
| Project | `project.project_id` | project | keyword | GDC project identifier. | TARGET-AML | 0 / 2492 missing | Identifier |
| Disease type | `disease_type` | case | keyword | WHO ICD-O disease category. | Myeloid Leukemias; Not Applicable | 70 Not Applicable | Descriptive only; interpretation of Not Applicable uncertain |
| Primary site | `primary_site` | case | keyword | WHO ICD-O primary site grouping. | Hematopoietic and reticuloendothelial systems; Unknown | 1 null; 69 Unknown | Descriptive only |
| Index date | `index_date` | case | keyword | Anchor date for day offsets. | Diagnosis (n=2181) | 311 / 2492 (12.48%) | Uncertain — supports diagnosis as time origin when present |
| Vital status | `demographic.vital_status` | demographic | keyword | Survival state of the person registered on the protocol. | Alive; Dead; Not Reported; Unknown | 303 null (12.16%); 31 Not Reported/Unknown | Primary endpoint (event indicator). Do not treat Unknown/Not Reported as censored. |
| Days to death | `demographic.days_to_death` | demographic | long | Days between index date and date of death. | days; observed 1 to 3243 | 1750 / 2492; 0 among Dead | Primary endpoint (event time if Dead) |
| Age at index | `demographic.age_at_index` | demographic | long | Age in years on the index/anchor date. | years; 0 to 29 | 341 / 2492 (13.68%) | Possible; redundant with age at diagnosis |
| Days to birth | `demographic.days_to_birth` | demographic | long | Days between index date and birth (GDC uses a negative offset). | days; −10898 to −3 | 341 / 2492 (13.68%) | Descriptive / QA |
| Sex at birth | `demographic.sex_at_birth` | demographic | keyword | Textual description of sex at birth. | male; female; unknown | 303 null; 31 unknown | Covariate of interest / adjustment covariate |
| Race | `demographic.race` | demographic | keyword | OMB/Census-style race grouping. | white; black or african american; asian; american indian or alaska native; native hawaiian or other pacific islander; other; Unknown; not reported | 303 null; 246 Unknown/not reported among non-null | Possible; missingness must remain explicit |
| Ethnicity | `demographic.ethnicity` | demographic | keyword | Hispanic or Latino self-described grouping. | not hispanic or latino; hispanic or latino; Unknown; not reported | 303 null; 111 Unknown/not reported among non-null | Possible; missingness must remain explicit |
| Age at diagnosis | `diagnoses.age_at_diagnosis` | diagnosis | long | Age at diagnosis in days since birth. | days; 3 to 10898 | 334 / 2492 (13.40%) | Covariate of interest |
| Days to diagnosis | `diagnoses.days_to_diagnosis` | diagnosis | long | Days between index date and diagnosis. | days; all 0 when present | 311 / 2492 (12.48%) | QA / time-origin check |
| Days to last follow-up | `diagnoses.days_to_last_follow_up` | diagnosis | double | Interval from last follow-up to initial pathologic diagnosis, as days. | days; 1 to 4134 | 334 / 2492 (13.40%) | Primary endpoint (candidate censoring time) |
| Primary diagnosis | `diagnoses.primary_diagnosis` | diagnosis | keyword | WHO ICD-O histologic diagnosis. | Acute myeloid leukemia, NOS only | 303 / 2492 (12.16%) | Descriptive only (no variation) |
| Morphology | `diagnoses.morphology` | diagnosis | keyword | ICD-O morphology code. | 9861/3 only | 303 / 2492 (12.16%) | Descriptive only (no variation) |
| Tissue or organ of origin | `diagnoses.tissue_or_organ_of_origin` | diagnosis | keyword | Anatomic site of origin. | Bone marrow only | 303 / 2492 (12.16%) | Descriptive only |
| ICD-10 code | `diagnoses.icd_10_code` | diagnosis | keyword | ICD-10 disease code. | C92.0 | 311 / 2492 (12.48%) | Descriptive only |
| Year of diagnosis | `diagnoses.year_of_diagnosis` | diagnosis | long (mixed encoding) | Calendar year of initial pathologic diagnosis. | 1996–2017 | 337 / 2492 (13.52%) | Possible era covariate; mixed types |
| Tumor classification | `diagnoses.classification_of_tumor` | diagnosis | keyword | Kind of disease relative to a timepoint. | primary | 311 / 2492 (12.48%) | Descriptive only |
| Days to follow-up | `follow_ups.days_to_follow_up` | follow_up | long | Days from index to last follow-up appointment or contact. | days; 0 to 4134; multiple values per case | 341 / 2492 (13.68%) | Uncertain until timepoint is selected (Last Contact vs first event) |
| Follow-up timepoint | `follow_ups.timepoint_category` | follow_up | keyword | Point in the time continuum. | Last Contact; Follow-up | 341 / 2492 (13.68%) | Needed to interpret follow-up times; not a covariate |
| First event | `follow_ups.first_event` | follow_up | keyword | First event after initial treatment. | Censored; Relapse; Induction Failure; Death; Death without Remission; Second Malignant Neoplasm | 341 / 2492 (13.68%) | Secondary / EFS candidate; not a baseline covariate |
| Days to first event | `follow_ups.days_to_first_event` | follow_up | long | Days from index to first event. | days; 0 to 4108 | 341 / 2492 (13.68%) | Secondary / EFS candidate |
| Protocol identifier | `diagnoses.treatments.protocol_identifier` | treatment | keyword | Study protocol identifier. | AAML1031; AAML0531; AAML03P1; AAML0631; CCG2961 | 341 / 2492 (13.68%) | Possible stratifier; not a biological exposure |
| Treatment type | `diagnoses.treatments.treatment_type` | treatment | keyword | Type of treatment information in the record; not proof it was administered. | Stem Cell Transplantation, NOS; Pharmaceutical Therapy, NOS | 341 / 2492 | Excluded as baseline covariate (post-baseline / timing unknown) |
| Treatment administered | `diagnoses.treatments.treatment_or_therapy` | treatment | keyword | Whether the treatment_type was administered. | yes; no; unknown | 341 / 2492 | Excluded as baseline covariate |
| Therapeutic agents | `diagnoses.treatments.therapeutic_agents` | treatment | keyword | Agent(s) in a treatment regimen. | Gemtuzumab Ozogamicin | 1616 / 2492 (64.85%) | Excluded as baseline covariate (post-baseline; no start day) |

Fields confirmed in the GDC mapping but **unpopulated** for TARGET-AML in
this audit (not listed as analysis variables): `demographic.gender`,
`demographic.year_of_birth`, `demographic.year_of_death`,
`demographic.cause_of_death`, `diagnoses.fab_morphology_code`,
`diagnoses.eln_risk_classification`, `diagnoses.calgb_risk_group`,
`diagnoses.prior_malignancy`, `diagnoses.prior_treatment`,
`diagnoses.treatments.days_to_treatment_start`,
`diagnoses.treatments.days_to_treatment_end`.

---

## B. Open clinical supplement columns (ingested, not concatenated)

Observed in open TARGET-AML Clinical Supplement XLSX files and loaded to
`raw.supplement_rows` / `staging.supplement_clinical_rows`. Definitions
are from `TARGET_AML_CDE_20230524.xlsx` where available. Files overlap
(union 2144 USIs). Precedence is recommended, not applied.

Missingness percents below are Stage 2 observed (not-observed includes
Unknown/N/A/blank) for the named workbook.

| Analytical concept | Exact source field | Source workbook/entity | Original type | Units / coding | Missingness | Proposed future role | Source-precedence status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TARGET USI | `TARGET USI` | Clinical Data / Sheet1 | string | TARGET-20-… | 1 null row in Discovery; 1 in Validation | Identifier | Join on canonical USI; keep original | 17 additional-file IDs are `…-Unsorted` |
| Vital status | `Vital Status` | Clinical Data / Sheet1 | categorical | Alive; Dead; Unknown; Unspecified | 0–4% by file | Primary endpoint (event) | Recommended confirmation of GDC; not merged | 99.78–100% agreement with GDC where both observed |
| OS time | `Overall Survival Time in Days` | Clinical Data / Sheet1 | numeric | days | 0–4% by file | **PROPOSED** `os_time_days` — uncertain | Unresolved vs GDC and across files | Validation vs GDC 68.89% exact; LowDepth vs Validation 47.38% |
| Age at diagnosis | `Age at Diagnosis in Days` | Clinical Data / Sheet1 | numeric | days | 0–4% by file | Covariate of interest | GDC preferred; 100% overlap agreement | Same unit as GDC |
| Gender | `Gender` | Clinical Data / Sheet1 | categorical | Female; Male; Unknown | 0–4% by file | Uncertain vs sex at birth | Not declared equivalent to `sex_at_birth` despite 100% case-folded match | CDE definition is gender |
| Race | `Race` | Clinical Data / Sheet1 | categorical | | 6.7–14.6% | Possible | GDC demographic preferred | Coding may differ |
| Ethnicity | `Ethnicity` | Clinical Data / Sheet1 | categorical | | 2.9–7.5% | Possible | GDC demographic preferred | |
| WBC | `WBC at Diagnosis` | Clinical Data / Sheet1 | numeric | x10^3/mcL | 0–4% | Covariate of interest | AML1031 where present | 100% overlap agreement; absent from Cases API |
| Risk group | `Risk group` | Clinical Data / Sheet1 | categorical | High / Low / Standard Risk | 0.84% AML1031; 84% additional | Covariate of interest | AML1031 where present | Small LowDepth disagreements |
| FLT3/ITD | `FLT3/ITD positive?` | Clinical Data / Sheet1 | categorical | Yes; No; Unknown | 0% AML1031; 80% additional | Covariate of interest | AML1031 where present | Overlaps agree |
| NPM | `NPM mutation` | Clinical Data / Sheet1 | categorical | | 0% AML1031; 80% additional | Covariate of interest | AML1031 where present | Few LowDepth disagreements |
| CEBPA | `CEBPA mutation` | Clinical Data / Sheet1 | categorical | | 0% AML1031; 80% additional | Covariate of interest | AML1031 where present | |
| FAB | `FAB Category` | Clinical Data / Sheet1 | categorical | M0–M7 | 99.35% AML1031; 12–19% other files | Possible | Discovery/Validation/LowDepth; not AML1031 | File-dependent completeness |
| t(8;21) | `t(8;21)` | Clinical Data / Sheet1 | categorical | Yes; No; Unknown | file-dependent | Possible | Lesion flag; do not auto-compose | |
| inv(16) | `inv(16)` | Clinical Data / Sheet1 | categorical | Yes; No; Unknown | file-dependent | Possible | Lesion flag | |
| MLL | `MLL` | Clinical Data / Sheet1 | categorical | | file-dependent | Possible | Lesion flag | |
| Monosomy 7 | `monosomy 7` | Clinical Data / Sheet1 | categorical | | file-dependent | Possible | Lesion flag | |
| Primary cytogenetic code | `Primary Cytogenetic Code` | Clinical Data / Sheet1 | categorical | | file-dependent | Possible | Unresolved vs lesion flags | Pairwise disagreements exist |
| CNS disease | `CNS disease` | Clinical Data / Sheet1 | categorical | | 0–4% most files; 62% additional | Possible | AML1031/Validation/LowDepth | |
| Marrow blasts | `Bone marrow leukemic blast percentage (%)` | Clinical Data / Sheet1 | numeric | percent | file-dependent | Possible | Unresolved | |
| Peripheral blasts | `Peripheral blasts (%)` | Clinical Data / Sheet1 | numeric | percent | file-dependent | Possible | Unresolved | |
| First event | `First Event` | Clinical Data / Sheet1 | categorical | Censored; Death; Relapse; … | mostly populated | Secondary / EFS | Not baseline | |
| MRD course 1 | `MRD at end of course 1` | Clinical Data / Sheet1 | categorical | Yes; No | file-dependent | Excluded | n/a | Post-baseline |
| SCT in 1st CR | `SCT in 1st CR` | Clinical Data / Sheet1 | categorical | Yes; No; Unknown | mostly populated | Excluded | n/a | Post-baseline / immortal time |

GDC Cases API fields in section A keep their Stage 1 audit missingness
(2492-case denominator). After Stage 2 load: 2492 cases, 2189
demographics, 2189 diagnoses, 61746 follow-ups, 9477 treatments.
Recommended GDC fields for later analytics (not created): **PROPOSED**
`vital_status` ← `demographic.vital_status`; **PROPOSED**
`age_at_diagnosis_days` ← `diagnoses.age_at_diagnosis`; **PROPOSED**
`sex_at_birth` ← `demographic.sex_at_birth`. OS time has no proposed
canonical name because the source is unresolved.
