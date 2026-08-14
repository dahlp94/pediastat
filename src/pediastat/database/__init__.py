"""PostgreSQL access for raw, staging, and analytics schemas.

Raw source data are treated as immutable once ingested. Transformations
into staging and analytics layers will be recorded explicitly.
"""

from pediastat.database.engine import create_db_engine, sqlalchemy_url

__all__ = ["create_db_engine", "sqlalchemy_url"]
