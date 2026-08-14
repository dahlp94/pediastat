# Primary Cohort Specification

Stage: 3 — study population, patient identity, and overall-survival endpoint  
Audience: collaborating investigator  
This document specifies who is in the primary analysis and how overall survival is defined. It does not report associations between baseline AML characteristics and survival.

## Scientific Population

Children and adolescents with acute myeloid leukemia in the public NCI GDC TARGET-AML project, with an unambiguous patient identifier and usable overall-survival information.

The scientific question is observational: which baseline patient and disease characteristics are associated with overall survival? Causal effects are not claimed.

TARGET-AML also contains young adults. They are not in the primary population. An age ≤21 sensitivity population is prespecified and has not been analyzed.

## Unit of Analysis

The unit of analysis is the **analysis person**, not the GDC case and not a biospecimen aliquot.

GDC `case_id` is retained as a source identifier. Multiple GDC cases may map to one analysis person when they are biospecimen-level extensions of the same TARGET USI.

## Patient Identity

A person is eligible for person-level analysis only if a canonical TARGET patient USI can be established:

- Pattern: `TARGET-20-XXXXXX` or `TARGET-21-XXXXXX`, where `XXXXXX` is six alphanumeric characters.
- `TARGET-21` barcodes that appear in the TARGET-AML GDC project and follow the same USI structure are treated as TARGET-AML persons.
- Extended identifiers such as `TARGET-20-XXXXXX-Unsorted` or sorted-cell suffixes are mapped to the canonical USI only when the suffix matches a documented biospecimen qualifier (Unsorted / Sorted-…). Prefix similarity alone is not sufficient.

The following are **not** analysis persons:

- Short experimental `TARGET-20-D#` tokens (experiment constructs such as GFP/mock/CBFA2T3-GLIS2 aliquots). These GDC cases are not collapsed to one patient, because they do not represent one unique patient.
- Other experimental constructs (cord-blood / endothelial transfer experiments).
- Cell-line names (HL60, Kasumi, MV4-11, MOLM-14, MUTZ-3, OCI-AML2, REH, TF-1, THP-1, and similar).
- `TARGET-00-` barcodes without a canonical patient USI.

If multiple GDC cases map to one USI, vital status, death time, last follow-up, age, sex, race, and ethnicity are compared. Compatible records are consolidated. Material conflicts exclude that person.

## Time Origin

Overall survival is measured from **initial pathologic diagnosis**.

Official GDC definitions:

- `diagnoses.days_to_last_follow_up`: interval from last follow-up to initial pathologic diagnosis, in days (caDSR 3008273).
- `demographic.days_to_death`: days from the GDC index date to death (caDSR 6154724).
- GDC policy stores clinical dates as intervals from initial pathologic diagnosis; events after diagnosis are positive.
- `diagnoses.age_at_diagnosis`: age at diagnosis in days since birth (caDSR 3225640).

In this extract, `index_date` is Diagnosis and `days_to_diagnosis` is 0 whenever those fields are populated among Alive/Dead cases. The two OS time fields therefore share a coherent origin at diagnosis. A small number of otherwise eligible cases lack `index_date`; they are retained with a QA flag because GDC policy still defines the index as diagnosis and, when Dead, death time equals last follow-up.

## Inclusion Criteria

A person is in the primary OS cohort if all of the following are true:

1. TARGET-AML analysis person with an unambiguous canonical USI.
2. GDC diagnosis entity available.
3. Age at diagnosis available from GDC `diagnoses.age_at_diagnosis`.
4. Age at diagnosis < 18 years, using years = days / 365.25.
5. GDC vital status is Alive or Dead.
6. Status-specific OS time is present and ≥ 0 days.

## Exclusion Criteria

- Ambiguous experimental identity, cell-line / non-patient identifier, or unresolved identity conflict.
- No diagnosis entity.
- Missing age at diagnosis.
- Age at diagnosis ≥ 18 years.
- Vital status Unknown, Not Reported, or structurally missing. These are not coded as censored.
- Dead without `days_to_death`, or Alive without `diagnoses.days_to_last_follow_up`.
- Negative OS time.

## Overall-Survival Event

Primary event source: GDC `demographic.vital_status`.

- Dead → event = 1
- Alive → event = 0

Supplement `Vital Status` is not required to define the event. It is retained for QA.

## Overall-Survival Time

Units: days (years = days / 365.25 for descriptive conversion only).

- If event = 1: `demographic.days_to_death`
- If event = 0: `diagnoses.days_to_last_follow_up`

Not used for the primary endpoint: follow-up first-event times, maximum arbitrary follow-up records, treatment dates, or supplement overall-survival days.

Zero times, if present, are reported and not automatically dropped. Negative times exclude the person. Implausibly large times are reported as QA flags and were not used to change the rule.

## Censoring

Alive persons are censored at diagnosis last follow-up. Unknown and Not Reported vital status are excluded, not censored.

## Age Eligibility

Primary: age at diagnosis < 18 years.

The cutoff follows the scientific question (“children and adolescents”). It was not chosen to maximize sample size. Age <18 and age ≤18 coincide in this extract because no one is exactly 18.0 years; the locked rule is still `< 18`.

## Handling Unknown Vital Status

Unknown, Not Reported, and missing vital status remain distinct missingness classes. They do not contribute person-time as censored observations in the primary OS cohort.

## Handling Duplicate / Extended TARGET Identifiers

Biospecimen-suffix GDC cases that share a canonical six-character USI and have compatible clinical data are one analysis person. The representative GDC case is chosen deterministically (clinical completeness, then `-Unsorted`, then canonical submitter, then `case_id`).

## Relationship to Clinical Supplements

Open clinical supplements supply AML-specific baseline covariates (WBC, risk group, FLT3/ITD, NPM, CEBPA, FAB, CNS disease, blasts, cytogenetic flags). They are not required for primary cohort entry. Supplement OS time is QA / future sensitivity information only and does not replace the GDC endpoint.

## Covariate Completeness

Primary cohort eligibility is not conditional on complete candidate covariates. A child with usable identity, age <18, and valid OS remains in the cohort if WBC, risk group, or molecular markers are missing.

## Sensitivity Populations

Prespecified, not analyzed in Stage 3:

- Age at diagnosis ≤ 21 years, otherwise the same OS and identity rules.
- No age restriction, otherwise the same identity, diagnosis, and OS rules.

No survival comparison across these populations has been performed.

## Cohort Attrition

See `artifacts/cohort_definition/cohort_attrition.csv`. Counts are produced by the locked rules above. They are not a substitute for the scientific definitions.

`analytics.cohort_eligibility` has **2453** rows. That is **2315** valid analysis persons plus **138** deliberately retained ineligible identity records (44 experimental `TARGET-20-D#` tokens, 6 other experimental constructs, and 88 non-patient identifiers). Those 138 rows are not valid analysis persons and are kept for auditability. The primary OS cohort remains **1978** rows in `analytics.primary_os_cohort`.

## Remaining Limitations

- Public GDC data do not include controlled-access TARGET clinical files.
- Some TARGET-AML GDC cases are experiments or cell lines, not patients.
- Validation supplement OS times remain discordant with GDC; that discordance is documented, not “fixed” by switching endpoints.
- Race and ethnicity have substantial Unknown / not reported codes.
- FAB is nearly empty in AML1031 and must use other files.
- The multivariable model is not locked. Missing-data methods for covariates are not locked.
- No survival model, Table 1, or outcome-stratified covariate screening was performed at this stage.
