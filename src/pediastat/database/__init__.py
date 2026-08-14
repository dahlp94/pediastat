"""PostgreSQL access for raw, staging, and analytics schemas.

Raw source data are treated as immutable once ingested. Transformations
into staging and analytics layers will be recorded explicitly.
"""
