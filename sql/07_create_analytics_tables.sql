-- Stage 3 analytics tables: identity, eligibility, primary OS cohort,
-- and source-reconciled baseline covariates.
-- Constraints apply only to analytics-derived tables.

CREATE TABLE IF NOT EXISTS analytics.patient_identity_crosswalk (
    case_id TEXT PRIMARY KEY,
    submitter_id TEXT,
    original_identifier TEXT,
    normalized_identifier TEXT,
    join_barcode TEXT,
    analysis_person_id TEXT NOT NULL,
    identity_rule TEXT NOT NULL,
    identity_confidence TEXT NOT NULL,
    eligible_for_person_level_analysis BOOLEAN NOT NULL,
    exclusion_reason TEXT,
    n_gdc_cases_for_person INTEGER,
    is_representative_case BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS patient_identity_person_idx
    ON analytics.patient_identity_crosswalk (analysis_person_id);
CREATE INDEX IF NOT EXISTS patient_identity_join_barcode_idx
    ON analytics.patient_identity_crosswalk (join_barcode);

COMMENT ON TABLE analytics.patient_identity_crosswalk IS
    'GDC case identity mapped to analysis-person identity. Original identifiers are retained.';

CREATE TABLE IF NOT EXISTS analytics.cohort_eligibility (
    analysis_person_id TEXT PRIMARY KEY,
    representative_case_id TEXT,
    submitter_id TEXT,
    has_valid_identity BOOLEAN NOT NULL,
    has_diagnosis BOOLEAN NOT NULL,
    has_age BOOLEAN NOT NULL,
    age_eligible_lt18 BOOLEAN NOT NULL,
    age_eligible_le21 BOOLEAN NOT NULL,
    has_known_vital_status BOOLEAN NOT NULL,
    has_valid_os_time BOOLEAN NOT NULL,
    records_compatible BOOLEAN NOT NULL,
    identity_conflict BOOLEAN NOT NULL,
    primary_cohort_eligible BOOLEAN NOT NULL,
    sensitivity_le21_eligible BOOLEAN NOT NULL,
    sensitivity_unrestricted_age_eligible BOOLEAN NOT NULL,
    primary_exclusion_reason TEXT,
    all_exclusion_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
    age_at_diagnosis_days DOUBLE PRECISION,
    age_at_diagnosis_years DOUBLE PRECISION,
    vital_status TEXT,
    os_event SMALLINT,
    os_days DOUBLE PRECISION,
    CONSTRAINT cohort_eligibility_os_event_check
        CHECK (os_event IS NULL OR os_event IN (0, 1))
);

COMMENT ON TABLE analytics.cohort_eligibility IS
    'Person-level inclusion and exclusion flags. Includes ineligible persons.';

CREATE TABLE IF NOT EXISTS analytics.primary_os_cohort (
    analysis_person_id TEXT PRIMARY KEY,
    gdc_case_id TEXT NOT NULL,
    submitter_id TEXT,
    age_at_diagnosis_days DOUBLE PRECISION NOT NULL
        CHECK (age_at_diagnosis_days >= 0),
    age_at_diagnosis_years DOUBLE PRECISION NOT NULL
        CHECK (age_at_diagnosis_years >= 0),
    vital_status TEXT NOT NULL
        CHECK (vital_status IN ('Alive', 'Dead')),
    os_event SMALLINT NOT NULL
        CHECK (os_event IN (0, 1)),
    os_days DOUBLE PRECISION NOT NULL
        CHECK (os_days >= 0),
    os_years DOUBLE PRECISION NOT NULL
        CHECK (os_years >= 0),
    os_time_source TEXT NOT NULL,
    os_event_source TEXT NOT NULL,
    identity_rule TEXT,
    source_provenance TEXT,
    qa_flags JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE analytics.primary_os_cohort IS
    'Primary study population and overall-survival endpoint. One row per analysis person.';

CREATE TABLE IF NOT EXISTS analytics.baseline_covariates_reconciled (
    analysis_person_id TEXT NOT NULL,
    concept TEXT NOT NULL,
    value TEXT,
    source_workbook TEXT,
    source_column TEXT,
    source_kind TEXT NOT NULL,
    conflict_flag BOOLEAN NOT NULL DEFAULT FALSE,
    alternative_source_count INTEGER NOT NULL DEFAULT 0
        CHECK (alternative_source_count >= 0),
    missingness_class TEXT,
    units TEXT,
    PRIMARY KEY (analysis_person_id, concept)
);

COMMENT ON TABLE analytics.baseline_covariates_reconciled IS
    'Source-reconciled baseline concepts with provenance. Missing values are retained.';
