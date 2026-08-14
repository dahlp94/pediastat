# Baseline Covariate Source Rules

Stage: 3  
Status: locked for future covariate construction; not used to define the primary OS cohort.

These rules specify how AML baseline concepts will be taken from overlapping open clinical supplements. They were chosen from Stage 2 source quality, CDE definitions, and coding coherence. They were **not** chosen by inspecting associations with survival.

Primary cohort membership does not require any of these covariates to be observed.

## Evidence hierarchy

1. The concept definition is documented (CDE or GDC dictionary).
2. The field represents baseline status, not a post-baseline event.
3. The source uses internally coherent coding.
4. The source agrees with overlapping high-quality sources.
5. The source has useful completeness.

Completeness alone does not determine precedence. Values are never averaged. Categorical codes are never silently replaced. When overlapping observed values disagree, the precedence winner is stored and `conflict_flag` is set.

## Shared missingness handling

Raw tokens are retained. Staging/analytics missingness classes remain:

- structurally missing
- not reported
- unknown (includes spreadsheet `NA` / `N/A`)
- not applicable
- sentinel
- observed (including 0)

Unknown is not recoded as a reference level for modeling at this stage.

## File families

| Family | Workbook |
| --- | --- |
| AML1031 | `TARGET_AML_ClinicalData_AML1031_20230720.xlsx` |
| Discovery | `TARGET_AML_ClinicalData_Discovery_20230720.xlsx` |
| Validation | `TARGET_AML_ClinicalData_Validation_20230720.xlsx` |
| LowDepth | `TARGET_AML_ClinicalData_LowDepthRNAseq_20230720.xlsx` |
| additional | additional sorted-cells / CB experiment workbook |

The CDE workbook and the tumor-content/RIN workbook are not covariate sources.

---

## Age at diagnosis

- Analytical concept: `age_at_diagnosis_days` / `age_at_diagnosis_years`
- Eligible sources: GDC `diagnoses.age_at_diagnosis`; supplement `Age at Diagnosis in Days`
- Precedence: GDC only for analysis and eligibility
- Units: days; years = days / 365.25
- Harmonization: none; GDC unit is already days
- Conflict handling: Stage 2 overlap was 100% exact; supplement age is QA only
- Missingness: missing age excludes a person from the primary OS cohort because age is an eligibility variable, not because it is a model covariate
- Rationale: official GDC definition is age at diagnosis in days since birth; concordance with supplements is complete where both are observed

## Sex at birth

- Analytical concept: `sex_at_birth`
- Eligible sources: GDC `demographic.sex_at_birth`; supplement `Gender`
- Precedence: GDC
- Coding: male / female / unknown (GDC)
- Conflict handling: supplement Gender is not substituted; CDE defines Gender, not sex at birth
- Missingness: unknown remains unknown; does not exclude from the primary cohort
- Rationale: GDC field matches the scientific concept more closely than the CDE Gender column

## Race

- Analytical concept: `race`
- Eligible sources: GDC `demographic.race`; supplement `Race`
- Precedence: GDC
- Conflict handling: GDC retained; supplement is QA
- Missingness: Unknown / not reported remain explicit
- Rationale: GDC coding is the Cases API standard; missingness is material

## Ethnicity

- Analytical concept: `ethnicity`
- Eligible sources: GDC `demographic.ethnicity`; supplement `Ethnicity`
- Precedence: GDC
- Missingness: Unknown / not reported remain explicit
- Rationale: same as race

## WBC at diagnosis

- Analytical concept: `wbc_at_diagnosis`
- Source field: `WBC at Diagnosis`
- Eligible files: AML1031, Discovery, Validation, LowDepth, additional
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Units: x10^3/mcL (CDE)
- Coding harmonization: numeric; do not round across sources
- Conflict handling: precedence winner; `conflict_flag` if observed values differ
- Missingness: not required for cohort entry; do not impute in Stage 3
- Rationale: not on the Cases API; 100% overlap agreement; AML1031 is the most complete high-quality file. Completeness is supporting evidence, not the sole reason.

## Risk group

- Analytical concept: `risk_group`
- Source field: `Risk group`
- Eligible files: same five clinical-data files
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Coding: High Risk / Low Risk / Standard Risk (CDE)
- Conflict handling: precedence winner; flag disagreements (known LowDepth disagreements in Stage 2)
- Missingness: does not exclude from the primary cohort
- Rationale: cytogenetics- and biomarker-defined AML risk; AML1031 nearly complete; Discovery/Validation preferred over LowDepth when they conflict

## FLT3/ITD

- Analytical concept: `flt3_itd`
- Source field: `FLT3/ITD positive?`
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Coding: Yes / No / Unknown
- Conflict handling: precedence winner; flag disagreements
- Rationale: CDE-defined baseline molecular marker; complete in AML1031; overlaps mostly agree

## NPM mutation

- Analytical concept: `npm`
- Source field: `NPM mutation`
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Conflict handling: precedence winner; flag disagreements
- Rationale: baseline molecular marker; complete in AML1031

## CEBPA mutation

- Analytical concept: `cebpa`
- Source field: `CEBPA mutation`
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Conflict handling: precedence winner; flag disagreements
- Rationale: baseline molecular marker; complete in AML1031

## FAB category

- Analytical concept: `fab`
- Source field: `FAB Category`
- Precedence: Discovery > Validation > LowDepth > additional > AML1031
- Coding: M0–M7 and related labels
- Conflict handling: precedence winner; flag disagreements
- Rationale: AML1031 is 99.35% missing for FAB, so completeness would misleadingly prefer empty data if used alone. Discovery/Validation/LowDepth are the supported sources.

## CNS disease

- Analytical concept: `cns_disease`
- Source field: `CNS disease`
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Missingness: additional file is mostly Unknown
- Rationale: baseline CNS involvement; additional file is sparse

## Marrow blast percentage

- Analytical concept: `marrow_blasts`
- Source field: `Bone marrow leukemic blast percentage (%)`
- Units: percent
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Conflict handling: precedence winner; flag numeric disagreements
- Rationale: CDE-defined baseline burden measure; modest missingness across files

## Peripheral blast percentage

- Analytical concept: `peripheral_blasts`
- Source field: `Peripheral blasts (%)`
- Units: percent
- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Rationale: baseline burden measure; not used as a cohort gate

## Cytogenetic lesion indicators

Concepts: `cytogenetics_t821` (`t(8;21)`), `cytogenetics_inv16` (`inv(16)`), `cytogenetics_mll` (`MLL`), `cytogenetics_monosomy7` (`monosomy 7`).

- Precedence: AML1031 > Discovery > Validation > LowDepth > additional
- Coding: Yes / No / Unknown where used
- Conflict handling: flags retained as separate fields; do not auto-compose a karyotype
- Rationale: CDE-defined lesion indicators; collapsing them would hide source disagreements

## Primary cytogenetic classification

- Analytical concept: `primary_cytogenetic_code`
- Source field: `Primary Cytogenetic Code`
- Precedence: Discovery > Validation > AML1031 > LowDepth > additional
- Conflict handling: precedence winner; flag disagreements
- Rationale: Stage 2 found pairwise code disagreements, especially involving LowDepth. The summary code is not assumed equivalent to lesion flags. Classified **NEEDS REVIEW** before any primary model uses it.

## Explicitly not baseline covariates

Protocol identifier may be a stratifier later. MRD, SCT in first CR, gemtuzumab, first event, relapse sites, and treatment outcome are post-baseline and remain excluded from ordinary baseline covariate construction.
