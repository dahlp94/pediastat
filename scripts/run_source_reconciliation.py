#!/usr/bin/env python3
"""Quantify overlap and discordance across ingested TARGET-AML sources."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from pediastat.config import get_settings
from pediastat.database.engine import create_db_engine
from pediastat.reconciliation.run import DEFAULT_OUTPUT, run_reconciliation


def _main() -> int:
    parser = argparse.ArgumentParser(description="Run source reconciliation QA.")
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
    result = run_reconciliation(engine, output_dir=args.output_dir)
    overlap = result["identifier_overlap"]
    logging.info(
        "GDC %s | supplements %s | intersection %s | GDC-only %s | supplement-only %s",
        overlap["gdc_unique_join_barcodes"],
        overlap["supplement_unique_join_barcodes"],
        overlap["intersection"],
        overlap["gdc_only"],
        overlap["supplement_only"],
    )
    logging.info("Artifacts written to %s", args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
