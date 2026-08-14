"""Compare source values without choosing a winner."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from pediastat.ingestion.missingness import classify_missing, is_observed


def _as_number(value: Any) -> float | None:
    if isinstance(value, bool) or not is_observed(value):
        return None
    if isinstance(value, int | float):
        number = float(value)
        if number == number:
            return number
        return None
    if isinstance(value, str):
        try:
            return float(value.strip().replace(",", ""))
        except ValueError:
            return None
    return None


def _norm_category(value: Any) -> str | None:
    if not is_observed(value):
        return None
    if isinstance(value, str):
        return " ".join(value.strip().lower().split())
    return str(value).strip().lower()


def categorical_agreement(
    pairs: Sequence[tuple[Any, Any]],
) -> dict[str, int | float]:
    """Compare paired categorical values from two sources."""
    n_pairs = len(pairs)
    both_observed = 0
    agreements = 0
    disagreements = 0
    missing_a_only = 0
    missing_b_only = 0
    missing_both = 0
    for left, right in pairs:
        left_obs = is_observed(left)
        right_obs = is_observed(right)
        if left_obs and right_obs:
            both_observed += 1
            if _norm_category(left) == _norm_category(right):
                agreements += 1
            else:
                disagreements += 1
        elif (not left_obs) and (not right_obs):
            missing_both += 1
        elif not left_obs:
            missing_a_only += 1
        else:
            missing_b_only += 1
    pct = round(agreements / both_observed * 100.0, 2) if both_observed else 0.0
    return {
        "n_pairs": n_pairs,
        "n_both_observed": both_observed,
        "n_agreements": agreements,
        "n_disagreements": disagreements,
        "agreement_percent": pct,
        "n_missing_a_only": missing_a_only,
        "n_missing_b_only": missing_b_only,
        "n_missing_both": missing_both,
    }


def numeric_discordance(pairs: Sequence[tuple[Any, Any]]) -> dict[str, Any]:
    """Compare paired numeric values, including difference summaries."""
    n_pairs = len(pairs)
    both_observed = 0
    exact = 0
    within_one = 0
    missing_a_only = 0
    missing_b_only = 0
    missing_both = 0
    diffs: list[float] = []
    for left, right in pairs:
        left_n = _as_number(left)
        right_n = _as_number(right)
        left_class = classify_missing(left)
        right_class = classify_missing(right)
        if left_n is not None and right_n is not None:
            both_observed += 1
            diff = left_n - right_n
            diffs.append(diff)
            if diff == 0:
                exact += 1
            if abs(diff) <= 1:
                within_one += 1
        elif left_n is None and right_n is None:
            missing_both += 1
        elif left_n is None:
            missing_a_only += 1
        else:
            missing_b_only += 1
        del left_class, right_class
    abs_diffs = [abs(item) for item in diffs]
    return {
        "n_pairs": n_pairs,
        "n_both_observed": both_observed,
        "n_exact_agreements": exact,
        "n_within_one": within_one,
        "agreement_percent": (
            round(exact / both_observed * 100.0, 2) if both_observed else 0.0
        ),
        "n_disagreements": both_observed - exact,
        "n_missing_a_only": missing_a_only,
        "n_missing_b_only": missing_b_only,
        "n_missing_both": missing_both,
        "diff_min": min(diffs) if diffs else None,
        "diff_max": max(diffs) if diffs else None,
        "abs_diff_median": _median(abs_diffs) if abs_diffs else None,
        "n_nonzero_diffs": sum(diff != 0 for diff in diffs),
    }


def _median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return float(ordered[mid])
    return (ordered[mid - 1] + ordered[mid]) / 2.0
