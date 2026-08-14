-- Separate storage layers for PediaStat.
-- raw: immutable source extracts as ingested
-- staging: cleaned copies after documented QA/QC transformations
-- analytics: analysis-ready cohort tables derived from staging
--
-- Clinical tables are not created here. Source-specific schemas will be
-- added only after the actual data files and documentation are inspected.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA raw IS
    'Immutable source data as ingested. Do not update or delete clinical rows in place.';
COMMENT ON SCHEMA staging IS
    'Cleaned data after documented QA/QC transformations from raw.';
COMMENT ON SCHEMA analytics IS
    'Analysis-ready cohort tables derived from staging.';
