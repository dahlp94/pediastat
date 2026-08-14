#!/usr/bin/env python3
"""Run a reproducible TARGET-AML source audit against the official GDC API.

This script writes metadata summaries only. It does not load PostgreSQL, does
not download controlled-access data, and does not define the final survival
endpoint.
"""

from __future__ import annotations

import sys
from pathlib import Path


def _main() -> int:
    src_dir = Path(__file__).resolve().parents[1] / "src"
    if str(src_dir) not in sys.path:
        sys.path.insert(0, str(src_dir))
    from pediastat.audit.run import main

    return main()


if __name__ == "__main__":
    raise SystemExit(_main())
