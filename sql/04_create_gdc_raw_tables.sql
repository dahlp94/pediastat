-- Raw GDC Cases API entities.
-- Typed columns are join/QA fields observed in Stage 1. Full entity JSON is in payload.
-- Do not collapse follow-ups or treatments.

CREATE TABLE IF NOT EXISTS raw.gdc_cases (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    project_id TEXT,
    disease_type TEXT,
    primary_site TEXT,
    index_date TEXT,
    lost_to_followup TEXT,
    days_to_lost_to_followup DOUBLE PRECISION,
    payload JSONB NOT NULL,
    CONSTRAINT gdc_cases_unique UNIQUE (source_id, case_id)
);

CREATE TABLE IF NOT EXISTS raw.gdc_demographics (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    demographic_id TEXT,
    vital_status TEXT,
    days_to_death DOUBLE PRECISION,
    age_at_index DOUBLE PRECISION,
    days_to_birth DOUBLE PRECISION,
    sex_at_birth TEXT,
    race TEXT,
    ethnicity TEXT,
    year_of_birth DOUBLE PRECISION,
    year_of_death DOUBLE PRECISION,
    cause_of_death TEXT,
    age_is_obfuscated TEXT,
    payload JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.gdc_diagnoses (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    diagnosis_id TEXT,
    age_at_diagnosis DOUBLE PRECISION,
    days_to_diagnosis DOUBLE PRECISION,
    days_to_last_follow_up DOUBLE PRECISION,
    primary_diagnosis TEXT,
    morphology TEXT,
    tissue_or_organ_of_origin TEXT,
    site_of_resection_or_biopsy TEXT,
    year_of_diagnosis TEXT,
    icd_10_code TEXT,
    classification_of_tumor TEXT,
    diagnosis_is_primary_disease TEXT,
    payload JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.gdc_follow_ups (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
    case_id TEXT NOT NULL,
    submitter_id TEXT,
    submitter_id_normalized TEXT,
    join_barcode TEXT,
    follow_up_id TEXT,
    days_to_follow_up DOUBLE PRECISION,
    timepoint_category TEXT,
    first_event TEXT,
    days_to_first_event DOUBLE PRECISION,
    year_of_follow_up DOUBLE PRECISION,
    payload JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.gdc_treatments (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
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
    course_number DOUBLE PRECISION,
    payload JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS gdc_cases_join_barcode_idx
    ON raw.gdc_cases (join_barcode);
CREATE INDEX IF NOT EXISTS gdc_follow_ups_case_id_idx
    ON raw.gdc_follow_ups (case_id);
CREATE INDEX IF NOT EXISTS gdc_treatments_case_id_idx
    ON raw.gdc_treatments (case_id);

COMMENT ON TABLE raw.gdc_follow_ups IS
    'One row per GDC follow-up entity, including stub records that have only an id.';
COMMENT ON TABLE raw.gdc_treatments IS
    'One row per GDC treatment entity nested under a diagnosis.';
