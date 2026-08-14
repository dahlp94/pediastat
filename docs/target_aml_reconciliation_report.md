# TARGET-AML Source Reconciliation Report

Stage: 2 — raw ingestion and clinical source reconciliation  
Ingestion date: 2026-08-14  
Stage 1 audit timestamp (source catalog): 2026-08-14T01:24:42Z  
This report does not define an analysis cohort, a final OS endpoint, or a locked age cutoff.

## 1. Objective

Build a reproducible ingestion layer for the verified TARGET-AML sources and quantify how the GDC Cases API and open clinical supplements agree, disagree, overlap, and differ.

Questions addressed:

1. Can every source record be traced back to its origin?
2. How do Cases API records join to supplement records?
3. Which supplement files overlap?
4. Which values conflict across sources?
5. Which source should be preferred for each future analysis concept?
6. Is there enough consistency to proceed toward a patient-level analysis cohort?

## 2. Sources Ingested

| source_id name | source_type | origin | access |
| --- | --- | --- | --- |
| `gdc_cases_api_target_aml` | `gdc_cases_api` | `https://api.gdc.cancer.gov/cases` | open |
| `supplement:TARGET_AML_ClinicalData_AML1031_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_ClinicalData_Validation_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_ClinicalData_Discovery_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_ClinicalData_LowDepthRNAseq_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_ClinicalData_AAML1031_AAML0631_additionalCasesForSortedCellsAndCBExperiment_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_ClinicalData_Discovery_and_Validation_Tumor_Content_and_RIN_Supplement_20230720.xlsx` | `clinical_supplement` | GDC files API / local XLSX | open |
| `supplement:TARGET_AML_CDE_20230524.xlsx` | `cde_dictionary` | GDC files API / local XLSX | open |

Workbooks were ingested separately. They were not concatenated.

## 3. Ingestion Provenance

Architecture:

```text
GDC Cases API  → raw.gdc_*       → staging.gdc_*
OPEN XLSX      → raw.supplement_* → staging.supplement_clinical_rows
                                    → reconciliation artifacts
                                    STOP (no analytics cohort)
```

Raw GDC design: selected typed join/QA columns plus the original entity JSON in `payload` JSONB. Nested follow-ups and treatments were not collapsed. Clinical transformations were not applied in `raw`.

Raw supplement design: one workbook, one sheet, one spreadsheet row. Original column names and cell values are stored in `cells` JSONB. Identifier columns are copied, not overwritten.

Every raw row has `source_id`. Reloads replace rows for that source inside a transaction (`DELETE` then `INSERT`). A second GDC load returned the same entity counts (2492 / 2189 / 2189 / 61746 / 9477) and did not double the tables.

Bootstrap: `python scripts/bootstrap_database.py --local-cluster` creates a project-local cluster under `.pgdata` (port 5433) and applies `sql/01`–`sql/06`.

## 4. GDC Entity Counts

| Entity | Raw rows | Notes |
| --- | --- | --- |
| cases | 2492 | One GDC case UUID per row |
| demographics | 2189 | 303 cases have no demographic entity |
| diagnoses | 2189 | Never more than one diagnosis per case in this extract |
| follow_ups | 61746 | Max 33 per case; 2151 cases have multiple follow-ups |
| treatments | 9477 | Max 5 per case; nested under diagnosis |

`submitter_id` is unique across 2492 cases. `join_barcode` (leading `TARGET-NN-TOKEN`) is unique for 2412 values. The difference is identifier-shape, not a load error; see section 6.

## 5. Supplement Workbook / Sheet Inventory

Patient-level sheets are those with a `TARGET USI` header.

| Workbook | Sheet | Rows | Patient-level |
| --- | --- | --- | --- |
| AML1031 | Clinical Data | 1069 | yes |
| AML1031 | Original File | 2 | no |
| Validation | Clinical Data | 627 | yes (626 non-null USIs) |
| Validation | Original File | 4 | no |
| Discovery | Clinical Data | 466 | yes (465 non-null USIs) |
| Discovery | Original File | 5 | no |
| LowDepthRNAseq | Clinical Data | 449 | yes |
| LowDepthRNAseq | Original File | 1 | no |
| additional sorted-cells | Sheet1 | 89 | yes (17 extended `-Unsorted` USIs) |
| Tumor content / RIN | Sample Submission | 133 | has TARGET USI, not a clinical-data table |
| Tumor content / RIN | Lists / Checkbox Status | 11 / 2 | no |
| CDE | Data Elements | 65 | dictionary, not patients |

Column profiles: `artifacts/ingestion_audit/supplement_schema_profiles.csv`. Sample patient identifiers are not stored there.

## 6. Identifier Quality

Normalization used **only for joins**, never written over the original value:

1. coerce to string
2. strip leading/trailing whitespace
3. uppercase
4. do **not** remove hyphens or suffixes

