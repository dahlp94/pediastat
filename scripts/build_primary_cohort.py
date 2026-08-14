#!/usr/bin/env python3
"""Build the Stage 3 primary OS cohort from staging tables."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from pediastat.cohort.run import DEFAULT_OUTPUT, build_primary_cohort
from pediastat.config import get_settings
from pediastat.database.engine import create_db_engine


def _main() -> int:
    parser = argparse.ArgumentParser(
        description="Build the primary OS analysis cohort."
    )
    parser.add_argument("--local-cluster", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if args.local_cluster:
        from pediastat.database.bootstrap import bootstrap_cluster

        settings = bootstrap_cluster()
    else:
        settings = get_settings()
    engine = create_db_engine(settings)
    result = build_primary_cohort(engine, output_dir=args.output_dir)
    endpoint = result["endpoint_summary"]
    identity = result["identity_summary"]
    validation = result["database_validation"]
    logging.info(
        "Valid persons %s | primary OS N %s | deaths %s | censored %s",
        identity["n_valid_analysis_persons"],
        endpoint["primary_cohort_n"],
        endpoint["deaths"],
        endpoint["censored"],
    )
    logging.info("Database validation passed=%s", validation["passed"])
    logging.info("Artifacts written to %s", args.output_dir)
    return 0 if validation["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(_main())
