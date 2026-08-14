-- Metadata for ingestion runs.
-- Requires PostgreSQL 13+ for the built-in gen_random_uuid() function.
-- This table records provenance only; it does not store clinical observations.

CREATE TABLE IF NOT EXISTS raw.ingestion_runs (
    ingestion_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_name TEXT NOT NULL,
    source_file TEXT,
    source_url TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL,
    records_received BIGINT,
    records_loaded BIGINT,
    notes TEXT,
    CONSTRAINT ingestion_runs_status_check
        CHECK (status IN ('started', 'succeeded', 'failed')),
    CONSTRAINT ingestion_runs_completed_after_started_check
        CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ingestion_runs_records_nonnegative_check
        CHECK (
            (records_received IS NULL OR records_received >= 0)
            AND (records_loaded IS NULL OR records_loaded >= 0)
        )
);

COMMENT ON TABLE raw.ingestion_runs IS
    'Provenance log for files loaded into the raw schema.';
COMMENT ON COLUMN raw.ingestion_runs.ingestion_run_id IS
    'Unique identifier for a single ingestion attempt.';
COMMENT ON COLUMN raw.ingestion_runs.source_name IS
    'Logical name of the data source (for example, a program or extract).';
COMMENT ON COLUMN raw.ingestion_runs.source_file IS
    'Local path or filename of the ingested file, when applicable.';
COMMENT ON COLUMN raw.ingestion_runs.source_url IS
    'Remote location of the source extract, when applicable.';
COMMENT ON COLUMN raw.ingestion_runs.status IS
    'started, succeeded, or failed.';
COMMENT ON COLUMN raw.ingestion_runs.records_received IS
    'Row count observed in the source file before loading, if known.';
COMMENT ON COLUMN raw.ingestion_runs.records_loaded IS
    'Row count written to the raw schema, if known.';