`normalized_identifier` is the trimmed uppercase original.  
`join_barcode` is the leading `TARGET-NN-TOKEN` when present, so `TARGET-20-PAYGWX-Unsorted` joins to `TARGET-20-PAYGWX`.

| Source | Records | Non-null IDs | Unique normalized | Duplicate normalized IDs | Notes |
| --- | --- | --- | --- | --- | --- |
| GDC cases | 2492 | 2492 | 2492 | 0 | 2385 canonical, 84 extended, 23 classified malformed by the strict regex; 98 case differences |
| AML1031 Clinical Data | 1069 | 1069 | 1069 | 0 | all canonical |
| Validation Clinical Data | 627 | 626 | 626 | 0 | one null USI row |
| Discovery Clinical Data | 466 | 465 | 465 | 0 | one null USI row |
| LowDepthRNAseq Clinical Data | 449 | 449 | 449 | 0 | all canonical |
| additional sorted-cells | 89 | 89 | 89 | 0 | 17 extended `-Unsorted` |

GDC `join_barcode` collisions (103 cases across 23 barcodes):

- 18 canonical six-character USIs covering 57 cases: biospecimen/aliquot suffixes of the same patient token (join-appropriate)
- 4 short `TARGET-20-D#` tokens covering 41 cases: experiment-like identifiers that are **not** the same patient
- 1 other experimental token covering 5 cases

Stage 3 must join supplements on canonical USI/`submitter_id` and must not treat short `D#` tokens as patient keys.

## 7. GDC vs Supplement Patient Overlap

Join key: `join_barcode`.

| Universe | Count |
| --- | --- |
| GDC unique join barcodes | 2412 |
| Supplement unique TARGET USIs (patient-level clinical sheets) | 2144 |
| Intersection | 2144 |
| GDC-only | 268 |
| Supplement-only | 0 |
| Percent of GDC join barcodes matched | 88.89% |
| Percent of supplement USIs matched | 100% |

Every open clinical-data USI is present in the Cases API. The 268 GDC-only barcodes include cases without an open clinical-data row and the experimental identifier shapes above.

Committed unmatched artifact: counts only (`unmatched_identifier_summary.csv`). Individual unmatched barcodes are in gitignored `data/interim/ingestion_audit/`.

## 8. Supplement-to-Supplement Overlap

Unique patients per patient-level clinical file (join barcode):

| File | Unique USIs |
| --- | --- |
| AML1031 | 1069 |
| Validation | 626 |
| Discovery | 465 |
| LowDepthRNAseq | 449 |
| additional sorted-cells | 89 |

Pairwise shared USIs (upper triangle):

|  | additional | AML1031 | Discovery | LowDepth | Validation |
| --- | ---: | ---: | ---: | ---: | ---: |
| additional | 89 | 0 | 1 | 0 | 0 |
| AML1031 |  | 1069 | 4 | 2 | 4 |
| Discovery |  |  | 465 | 110 | 111 |
| LowDepth |  |  |  | 449 | 363 |
| Validation |  |  |  |  | 626 |

Distribution of file membership:

| Files containing a patient | Patients |
| ---: | ---: |
| 1 | 1630 |
| 2 | 475 |
| 3 | 38 |
| 4 | 1 |
| 5 | 0 |

Union = 2144. AML1031 is largely disjoint from the Discovery/Validation/LowDepth cluster. No patient appears in all five clinical files. Files were not deduplicated.

## 9. Clinical Concept Mapping

Concepts were listed only when the column was observed. Name similarity was not treated as equivalence. CDE or GDC definitions were used where inspected.

Shared or source-specific concepts actually found:

- vital status (GDC `demographic.vital_status`; supplement `Vital Status`)
- OS time (GDC `days_to_death`, `days_to_last_follow_up`, `days_to_follow_up`; supplement `Overall Survival Time in Days`)
- age at diagnosis in days (both)
- sex / gender (`demographic.sex_at_birth` vs supplement `Gender` — CDE defines gender)
- race, ethnicity
- WBC at diagnosis (supplement only)
- risk group (supplement only)
- FLT3/ITD, NPM, CEBPA (supplement only)
- FAB category (supplement; nearly empty in AML1031)
- CNS disease, marrow/peripheral blasts (supplement)
- cytogenetic lesion flags and `Primary Cytogenetic Code` (supplement)

Full map with missingness: `artifacts/ingestion_audit/clinical_concept_source_map.csv`.

## 10. Baseline Covariate Availability

GDC Cases API remains insufficient for AML-specific baseline biology (FAB/ELN/CALGB empty; primary diagnosis is AML NOS only).

Supplement completeness (percent missing, including Unknown/N/A/blank as not observed):

