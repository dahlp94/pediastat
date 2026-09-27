"""Database, local PostgreSQL bootstrap, and ingestion persistence helpers."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus
from uuid import UUID, uuid4

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from pediastat.config import PROJECT_ROOT, Settings, get_settings
from pediastat.gdc import classify_vital_status
from pediastat.ingest import classify_missing

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

        if not stripped and not current:
            continue

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


DEFAULT_DATA_DIR = PROJECT_ROOT / ".pgdata"


DEFAULT_PORT = 5433


DEFAULT_USER = "pediastat"


DEFAULT_DB = "pediastat"


def _postgres_bin(name: str) -> str:
    env_dir = os.environ.get("POSTGRES_BIN")
    candidates = []
    if env_dir:
        candidates.append(Path(env_dir) / name)
    which = shutil.which(name)
    if which:
        candidates.append(Path(which))
    candidates.extend(
        [
            Path("/Library/PostgreSQL/18/bin") / name,
            Path("/Library/PostgreSQL/17/bin") / name,
            Path("/usr/local/opt/postgresql@18/bin") / name,
            Path("/opt/homebrew/opt/postgresql@18/bin") / name,
        ]
    )
    for path in candidates:
        if path.is_file():
            return str(path)
    msg = f"Could not find {name}. Install PostgreSQL or set POSTGRES_BIN."
    raise FileNotFoundError(msg)


def _ensure_trust_auth(data_dir: Path) -> None:
    """Keep the project-local cluster passwordless on localhost."""
    hba = data_dir / "pg_hba.conf"
    if not hba.exists():
        return

    marker = "# PediaStat local trust authentication"
    rules = (
        f"{marker}\n"
        "local   all   all                     trust\n"
        "host    all   all   127.0.0.1/32      trust\n"
        "host    all   all   ::1/128           trust\n"
    )

    current = hba.read_text(encoding="utf-8")
    if marker not in current:
        hba.write_text(rules + "\n" + current, encoding="utf-8")


def cluster_is_running(data_dir: Path = DEFAULT_DATA_DIR) -> bool:
    pg_ctl = _postgres_bin("pg_ctl")
    result = subprocess.run(
        [pg_ctl, "-D", str(data_dir), "status"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def bootstrap_cluster(
    data_dir: Path = DEFAULT_DATA_DIR,
    port: int = DEFAULT_PORT,
    user: str = DEFAULT_USER,
    database: str = DEFAULT_DB,
) -> Settings:
    """Initialize a local trust-auth cluster if needed and apply DDL."""
    data_dir.mkdir(parents=True, exist_ok=True)
    pg_ctl = _postgres_bin("pg_ctl")
    initdb = _postgres_bin("initdb")
    createdb = _postgres_bin("createdb")
    marker = data_dir / "PG_VERSION"
    if not marker.exists():
        init_cmd = [
            initdb,
            "-D",
            str(data_dir),
            "-U",
            user,
            "--auth-local=trust",
            "--auth-host=trust",
            "--encoding=UTF8",
        ]
        result = subprocess.run(
            [*init_cmd, "--locale=C"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            for child in list(data_dir.iterdir()):
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            subprocess.run(init_cmd, check=True)
        config = data_dir / "postgresql.conf"
        extra = (
            f"\nport = {port}\n"
            f"unix_socket_directories = '{data_dir}'\n"
            "listen_addresses = 'localhost'\n"
        )
        config.write_text(config.read_text(encoding="utf-8") + extra, encoding="utf-8")

    _ensure_trust_auth(data_dir)

    if not cluster_is_running(data_dir):
        log_file = data_dir / "pg.log"
        subprocess.run(
            [
                pg_ctl,
                "-D",
                str(data_dir),
                "-l",
                str(log_file),
                "start",
            ],
            check=True,
        )
        time.sleep(1.0)
    else:
        subprocess.run(
            [pg_ctl, "-D", str(data_dir), "reload"],
            check=True,
        )
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": "localhost",
            "PGPORT": str(port),
            "PGUSER": user,
        }
    )
    exists = subprocess.run(
        [
            _postgres_bin("psql"),
            "-h",
            "localhost",
            "-p",
            str(port),
            "-U",
            user,
            "-d",
            "postgres",
            "-tAc",
            f"SELECT 1 FROM pg_database WHERE datname = '{database}'",
        ],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    if exists.stdout.strip() != "1":
        subprocess.run(
            [
                createdb,
                "-h",
                "localhost",
                "-p",
                str(port),
                "-U",
                user,
                database,
            ],
            check=True,
            env=env,
        )
    settings = Settings(
        postgres_host="localhost",
        postgres_port=port,
        postgres_db=database,
        postgres_user=user,
        postgres_password="",
        _env_file=None,
    )
    engine = create_db_engine(settings)
    sql_dir = PROJECT_ROOT / "sql"
    for name in SQL_FILES:
        apply_sql_file(engine, (sql_dir / name).read_text(encoding="utf-8"))
    return settings


def utc_now() -> datetime:
    return datetime.now(UTC)


def _json(value: Any) -> str:
    return json.dumps(value, default=str)


def upsert_source(
    engine: Engine,
    *,
    source_name: str,
    source_type: str,
    source_file: str | None = None,
    source_file_id: str | None = None,
    source_url: str | None = None,
    api_endpoint: str | None = None,
    project_id: str | None = None,
    access_level: str | None = None,
    checksum: str | None = None,
    downloaded_at: datetime | None = None,
    source_release_or_audit_date: str | None = None,
    row_count: int | None = None,
    notes: str | None = None,
) -> UUID:
    sql = text(
        """
        INSERT INTO raw.source_registry (
            source_name, source_type, source_file, source_file_id, source_url,
            api_endpoint, project_id, access_level, checksum, downloaded_at,
            ingested_at, source_release_or_audit_date, row_count, notes
        ) VALUES (
            :source_name, :source_type, :source_file, :source_file_id, :source_url,
            :api_endpoint, :project_id, :access_level, :checksum, :downloaded_at,
            :ingested_at, :source_release_or_audit_date, :row_count, :notes
        )
        ON CONFLICT (source_name) DO UPDATE SET
            source_file = EXCLUDED.source_file,
            source_file_id = EXCLUDED.source_file_id,
            source_url = EXCLUDED.source_url,
            api_endpoint = EXCLUDED.api_endpoint,
            checksum = EXCLUDED.checksum,
            downloaded_at = EXCLUDED.downloaded_at,
            ingested_at = EXCLUDED.ingested_at,
            source_release_or_audit_date = EXCLUDED.source_release_or_audit_date,
            row_count = EXCLUDED.row_count,
            notes = EXCLUDED.notes
        RETURNING source_id
        """
    )
    with engine.begin() as connection:
        result = connection.execute(
            sql,
            {
                "source_name": source_name,
                "source_type": source_type,
                "source_file": source_file,
                "source_file_id": source_file_id,
                "source_url": source_url,
                "api_endpoint": api_endpoint,
                "project_id": project_id,
                "access_level": access_level,
                "checksum": checksum,
                "downloaded_at": downloaded_at,
                "ingested_at": utc_now(),
                "source_release_or_audit_date": source_release_or_audit_date,
                "row_count": row_count,
                "notes": notes,
            },
        )
        return result.scalar_one()


def start_ingestion_run(
    engine: Engine,
    *,
    source_id: UUID,
    source_name: str,
    source_file: str | None,
    source_url: str | None,
    records_received: int | None = None,
) -> UUID:
    run_id = uuid4()
    sql = text(
        """
        INSERT INTO raw.ingestion_runs (
            ingestion_run_id, source_id, source_name, source_file, source_url,
            started_at, status, records_received
        ) VALUES (
            :ingestion_run_id, :source_id, :source_name, :source_file, :source_url,
            :started_at, 'started', :records_received
        )
        """
    )
    with engine.begin() as connection:
        connection.execute(
            sql,
            {
                "ingestion_run_id": run_id,
                "source_id": source_id,
                "source_name": source_name,
                "source_file": source_file,
                "source_url": source_url,
                "started_at": utc_now(),
                "records_received": records_received,
            },
        )
    return run_id


def finish_ingestion_run(
    engine: Engine,
    run_id: UUID,
    *,
    status: str,
    records_loaded: int | None = None,
    notes: str | None = None,
) -> None:
    sql = text(
        """
        UPDATE raw.ingestion_runs
        SET completed_at = :completed_at,
            status = :status,
            records_loaded = :records_loaded,
            notes = :notes
        WHERE ingestion_run_id = :ingestion_run_id
        """
    )
    with engine.begin() as connection:
        connection.execute(
            sql,
            {
                "ingestion_run_id": run_id,
                "completed_at": utc_now(),
                "status": status,
                "records_loaded": records_loaded,
                "notes": notes,
            },
        )


def replace_gdc_entities(
    engine: Engine,
    *,
    source_id: UUID,
    run_id: UUID,
    entities: Mapping[str, Sequence[Mapping[str, Any]]],
) -> dict[str, int]:
    """Replace raw+staging GDC tables for one source inside one transaction."""
    table_map = {
        "cases": "raw.gdc_cases",
        "demographics": "raw.gdc_demographics",
        "diagnoses": "raw.gdc_diagnoses",
        "follow_ups": "raw.gdc_follow_ups",
        "treatments": "raw.gdc_treatments",
    }
    counts: dict[str, int] = {}
    with engine.begin() as connection:
        for table in (
            "staging.gdc_treatments",
            "staging.gdc_follow_ups",
            "staging.gdc_diagnoses",
            "staging.gdc_demographics",
            "staging.gdc_cases",
            "raw.gdc_treatments",
            "raw.gdc_follow_ups",
            "raw.gdc_diagnoses",
            "raw.gdc_demographics",
            "raw.gdc_cases",
        ):
            connection.execute(
                text(f"DELETE FROM {table} WHERE source_id = :source_id"),
                {"source_id": source_id},
            )
        for key, table in table_map.items():
            rows = list(entities.get(key, []))
            counts[key] = len(rows)
            for row in rows:
                payload = dict(row)
                payload["source_id"] = source_id
                payload["ingestion_run_id"] = run_id
                payload["payload"] = _json(row["payload"])
                columns = list(payload)
                placeholders = ", ".join(f":{name}" for name in columns)
                colsql = ", ".join(columns)
                insert = text(f"INSERT INTO {table} ({colsql}) VALUES ({placeholders})")
                if "payload" in payload:
                    insert = text(
                        f"INSERT INTO {table} ({colsql}) "
                        f"VALUES ({_payload_placeholders(columns)})"
                    )
                connection.execute(insert, payload)
            _insert_gdc_staging(connection, key, source_id, rows)
    return counts


def _payload_placeholders(columns: Sequence[str]) -> str:
    parts = []
    for name in columns:
        if name == "payload":
            parts.append("CAST(:payload AS JSONB)")
        else:
            parts.append(f":{name}")
    return ", ".join(parts)


def _insert_gdc_staging(
    connection: Any,
    key: str,
    source_id: UUID,
    rows: Sequence[Mapping[str, Any]],
) -> None:
    if key == "cases":
        for row in rows:
            connection.execute(
                text(
                    """
                    INSERT INTO staging.gdc_cases (
                        source_id, case_id, submitter_id, submitter_id_normalized,
                        join_barcode, project_id, disease_type, primary_site,
                        index_date, lost_to_followup, days_to_lost_to_followup
                    ) VALUES (
                        :source_id, :case_id, :submitter_id, :submitter_id_normalized,
                        :join_barcode, :project_id, :disease_type, :primary_site,
                        :index_date, :lost_to_followup, :days_to_lost_to_followup
                    )
                    """
                ),
                {**row, "source_id": source_id},
            )
    elif key == "demographics":
        for row in rows:
            raw_status = row.get("vital_status")
            connection.execute(
                text(
                    """
                    INSERT INTO staging.gdc_demographics (
                        source_id, case_id, submitter_id, submitter_id_normalized,
                        join_barcode, demographic_id, vital_status_raw,
                        vital_status_missing_class, vital_status_analysis_class,
                        days_to_death, age_at_index, days_to_birth,
                        sex_at_birth_raw, sex_at_birth_missing_class,
                        race_raw, race_missing_class, ethnicity_raw,
                        ethnicity_missing_class
                    ) VALUES (
                        :source_id, :case_id, :submitter_id, :submitter_id_normalized,
                        :join_barcode, :demographic_id, :vital_status_raw,
                        :vital_status_missing_class, :vital_status_analysis_class,
                        :days_to_death, :age_at_index, :days_to_birth,
                        :sex_at_birth_raw, :sex_at_birth_missing_class,
                        :race_raw, :race_missing_class, :ethnicity_raw,
                        :ethnicity_missing_class
                    )
                    """
                ),
                {
                    "source_id": source_id,
                    "case_id": row.get("case_id"),
                    "submitter_id": row.get("submitter_id"),
                    "submitter_id_normalized": row.get("submitter_id_normalized"),
                    "join_barcode": row.get("join_barcode"),
                    "demographic_id": row.get("demographic_id"),
                    "vital_status_raw": raw_status,
                    "vital_status_missing_class": classify_missing(raw_status),
                    "vital_status_analysis_class": classify_vital_status(raw_status),
                    "days_to_death": row.get("days_to_death"),
                    "age_at_index": row.get("age_at_index"),
                    "days_to_birth": row.get("days_to_birth"),
                    "sex_at_birth_raw": row.get("sex_at_birth"),
                    "sex_at_birth_missing_class": classify_missing(
                        row.get("sex_at_birth")
                    ),
                    "race_raw": row.get("race"),
                    "race_missing_class": classify_missing(row.get("race")),
                    "ethnicity_raw": row.get("ethnicity"),
                    "ethnicity_missing_class": classify_missing(row.get("ethnicity")),
                },
            )
    elif key == "diagnoses":
        for row in rows:
            connection.execute(
                text(
                    """
                    INSERT INTO staging.gdc_diagnoses (
                        source_id, case_id, submitter_id, submitter_id_normalized,
                        join_barcode, diagnosis_id, age_at_diagnosis_days,
                        days_to_diagnosis, days_to_last_follow_up, primary_diagnosis,
                        morphology, year_of_diagnosis
                    ) VALUES (
                        :source_id, :case_id, :submitter_id, :submitter_id_normalized,
                        :join_barcode, :diagnosis_id, :age_at_diagnosis,
                        :days_to_diagnosis, :days_to_last_follow_up, :primary_diagnosis,
                        :morphology, :year_of_diagnosis
                    )
                    """
                ),
                {**row, "source_id": source_id},
            )
    elif key == "follow_ups":
        for row in rows:
            connection.execute(
                text(
                    """
                    INSERT INTO staging.gdc_follow_ups (
                        source_id, case_id, submitter_id, submitter_id_normalized,
                        join_barcode, follow_up_id, days_to_follow_up,
                        timepoint_category, first_event, days_to_first_event,
                        year_of_follow_up
                    ) VALUES (
                        :source_id, :case_id, :submitter_id, :submitter_id_normalized,
                        :join_barcode, :follow_up_id, :days_to_follow_up,
                        :timepoint_category, :first_event, :days_to_first_event,
                        :year_of_follow_up
                    )
                    """
                ),
                {**row, "source_id": source_id},
            )
    elif key == "treatments":
        for row in rows:
            connection.execute(
                text(
                    """
                    INSERT INTO staging.gdc_treatments (
                        source_id, case_id, submitter_id, submitter_id_normalized,
                        join_barcode, diagnosis_id, treatment_id, treatment_type,
                        treatment_or_therapy, therapeutic_agents, protocol_identifier,
                        days_to_treatment_start, days_to_treatment_end,
                        timepoint_category, treatment_outcome, course_number
                    ) VALUES (
                        :source_id, :case_id, :submitter_id, :submitter_id_normalized,
                        :join_barcode, :diagnosis_id, :treatment_id, :treatment_type,
                        :treatment_or_therapy,
                        :therapeutic_agents,
                        :protocol_identifier,
                        :days_to_treatment_start, :days_to_treatment_end,
                        :timepoint_category, :treatment_outcome, :course_number
                    )
                    """
                ),
                {**row, "source_id": source_id},
            )


SUPPLEMENT_CONCEPT_COLUMNS = {
    "Vital Status": "vital_status_raw",
    "Overall Survival Time in Days": "os_time_days",
    "Age at Diagnosis in Days": "age_at_diagnosis_days",
    "Gender": "sex_raw",
    "Race": "race_raw",
    "Ethnicity": "ethnicity_raw",
    "WBC at Diagnosis": "wbc_raw",
    "Risk group": "risk_group_raw",
    "FLT3/ITD positive?": "flt3_itd_raw",
    "NPM mutation": "npm_raw",
    "CEBPA mutation": "cebpa_raw",
    "FAB Category": "fab_raw",
    "CNS disease": "cns_disease_raw",
    "Bone marrow leukemic blast percentage (%)": "marrow_blasts_raw",
    "Peripheral blasts (%)": "peripheral_blasts_raw",
    "Protocol": "protocol_raw",
    "First Event": "first_event_raw",
}


def _as_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip().replace(",", ""))
        except ValueError:
            return None
    return None


def replace_supplement_sheet(
    engine: Engine,
    *,
    source_id: UUID,
    run_id: UUID,
    sheet: Mapping[str, Any],
) -> int:
    """Replace one workbook/sheet of supplement rows in a transaction."""
    records = list(sheet["records"])
    workbook = sheet["workbook"]
    sheet_name = sheet["sheet"]
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                DELETE FROM staging.supplement_clinical_rows
                WHERE source_id = :source_id AND sheet_name = :sheet_name
                """
            ),
            {"source_id": source_id, "sheet_name": sheet_name},
        )
        connection.execute(
            text(
                """
                DELETE FROM raw.supplement_rows
                WHERE source_id = :source_id AND sheet_name = :sheet_name
                """
            ),
            {"source_id": source_id, "sheet_name": sheet_name},
        )
        connection.execute(
            text(
                """
                INSERT INTO raw.supplement_sheets (
                    source_id, workbook_name, sheet_name, n_rows, n_columns,
                    identifier_field, is_patient_level, columns
                ) VALUES (
                    :source_id, :workbook_name, :sheet_name, :n_rows, :n_columns,
                    :identifier_field, :is_patient_level, CAST(:columns AS JSONB)
                )
                ON CONFLICT (source_id, sheet_name) DO UPDATE SET
                    n_rows = EXCLUDED.n_rows,
                    n_columns = EXCLUDED.n_columns,
                    identifier_field = EXCLUDED.identifier_field,
                    is_patient_level = EXCLUDED.is_patient_level,
                    columns = EXCLUDED.columns
                """
            ),
            {
                "source_id": source_id,
                "workbook_name": workbook,
                "sheet_name": sheet_name,
                "n_rows": sheet["n_rows"],
                "n_columns": sheet["n_columns"],
                "identifier_field": sheet.get("identifier_field"),
                "is_patient_level": sheet.get("is_patient_level"),
                "columns": _json(sheet["columns"]),
            },
        )
        for record in records:
            cells = record["cells"]
            connection.execute(
                text(
                    """
                    INSERT INTO raw.supplement_rows (
                        source_id, ingestion_run_id, workbook_name, sheet_name,
                        row_number, original_identifier, normalized_identifier,
                        join_barcode, identifier_shape, cells
                    ) VALUES (
                        :source_id, :ingestion_run_id, :workbook_name, :sheet_name,
                        :row_number, :original_identifier, :normalized_identifier,
                        :join_barcode, :identifier_shape, CAST(:cells AS JSONB)
                    )
                    """
                ),
                {
                    "source_id": source_id,
                    "ingestion_run_id": run_id,
                    "workbook_name": workbook,
                    "sheet_name": sheet_name,
                    "row_number": record["row_number"],
                    "original_identifier": record["original_identifier"],
                    "normalized_identifier": record["normalized_identifier"],
                    "join_barcode": record["join_barcode"],
                    "identifier_shape": record["identifier_shape"],
                    "cells": _json(cells),
                },
            )
            staged = {
                "source_id": source_id,
                "workbook_name": workbook,
                "sheet_name": sheet_name,
                "row_number": record["row_number"],
                "original_identifier": record["original_identifier"],
                "normalized_identifier": record["normalized_identifier"],
                "join_barcode": record["join_barcode"],
                "identifier_shape": record["identifier_shape"],
                "cells": _json(cells),
                "vital_status_raw": None,
                "vital_status_missing_class": None,
                "os_time_days": None,
                "os_time_missing_class": None,
                "age_at_diagnosis_days": None,
                "sex_raw": None,
                "race_raw": None,
                "ethnicity_raw": None,
                "wbc_raw": None,
                "risk_group_raw": None,
                "flt3_itd_raw": None,
                "npm_raw": None,
                "cebpa_raw": None,
                "fab_raw": None,
                "cns_disease_raw": None,
                "marrow_blasts_raw": None,
                "peripheral_blasts_raw": None,
                "protocol_raw": None,
                "first_event_raw": None,
            }
            for source_col, dest in SUPPLEMENT_CONCEPT_COLUMNS.items():
                if source_col in cells:
                    value = cells[source_col]
                    if dest in {"os_time_days", "age_at_diagnosis_days"}:
                        staged[dest] = _as_float(value)
                        if dest == "os_time_days":
                            staged["os_time_missing_class"] = classify_missing(value)
                    else:
                        staged[dest] = None if value is None else str(value)
            if "Vital Status" in cells:
                staged["vital_status_missing_class"] = classify_missing(
                    cells.get("Vital Status")
                )
            connection.execute(
                text(
                    """
                    INSERT INTO staging.supplement_clinical_rows (
                        source_id, workbook_name, sheet_name, row_number,
                        original_identifier, normalized_identifier, join_barcode,
                        identifier_shape, vital_status_raw, vital_status_missing_class,
                        os_time_days, os_time_missing_class, age_at_diagnosis_days,
                        sex_raw, race_raw, ethnicity_raw, wbc_raw, risk_group_raw,
                        flt3_itd_raw, npm_raw, cebpa_raw, fab_raw, cns_disease_raw,
                        marrow_blasts_raw, peripheral_blasts_raw, protocol_raw,
                        first_event_raw, cells
                    ) VALUES (
                        :source_id, :workbook_name, :sheet_name, :row_number,
                        :original_identifier, :normalized_identifier, :join_barcode,
                        :identifier_shape,
                        :vital_status_raw,
                        :vital_status_missing_class,
                        :os_time_days, :os_time_missing_class, :age_at_diagnosis_days,
                        :sex_raw, :race_raw, :ethnicity_raw, :wbc_raw, :risk_group_raw,
                        :flt3_itd_raw, :npm_raw, :cebpa_raw, :fab_raw, :cns_disease_raw,
                        :marrow_blasts_raw, :peripheral_blasts_raw, :protocol_raw,
                        :first_event_raw, CAST(:cells AS JSONB)
                    )
                    """
                ),
                staged,
            )
    return len(records)
