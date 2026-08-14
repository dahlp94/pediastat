# Stage 4 analysis extract

The descriptive analysis reads the frozen Stage 3 tables. It does not
reimplement patient identity, age eligibility, OS event, or OS time.

## Database view

`sql/08_create_stage4_extract_view.sql` creates:

`analytics.stage4_primary_cohort_extract`

The view is a wide join of:

- `analytics.primary_os_cohort` (one row per eligible analysis person)
- `analytics.baseline_covariates_reconciled` (long, concept-level)

Join key: `analysis_person_id`.

## Query used by R

R loads the view after applying the SQL file:

```sql
SELECT *
FROM analytics.stage4_primary_cohort_extract
ORDER BY analysis_person_id;
```

If the view is missing, `analysis/R/01_load_primary_cohort.R` applies the
SQL file and then runs the same SELECT.

Baseline provenance used for source-conflict QA is also read in long form:

```sql
SELECT b.*
FROM analytics.baseline_covariates_reconciled AS b
INNER JOIN analytics.primary_os_cohort AS c
    USING (analysis_person_id);
```

Identity accounting uses:

```sql
SELECT * FROM analytics.patient_identity_crosswalk;
SELECT * FROM analytics.cohort_eligibility;
```

## On-disk extract

A person-level copy may be written to:

`data/interim/stage4/primary_cohort_extract.rds`

That path is gitignored. Do not commit patient-level rows.

## Frozen checks before analysis

The loader stops if any of the following fail:

- 1978 rows
- unique `analysis_person_id`
- 695 events (`os_event = 1`)
- 1283 censored (`os_event = 0`)
- no age at diagnosis ≥ 18 years
- no missing `os_event` or `os_days`
- no negative `os_days`
