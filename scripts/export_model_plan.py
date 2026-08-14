#!/usr/bin/env python3
"""Write Stage 5 aggregate model-plan artifacts from the frozen YAML spec."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from pediastat.model_plan import write_model_plan_artifacts


def _main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    paths = write_model_plan_artifacts()
    for name, path in paths.items():
        logging.info("%s -> %s", name, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
