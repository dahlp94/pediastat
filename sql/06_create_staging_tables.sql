-- Source-aware staging tables.
-- Types and missingness classes are standardized; sources are not merged.
-- Do not create analytics.patient_cohort here.

CREATE TABLE IF NOT EXISTS staging.gdc_cases (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    project_id TEXT,
    disease_type TEXT,
    primary_site TEXT,
    index_date TEXT,
    lost_to_followup TEXT,
    days_to_lost_to_followup DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS staging.gdc_demographics (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    demographic_id TEXT,
    vital_status_raw TEXT,
    vital_status_missing_class TEXT,
    vital_status_analysis_class TEXT,
    days_to_death DOUBLE PRECISION,
    age_at_index DOUBLE PRECISION,
    days_to_birth DOUBLE PRECISION,
    sex_at_birth_raw TEXT,
    sex_at_birth_missing_class TEXT,
    race_raw TEXT,
    race_missing_class TEXT,
    ethnicity_raw TEXT,
    ethnicity_missing_class TEXT
);

CREATE TABLE IF NOT EXISTS staging.gdc_diagnoses (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    diagnosis_id TEXT,
    age_at_diagnosis_days DOUBLE PRECISION,
    days_to_diagnosis DOUBLE PRECISION,
    days_to_last_follow_up DOUBLE PRECISION,
    primary_diagnosis TEXT,
    morphology TEXT,
    year_of_diagnosis TEXT
);

CREATE TABLE IF NOT EXISTS staging.gdc_follow_ups (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    follow_up_id TEXT,
    days_to_follow_up DOUBLE PRECISION,
    timepoint_category TEXT,
    first_event TEXT,
    days_to_first_event DOUBLE PRECISION,
    year_of_follow_up DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS staging.gdc_treatments (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    diagnosis_id TEXT,
    treatment_id TEXT,
    treatment_type TEXT,
    treatment_or_therapy TEXT,
    therapeutic_agents TEXT,
    protocol_identifier TEXT,
    days_to_treatment_start DOUBLE PRECISION,
    days_to_treatment_end DOUBLE PRECISION,
    timepoint_category TEXT,
    treatment_outcome TEXT,
    course_number DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS staging.supplement_clinical_rows (
    staging_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL,
    workbook_name TEXT NOT NULL,
    sheet_name TEXT NOT NULL,
    row_number INTEGER NOT NULL,
    original_identifier TEXT,
    normalized_identifier TEXT,
    join_barcode TEXT,
    identifier_shape TEXT,
    vital_status_raw TEXT,
    vital_status_missing_class TEXT,
    os_time_days DOUBLE PRECISION,
    os_time_missing_class TEXT,
    age_at_diagnosis_days DOUBLE PRECISION,
    sex_raw TEXT,
    race_raw TEXT,
    ethnicity_raw TEXT,
    wbc_raw TEXT,
    risk_group_raw TEXT,
    flt3_itd_raw TEXT,
    npm_raw TEXT,
    cebpa_raw TEXT,
    fab_raw TEXT,
    cns_disease_raw TEXT,
    marrow_blasts_raw TEXT,
    peripheral_blasts_raw TEXT,
    protocol_raw TEXT,
    first_event_raw TEXT,
    cells JSONB NOT NULL
);

COMMENT ON TABLE staging.supplement_clinical_rows IS
    'Source-aware supplement rows. Multiple workbooks may contain the same patient.';
