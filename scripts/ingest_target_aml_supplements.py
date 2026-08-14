#!/usr/bin/env python3
"""Ingest open TARGET-AML clinical supplements without concatenating workbooks."""

from __future__ import annotations

import argparse
import csv
import logging
import sys
from pathlib import Path

from sqlalchemy import text

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from pediastat.audit.client import GDCClient
from pediastat.audit.run import (
    DEFAULT_DOWNLOAD_DIR,
    fetch_clinical_files,
    flatten_clinical_file_row,
    md5_file,
)
from pediastat.config import PROJECT_ROOT, get_settings
from pediastat.database.engine import create_db_engine
from pediastat.ingestion.loaders import (
    finish_ingestion_run,
    replace_supplement_sheet,
    start_ingestion_run,
    upsert_source,
)
from pediastat.ingestion.supplements import profile_sheet, read_workbook_sheets

AUDIT_FILES = PROJECT_ROOT / "artifacts" / "source_audit" / "open_clinical_files.csv"
STAGE1_AUDIT_DATE = "2026-08-14T01:24:42Z"


def _meta_from_audit_csv() -> dict[str, dict[str, str]]:
    if not AUDIT_FILES.exists():
        return {}
    with AUDIT_FILES.open(encoding="utf-8", newline="") as handle:
        return {row["file_name"]: row for row in csv.DictReader(handle)}


def _meta_from_api() -> dict[str, dict[str, object]]:
    try:
        client = GDCClient(timeout_seconds=60)
        hits = fetch_clinical_files(client)
    except Exception as exc:
        logging.warning("Could not refresh GDC file metadata: %s", exc)
        return {}
    return {
        row["file_name"]: row
        for row in (flatten_clinical_file_row(item) for item in hits)
        if row.get("file_name")
    }


def _main() -> int:
    parser = argparse.ArgumentParser(description="Ingest TARGET-AML open supplements.")
    parser.add_argument("--local-cluster", action="store_true")
    parser.add_argument("--download-dir", type=Path, default=DEFAULT_DOWNLOAD_DIR)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if args.local_cluster:
        from pediastat.database.bootstrap import bootstrap_cluster

        settings = bootstrap_cluster()
    else:
        settings = get_settings()
    engine = create_db_engine(settings)
    download_dir = args.download_dir
    if not download_dir.is_dir():
        raise FileNotFoundError(
            f"Supplement directory not found: {download_dir}. "
            "Run scripts/audit_target_aml_source.py first."
        )
    file_meta = _meta_from_audit_csv()
    file_meta.update(_meta_from_api())
    paths = sorted(download_dir.glob("*.xlsx"))
    if not paths:
        raise FileNotFoundError(f"No XLSX files in {download_dir}")
    profiles: list[dict[str, object]] = []
    for path in paths:
        logging.info("Reading %s", path.name)
        sheets = read_workbook_sheets(path)
        meta = file_meta.get(path.name, {})
        local_md5 = md5_file(path)
        api_md5 = meta.get("md5sum")
        if api_md5 and api_md5 != local_md5:
            logging.warning(
                "Checksum mismatch for %s: local %s vs catalog %s",
                path.name,
                local_md5,
                api_md5,
            )
        source_type = (
            "cde_dictionary" if "CDE" in path.name.upper() else "clinical_supplement"
        )
        n_rows = sum(sheet["n_rows"] for sheet in sheets)
        file_id = meta.get("file_id")
        source_id = upsert_source(
            engine,
            source_name=f"supplement:{path.name}",
            source_type=source_type,
            source_file=str(path.relative_to(PROJECT_ROOT)),
            source_file_id=file_id,
            source_url=(
                f"https://api.gdc.cancer.gov/data/{file_id}" if file_id else None
            ),
            api_endpoint="https://api.gdc.cancer.gov/files",
            project_id="TARGET-AML",
            access_level=str(meta.get("access") or "open"),
            checksum=local_md5,
            source_release_or_audit_date=STAGE1_AUDIT_DATE,
            row_count=n_rows,
            notes=(
                "Workbook ingested separately; original columns stored in cells JSONB."
            ),
        )
        run_id = start_ingestion_run(
            engine,
            source_id=source_id,
            source_name=f"supplement:{path.name}",
            source_file=str(path),
            source_url=None,
            records_received=n_rows,
        )
        loaded = 0
        try:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        """
                        INSERT INTO raw.supplement_workbooks (
                            source_id, workbook_name, source_file, source_file_id,
                            checksum, n_sheets
                        ) VALUES (
                            :source_id, :workbook_name, :source_file, :source_file_id,
                            :checksum, :n_sheets
                        )
                        ON CONFLICT (source_id) DO UPDATE SET
                            n_sheets = EXCLUDED.n_sheets,
                            checksum = EXCLUDED.checksum
                        """
                    ),
                    {
                        "source_id": source_id,
                        "workbook_name": path.name,
                        "source_file": str(path.relative_to(PROJECT_ROOT)),
                        "source_file_id": file_id,
                        "checksum": local_md5,
                        "n_sheets": len(sheets),
                    },
                )
            for sheet in sheets:
                loaded += replace_supplement_sheet(
                    engine, source_id=source_id, run_id=run_id, sheet=sheet
                )
                profiles.extend(profile_sheet(sheet, include_samples=False))
            if loaded != n_rows:
                raise RuntimeError(
                    f"{path.name}: loaded {loaded} vs extracted {n_rows}"
                )
            finish_ingestion_run(
                engine, run_id, status="succeeded", records_loaded=loaded
            )
        except Exception:
            finish_ingestion_run(engine, run_id, status="failed")
            raise
        logging.info("Loaded %s rows from %s", loaded, path.name)

    out = PROJECT_ROOT / "artifacts" / "ingestion_audit"
    out.mkdir(parents=True, exist_ok=True)
    if profiles:
        fieldnames = list(profiles[0].keys())
        with (out / "supplement_schema_profiles.csv").open(
            "w", encoding="utf-8", newline=""
        ) as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(profiles)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
