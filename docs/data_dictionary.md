# Data Dictionary

This dictionary records fields **verified during the Stage 1 TARGET-AML
source audit** (audit timestamp 2026-08-14T01:24:42Z). It is not the final
analytics data dictionary. Availability counts are specific to that GDC
release and must be re-checked after ingestion.

Missingness is case-level unless noted. "GDC missing-like codes" include
values such as unknown / not reported that are present but not usable as
analysis categories without an explicit rule.

Analysis roles are provisional:

- primary endpoint / secondary endpoint / covariate of interest /
  adjustment covariate / descriptive only / excluded / uncertain

---

## A. GDC Cases API fields

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

## B. Open clinical supplement columns (not ingested)

Observed in open TARGET-AML Clinical Supplement XLSX files. Definitions
below are from `TARGET_AML_CDE_20230524.xlsx` where available. These are
**not** yet analysis-ready: files overlap, and they have not been joined to
`case_id`.

| Variable | Source Field | Source Entity | Type | Definition | Units / Levels | Missingness | Analysis Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TARGET USI | `TARGET USI` | clinical supplement | string | TARGET barcode. | TARGET-20-… | Present on inspected clinical-data rows | Identifier (join to `submitter_id`) |
| OS time | `Overall Survival Time in Days` | clinical supplement | numeric | CDE: days after diagnosis to last follow-up or death. | days | Populated on most clinical-data rows inspected | Uncertain — candidate OS time pending concordance with Cases API |
| Vital status | `Vital Status` | clinical supplement | categorical | CDE: Alive / Dead / Unknown / Unspecified. | Alive; Dead (Unknown/Unspecified permitted) | Mostly populated in inspected files | Uncertain — pending concordance |
| Age at diagnosis | `Age at Diagnosis in Days` | clinical supplement | numeric | CDE: age in days at diagnosis (min 1, max 15000). | days | Mostly populated | Uncertain — pending concordance with `diagnoses.age_at_diagnosis` |
| WBC | `WBC at Diagnosis` | clinical supplement | numeric | CDE: absolute peripheral WBC (x10^3/mcL). | x10^3/mcL | Nearly complete in inspected files | Covariate of interest (after ingestion QA) |
| Risk group | `Risk group` | clinical supplement | categorical | CDE: cytogenetics- and biomarker-defined AML risk. | High Risk; Low Risk; Standard Risk | High in most files; sparse completeness varies | Covariate of interest pending provenance review |
| FLT3/ITD | `FLT3/ITD positive?` | clinical supplement | categorical | CDE: FLT3 internal tandem duplication indicator. | Yes; No; Unknown | High in inspected files | Covariate of interest (after ingestion QA) |
| FAB | `FAB Category` | clinical supplement | categorical | CDE: French-American-British morphology code. | M0–M7 and related labels | File-dependent (near-empty in AML1031 file) | Possible; completeness varies by file |
| First event | `First Event` | clinical supplement | categorical | CDE: endpoint event type. | Censored; Death; Relapse; Induction Failure; etc. | Mostly populated | Secondary / EFS; not baseline |
| MRD course 1 | `MRD at end of course 1` | clinical supplement | categorical | Residual disease after first course. | Yes; No | File-dependent | Excluded as baseline (post-baseline) |
| SCT in 1st CR | `SCT in 1st CR` | clinical supplement | categorical | Stem cell transplant during first CR. | Yes; No; Unknown | Mostly populated | Excluded as baseline (post-baseline / immortal time) |
