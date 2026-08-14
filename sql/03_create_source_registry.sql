-- Source registry: every ingested dataset is traceable.
-- Requires PostgreSQL 13+ for gen_random_uuid().

CREATE TABLE IF NOT EXISTS raw.source_registry (
    source_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type TEXT NOT NULL,
    source_name TEXT NOT NULL,
    source_file TEXT,
    source_file_id TEXT,
    source_url TEXT,
    api_endpoint TEXT,
    project_id TEXT,
    access_level TEXT,
    checksum TEXT,
    downloaded_at TIMESTAMPTZ,
    ingested_at TIMESTAMPTZ,
    source_release_or_audit_date TEXT,
    row_count BIGINT,
    notes TEXT,
    CONSTRAINT source_registry_type_check
        CHECK (source_type IN ('gdc_cases_api', 'clinical_supplement', 'cde_dictionary')),
    CONSTRAINT source_registry_access_check
        CHECK (
            access_level IS NULL
            OR access_level IN ('open', 'controlled', 'unknown')
        ),
    CONSTRAINT source_registry_row_count_check
        CHECK (row_count IS NULL OR row_count >= 0),
    CONSTRAINT source_registry_name_unique UNIQUE (source_name)
);

COMMENT ON TABLE raw.source_registry IS
    'Catalog of ingested TARGET-AML sources. Raw clinical rows reference source_id.';

ALTER TABLE raw.ingestion_runs
    ADD COLUMN IF NOT EXISTS source_id UUID REFERENCES raw.source_registry (source_id);
