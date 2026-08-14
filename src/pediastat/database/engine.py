"""SQLAlchemy engine helpers. Credentials come from Settings, never hard-coded."""

from __future__ import annotations

from urllib.parse import quote_plus

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from pediastat.config import Settings, get_settings

SQL_FILES = (
    "01_create_schemas.sql",
    "02_create_ingestion_tables.sql",
    "03_create_source_registry.sql",
    "04_create_gdc_raw_tables.sql",
    "05_create_supplement_raw_tables.sql",
    "06_create_staging_tables.sql",
    "07_create_analytics_tables.sql",
    "08_create_stage4_extract_view.sql",
)


def sqlalchemy_url(settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    password = settings.postgres_password.get_secret_value()
    user = quote_plus(settings.postgres_user)
    host = settings.postgres_host
    port = settings.postgres_port
    database = quote_plus(settings.postgres_db)
    if password:
        secret = quote_plus(password)
        return f"postgresql+psycopg://{user}:{secret}@{host}:{port}/{database}"
    return f"postgresql+psycopg://{user}@{host}:{port}/{database}"


def create_db_engine(settings: Settings | None = None) -> Engine:
    return create_engine(sqlalchemy_url(settings), pool_pre_ping=True)


def apply_sql_file(engine: Engine, sql_text: str) -> None:
    """Apply a SQL file. PostgreSQL DDL is executed statement-by-statement."""
    statements = _split_sql(sql_text)
    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))


def _split_sql(sql_text: str) -> list[str]:
    statements: list[str] = []
    current: list[str] = []
    for line in sql_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") and not current:
            continue
        current.append(line)
        if stripped.endswith(";"):
            chunk = "\n".join(current).strip()
            if chunk:
                statements.append(chunk)
            current = []
    trailing = "\n".join(current).strip()
    if trailing:
        statements.append(trailing)
    return statements
