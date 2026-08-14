#!/usr/bin/env python3
"""Ingest TARGET-AML GDC Cases API entities into raw and staging tables."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from pediastat.audit.client import GDCClient
from pediastat.audit.constants import (
    CANDIDATE_FIELDS,
    GDC_API_BASE_URL,
    TARGET_AML_PROJECT_ID,
)
from pediastat.audit.extract import field_exists_in_mapping, mapping_field_names
from pediastat.audit.run import fetch_all_cases, fetch_cases_mapping
from pediastat.config import get_settings
from pediastat.database.engine import create_db_engine
from pediastat.ingestion.gdc import parse_cases
from pediastat.ingestion.loaders import (
    finish_ingestion_run,
    replace_gdc_entities,
    start_ingestion_run,
    upsert_source,
)


def _main() -> int:
    parser = argparse.ArgumentParser(description="Ingest TARGET-AML GDC cases.")
    parser.add_argument("--local-cluster", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    if args.local_cluster:
        from pediastat.database.bootstrap import bootstrap_cluster

        settings = bootstrap_cluster()
    else:
        settings = get_settings()
    engine = create_db_engine(settings)
    client = GDCClient(timeout_seconds=120)
    mapping = mapping_field_names(fetch_cases_mapping(client))
    fields = [
        field
        for field in CANDIDATE_FIELDS
        if field_exists_in_mapping(mapping, field)
    ]
    logging.info("Fetching TARGET-AML cases (%s fields)", len(fields))
    cases, pagination = fetch_all_cases(client, fields)
    logging.info(
        "Retrieved %s cases (pagination total %s)",
        len(cases),
        pagination.get("total"),
    )
    entities = parse_cases(cases)
    source_id = upsert_source(
        engine,
        source_name="gdc_cases_api_target_aml",
        source_type="gdc_cases_api",
        source_url=GDC_API_BASE_URL,
        api_endpoint=f"{GDC_API_BASE_URL}/cases",
        project_id=TARGET_AML_PROJECT_ID,
        access_level="open",
        row_count=len(cases),
        notes=(
            "Raw JSON payloads stored per entity. "
            "Follow-ups and treatments not collapsed."
        ),
    )
    run_id = start_ingestion_run(
        engine,
        source_id=source_id,
        source_name="gdc_cases_api_target_aml",
        source_file=None,
        source_url=f"{GDC_API_BASE_URL}/cases",
        records_received=len(cases),
    )
    try:
        counts = replace_gdc_entities(
            engine, source_id=source_id, run_id=run_id, entities=entities
        )
        if counts["cases"] != len(cases):
            raise RuntimeError(
                "Case row count mismatch: "
                f"parsed {counts['cases']} vs fetched {len(cases)}"
            )
        finish_ingestion_run(
            engine,
            run_id,
            status="succeeded",
            records_loaded=counts["cases"],
            notes=str(counts),
        )
    except Exception:
        finish_ingestion_run(engine, run_id, status="failed")
        raise
    logging.info("Loaded GDC entities: %s", counts)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