| Concept | AML1031 | Validation | Discovery | LowDepth | additional |
| --- | ---: | ---: | ---: | ---: | ---: |
| WBC | 0.09 | 2.07 | 4.08 | 0.00 | 2.25 |
| Risk group | 0.84 | 3.99 | 8.58 | 2.67 | 84.27 |
| FLT3/ITD | 0.00 | 2.23 | 4.51 | 0.22 | 79.78 |
| NPM | 0.00 | 2.39 | 7.30 | 0.89 | 79.78 |
| CEBPA | 0.00 | 2.55 | 6.44 | 1.11 | 79.78 |
| FAB | 99.35 | 17.22 | 11.59 | 14.92 | 19.10 |
| CNS disease | 3.55 | 2.07 | 4.08 | 0.00 | 61.80 |

AML1031 is the most complete molecular/risk file and the least complete FAB file. The additional sorted-cells file is sparse for molecular markers.

Post-baseline fields (MRD, SCT in first CR, gemtuzumab, relapse sites) are present and must not be used as baseline covariates.

## 11. Cross-Supplement Discordance

Comparisons use overlapping patients only. No winner was selected.

High-agreement concepts among overlaps:

- age at diagnosis: 100% exact in every pair with shared patients
- WBC: 100% exact in every pair with shared patients
- FLT3/ITD: 100% among both-observed overlapping patients
- vital status: 100% except Discovery vs LowDepth (1 disagreement / 110)

Material disagreements:

- OS time, Discovery vs LowDepth: 69/110 exact (62.73%)
- OS time, LowDepth vs Validation: 172/363 exact (47.38%)
- OS time, AML1031 vs LowDepth: 0/2 exact (n is tiny)
- OS time, Discovery vs Validation: 111/111 exact
- risk group: 4 disagreements / 105 (Discovery vs LowDepth); 6 / 353 (LowDepth vs Validation)
- NPM: 3 / 105 and 6 / 361 in those same pairs
- Primary Cytogenetic Code: 6 / 103 and 12 / 349

Discovery and Validation agree with each other where they overlap. LowDepth disagrees with both on OS time. That pattern is a source-version problem, not random noise.

## 12. Overall-Survival Source Reconciliation

GDC candidate time used for QA only (not a locked endpoint): `days_to_death` if vital status is Dead; `diagnoses.days_to_last_follow_up` if Alive. Unknown / Not Reported are not treated as censored.

| Supplement | Shared patients | Vital-status agreement | OS-time exact agreement | Age agreement | Zero/negative OS times |
| --- | ---: | ---: | ---: | ---: | ---: |
| additional sorted-cells | 89 | 100% (89/89) | 100% | 100% | 0 / 0 |
| AML1031 | 1069 | 100% | 99.81% (1067/1069) | 100% | 0 / 0 |
| LowDepthRNAseq | 449 | 100% | 100% | 100% | 0 / 0 |
| Discovery | 465 | 99.78% (446/447 observed; 1 Dead vs Alive; 18 both missing) | 90.83% (406/447) | 100% | 0 / 0 |
| Validation | 626 | 100% of 614 observed (12 both missing) | 68.89% (423/614) | 100% | 0 / 0 |

GDC Last Contact follow-up days matched supplement OS time at the same rates as the GDC candidate time. Units are days in both sources. Time origin is not locked.

Validation OS times are not interchangeable with the GDC candidate. LowDepth OS times match GDC and therefore disagree with Validation. Stage 3 must keep these as competing candidate times, not silently pick the series that maximizes N.

Detailed patient-level OS mismatches are gitignored under `data/interim/ingestion_audit/`.

## 13. Missing-Value Encoding

Staging classes (raw values retained):

| Class | Examples |
| --- | --- |
| structurally_missing | null, blank |
| not_reported | Not Reported |
| unknown | Unknown, Unspecified, NA, N/A |
| not_applicable | Not Applicable |
| sentinel | −99, −999, −9999 |
| observed | including 0 |

`NA` / `N/A` are classified as **unknown**, not not-applicable, because spreadsheet N/A is ambiguous. Unknown vital status is not censoring.

Observed encodings in supplements include blank, `Unknown`, `N/A`, and structurally empty cytogenetic free-text. Inventory: `missing_value_token_inventory.csv` (tokens with n<5 omitted).

## 14. Important Data-Quality Problems

1. Open supplements overlap; concatenating them would duplicate patients.
2. OS time is discordant across Validation, LowDepth, Discovery, and the GDC candidate.
3. One Discovery vs GDC vital-status conflict (Dead vs Alive).
4. GDC `join_barcode` collapses experimental `TARGET-20-D#-*` cases that are not the same patient.
5. 17 additional-file USIs use a `-Unsorted` suffix; the suffix is retained on `normalized_identifier`.
6. Discovery and Validation each have one spreadsheet row with a null TARGET USI.
7. 303 GDC cases lack demographic and diagnosis entities.
8. 31 diagnosis rows lack age; 334 of 2492 cases lack usable GDC age-at-diagnosis.
9. AML1031 FAB is almost entirely missing; additional-file FLT3/NPM/CEBPA/risk are mostly Unknown.
10. Follow-up entities remain one-to-many (stubs plus Last Contact plus first-event times).

