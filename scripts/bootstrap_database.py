#!/usr/bin/env python3
"""Create schemas and Stage 2 tables in PostgreSQL."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


def _main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap the PediaStat database.")
    parser.add_argument(
        "--local-cluster",
        action="store_true",
        help="Initialize a project-local PostgreSQL cluster.",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if args.local_cluster:
        from pediastat.database.bootstrap import bootstrap_cluster

        settings = bootstrap_cluster()
        logging.info(
            "Local cluster ready on %s:%s db=%s user=%s",
            settings.postgres_host,
            settings.postgres_port,
            settings.postgres_db,
            settings.postgres_user,
        )
        return 0

    from pediastat.config import PROJECT_ROOT, get_settings
    from pediastat.database.engine import SQL_FILES, apply_sql_file, create_db_engine

    settings = get_settings()
    engine = create_db_engine(settings)
    sql_dir = PROJECT_ROOT / "sql"
    for name in SQL_FILES:
        logging.info("Applying %s", name)
        apply_sql_file(engine, (sql_dir / name).read_text(encoding="utf-8"))
    logging.info("DDL applied to %s", settings.postgres_db)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
