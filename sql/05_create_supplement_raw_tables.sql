-- Raw open clinical supplements.
-- Each workbook remains identifiable. Rows are not concatenated into a master table.
-- Original column names and cell values are stored in cells JSONB.

CREATE TABLE IF NOT EXISTS raw.supplement_workbooks (
    workbook_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    workbook_name TEXT NOT NULL,
    source_file TEXT,
    source_file_id TEXT,
    checksum TEXT,
    n_sheets INTEGER,
    CONSTRAINT supplement_workbooks_source_unique UNIQUE (source_id)
);

CREATE TABLE IF NOT EXISTS raw.supplement_sheets (
    sheet_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    workbook_name TEXT NOT NULL,
    sheet_name TEXT NOT NULL,
    n_rows INTEGER,
    n_columns INTEGER,
    identifier_field TEXT,
    is_patient_level BOOLEAN NOT NULL DEFAULT FALSE,
    columns JSONB NOT NULL,
    CONSTRAINT supplement_sheets_unique UNIQUE (source_id, sheet_name)
);

CREATE TABLE IF NOT EXISTS raw.supplement_rows (
    raw_row_id BIGSERIAL PRIMARY KEY,
    source_id UUID NOT NULL REFERENCES raw.source_registry (source_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_runs (ingestion_run_id),
    workbook_name TEXT NOT NULL,
    sheet_name TEXT NOT NULL,
    row_number INTEGER NOT NULL,
    original_identifier TEXT,
    normalized_identifier TEXT,
    join_barcode TEXT,
    identifier_shape TEXT,
    cells JSONB NOT NULL,
    CONSTRAINT supplement_rows_unique UNIQUE (source_id, sheet_name, row_number)
);

CREATE INDEX IF NOT EXISTS supplement_rows_join_barcode_idx
    ON raw.supplement_rows (join_barcode);
CREATE INDEX IF NOT EXISTS supplement_rows_workbook_sheet_idx
    ON raw.supplement_rows (workbook_name, sheet_name);

COMMENT ON TABLE raw.supplement_rows IS
    'One row per spreadsheet record. cells preserves original column names and values.';
