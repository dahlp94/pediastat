"""Load the frozen Stage 5 model specification. No results are stored here."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from pediastat.config import PROJECT_ROOT

DEFAULT_SPEC_PATH = PROJECT_ROOT / "config" / "model_spec.yaml"

FORBIDDEN_RESULT_KEYS = {
    "hazard_ratio",
    "hazard_ratios",
    "hr",
    "coef",
    "coefficient",
    "p_value",
    "pvalue",
    "q_value",
    "qvalue",
    "logrank",
    "concordance_result",
}


def load_model_spec(path: Path | None = None) -> dict[str, Any]:
    spec_path = path or DEFAULT_SPEC_PATH
    with spec_path.open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    if not isinstance(loaded, dict):
        msg = f"Model spec at {spec_path} must be a mapping."
        raise ValueError(msg)
    return loaded


def assert_spec_has_no_results(spec: dict[str, Any] | None = None) -> None:
    payload = spec if spec is not None else load_model_spec()
    _walk_for_results(payload, "root")


def _walk_for_results(node: object, prefix: str) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            lowered = str(key).lower()
            if lowered in FORBIDDEN_RESULT_KEYS:
                msg = f"Model spec unexpectedly contains result key {prefix}.{key}."
                raise ValueError(msg)
            _walk_for_results(value, f"{prefix}.{key}")
    elif isinstance(node, list):
        for index, item in enumerate(node):
            _walk_for_results(item, f"{prefix}[{index}]")