## 15. Recommended Source Precedence

Recommendations only. Not implemented as a canonical patient table.

| Concept | Candidate sources | Recommended source | Reason | Confidence |
| --- | --- | --- | --- | --- |
| Patient identifier | GDC `submitter_id`; supplement `TARGET USI` | GDC `case_id` internally; canonical USI for joins | UUID is unique; USI is the crosswalk. Do not join on short `D#` tokens | high |
| Vital status | GDC `demographic.vital_status`; supplement `Vital Status` | GDC `demographic.vital_status` | Direct GDC field; near-complete agreement with supplements; keep Unknown/Not Reported separate | high |
| OS time | GDC death / last follow-up / Last Contact; supplement OS days | **unresolved** | Validation vs GDC 68.89% exact; LowDepth vs Validation 47.38% exact | n/a |
| Age at diagnosis | GDC `diagnoses.age_at_diagnosis`; supplement days | GDC `diagnoses.age_at_diagnosis` | 100% exact agreement in overlap; GDC unit is days | high |
| Sex | GDC `sex_at_birth`; supplement `Gender` | GDC `sex_at_birth` | Values matched after case-fold, but CDE defines Gender, not sex at birth | moderate |
| Race / ethnicity | GDC demographic; supplement | GDC demographic | GDC coding is the Cases API standard; unknown remains explicit | moderate |
| WBC | supplements only | AML1031 where present, else other clinical-data files | Not in Cases API; 100% agreement in overlaps; AML1031 most complete | high |
| Risk group | supplements only | AML1031 where present; otherwise Discovery/Validation over LowDepth when they conflict | AML1031 nearly complete; small LowDepth disagreements | moderate |
| FLT3/ITD, NPM, CEBPA | supplements only | AML1031 where present | Complete in AML1031; high Unknown in additional file; overlaps mostly agree | high |
| FAB | supplements only | Discovery/Validation/LowDepth, not AML1031 | AML1031 99.35% missing | high |
| Cytogenetics | lesion flags + primary code in supplements | retain flags as separate fields; do not auto-compose | pairwise code disagreements exist; flags are CDE-defined | moderate |
| CNS disease | supplements only | AML1031 / Validation / LowDepth where observed | additional file mostly Unknown | moderate |
| Protocol | GDC treatments `protocol_identifier`; supplement `Protocol` | GDC protocol as stratifier only | not a biological exposure | moderate |

## 16. Implications for the Statistical Analysis Plan

- The study can proceed to cohort definition, but OS time and age eligibility remain unlocked.
- AML-specific covariates must come from supplements, with file-aware precedence rather than concatenation.
- Unknown/Not Reported vital status stays a distinct exclusion or missingness class, not censoring.
- Treatment, MRD, and SCT remain ineligible as baseline covariates.
- Sample size for a pediatric-restricted cohort is smaller than 2492 and depends on the age rule (section 19 of the Stage 2 task / section below).

## 17. Is the Dataset Ready for Cohort Construction?

**YES, WITH CONDITIONS**

Conditions:

1. Stage 3 must lock an OS time rule using the discordance evidence, not by maximizing N.
2. Stage 3 must lock an age-eligibility rule with a scientific rationale for “children and adolescents.”
3. Stage 3 must specify supplement de-duplication / precedence per concept.
4. Stage 3 must define handling of the 303 GDC cases without demographic/diagnosis entities and the 268 GDC-only barcodes.
5. No analytics cohort is created in Stage 2.

## 18. Required Decisions Before Stage 3

1. Age cutoff: `<18`, `≤18`, `≤21`, or include 22–29 with stratified reporting?
2. OS event indicator: GDC vital status vs supplement Vital Status vs require both?
3. OS time precedence among GDC death time, GDC last follow-up, GDC Last Contact, and each supplement OS column.
4. Whether cases with Unknown/Not Reported vital status are excluded or retained as a missingness class (they must not be censored).
5. Time origin: diagnosis vs other index date.
6. Which supplement file wins for WBC, risk, FLT3, NPM, CEBPA, FAB, cytogenetics, CNS when patients appear in more than one file.
7. Whether `-Unsorted` and other suffix barcodes are the same analysis person as the canonical USI.
8. Whether experimental `TARGET-20-D#-*` GDC cases are eligible.
9. Whether the 303 API cases without nested clinical entities are ineligible.
10. Final exclusion list and analysis N after the above are locked.
