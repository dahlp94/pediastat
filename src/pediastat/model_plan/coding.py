"""Stage 5 inferential coding and model-plan helpers.

These functions construct planned analysis variables. They do not fit Cox
models, run multiple imputation, or estimate predictor-survival associations.
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from typing import Any

UNRESOLVED_RISK_FLAG = "unresolved_risk_group_token"


def age5(age_years: float | None, divisor: float = 5.0) -> float | None:
    """Return age at diagnosis in 5-year units."""
    if age_years is None:
        return None
    value = float(age_years)
    if not math.isfinite(value):
        return None
    return value / divisor


def log2_wbc(wbc: float | None) -> float | None:
    """Return log2(WBC) for strictly positive observed WBC; else missing."""
    if wbc is None:
        return None
    value = float(wbc)
    if not math.isfinite(value) or value <= 0:
        return None
    return math.log2(value)


def _norm_token(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def harmonize_yes_no(
    value: Any,
    *,
    yes_tokens: Sequence[str],
    no_tokens: Sequence[str],
    missing_tokens: Sequence[str],
) -> str | None:
    """Map mixed-case Yes/No source tokens to Yes/No; unknown becomes missing."""
    token = _norm_token(value)
    if token == "":
        return None
    if token in missing_tokens:
        return None
    if token in yes_tokens:
        return "Yes"
    if token in no_tokens:
        return "No"
    upper = token.upper()
    if upper == "YES":
        return "Yes"
    if upper == "NO":
        return "No"
    if upper in {
        "UNKNOWN",
        "UNSPECIFIED",
        "NOT REPORTED",
        "NOT APPLICABLE",
        "NOT DONE",
    }:
        return None
    return None


def standardize_sex(
    value: Any,
    mapping: Mapping[str, str],
    missing_tokens: Sequence[str],
) -> str | None:
    token = _norm_token(value)
    if token == "" or token in missing_tokens:
        return None
    if token in mapping:
        return mapping[token]
    lowered = token.lower()
    for key, mapped in mapping.items():
        if key.lower() == lowered:
            return mapped
    return None


def standardize_risk_group(
    value: Any,
    *,
    mapping: Mapping[str, str],
    unresolved_tokens: Sequence[str],
    missing_tokens: Sequence[str],
) -> dict[str, Any]:
    """Map CDE High/Low/Standard labels. Unresolved tokens become missing."""
    original = _norm_token(value)
    result = {
        "original": original if original else None,
        "standardized": None,
        "qa_flag": None,
        "mapping_action": "missing",
    }
    if original == "":
        return result
    if original in unresolved_tokens:
        result["qa_flag"] = UNRESOLVED_RISK_FLAG
        result["mapping_action"] = "unresolved_set_missing"
        return result
    if original in missing_tokens:
        result["mapping_action"] = "source_missing"
        return result
    if original in mapping:
        result["standardized"] = mapping[original]
        result["mapping_action"] = "mapped"
        return result
    result["qa_flag"] = UNRESOLVED_RISK_FLAG
    result["mapping_action"] = "unrecognized_set_missing"
    return result


def factor_levels(values: Sequence[str | None], reference: str) -> list[str]:
    """Return factor levels with the planned reference first."""
    observed = [item for item in values if item is not None]
    rest = sorted({item for item in observed if item != reference})
    if reference not in observed and not rest:
        return [reference]
    return [reference, *rest]


def model_df(primary_df: int, secondary_df: int) -> dict[str, Any]:
    return {
        "primary_clinical_df": primary_df,
        "secondary_molecular_df": secondary_df,
    }
