#!/usr/bin/env python3
"""Report whether the local PediaStat environment is usable.

This check does not connect to PostgreSQL. A missing or stopped database
is not a failure at Stage 0.
"""

from __future__ import annotations

import importlib
import sys
from collections.abc import Sequence
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = PROJECT_ROOT / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

REQUIRED_IMPORTS: Sequence[str] = (
    "pandas",
    "numpy",
    "pydantic",
    "pydantic_settings",
    "sqlalchemy",
    "psycopg",
    "yaml",
    "pediastat",
    "pediastat.config",
    "requests",
    "openpyxl",
)

EXPECTED_DIRECTORIES: Sequence[Path] = (
    PROJECT_ROOT / "config",
    PROJECT_ROOT / "data",
    PROJECT_ROOT / "data" / "raw",
    PROJECT_ROOT / "data" / "interim",
    PROJECT_ROOT / "data" / "processed",
    PROJECT_ROOT / "docs",
    PROJECT_ROOT / "sql",
    PROJECT_ROOT / "src" / "pediastat",
    PROJECT_ROOT / "analysis" / "R",
    PROJECT_ROOT / "reports",
    PROJECT_ROOT / "tests",
    PROJECT_ROOT / "artifacts",
    PROJECT_ROOT / "artifacts" / "source_audit",
    PROJECT_ROOT / "artifacts" / "ingestion_audit",
    PROJECT_ROOT / "artifacts" / "cohort_definition",
)


def _status(ok: bool) -> str:
    return "PASS" if ok else "FAIL"


def check_python_version() -> bool:
    version = sys.version.replace("\n", " ")
    ok = sys.version_info >= (3, 12)
    print(f"[{_status(ok)}] Python {version}")
    if not ok:
        print("         Python 3.12 or later is required.")
    return ok


def check_imports() -> bool:
    all_ok = True
    for module_name in REQUIRED_IMPORTS:
        try:
            importlib.import_module(module_name)
        except Exception as exc:
            print(f"[{_status(False)}] import {module_name}: {exc}")
            all_ok = False
        else:
            print(f"[{_status(True)}] import {module_name}")
    return all_ok


def check_directories() -> bool:
    all_ok = True
    for path in EXPECTED_DIRECTORIES:
        exists = path.is_dir()
        relative = path.relative_to(PROJECT_ROOT)
        print(f"[{_status(exists)}] directory {relative}")
        all_ok = all_ok and exists
    return all_ok


def check_settings() -> bool:
    try:
        from pediastat.config import Settings

        settings = Settings()
        display = settings.redacted()
    except Exception as exc:
        print(f"[{_status(False)}] load settings: {exc}")
        return False

    print(f"[{_status(True)}] load settings")
    print(f"         host={display['postgres_host']}")
    print(f"         port={display['postgres_port']}")
    print(f"         db={display['postgres_db']}")
    print(f"         user={display['postgres_user']}")
    print(f"         password={display['postgres_password']}")
    print(f"         data_dir={display['data_dir']}")
    print("         PostgreSQL connectivity is not required for this check.")
    return True


def main() -> int:
    print("PediaStat environment check")
    print(f"project root: {PROJECT_ROOT}")
    print()

    results = [
        check_python_version(),
        check_imports(),
        check_directories(),
        check_settings(),
    ]
    ok = all(results)
    print()
    print("Environment check passed." if ok else "Environment check failed.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
