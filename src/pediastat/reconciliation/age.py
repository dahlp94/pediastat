"""Age-at-diagnosis banding for eligibility discussion. Not a cohort rule."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

DAYS_PER_YEAR = 365.25

BANDS: tuple[tuple[str, float | None, float | None], ...] = (
    ("<1", None, 1.0),
    ("1-4", 1.0, 5.0),
    ("5-9", 5.0, 10.0),
    ("10-14", 10.0, 15.0),
    ("15-17", 15.0, 18.0),
    ("18-21", 18.0, 22.0),
    ("22-29", 22.0, 30.0),
    (">=30", 30.0, None),
)


def days_to_years(days: Any) -> float | None:
    """Convert age-at-diagnosis days to years using 365.25. Documented, not locked."""
    if isinstance(days, bool) or days is None:
        return None
    try:
        number = float(days)
    except (TypeError, ValueError):
        return None
    if number < 0:
        return None
    return number / DAYS_PER_YEAR


def band_for_years(years: float) -> str:
    for label, lower, upper in BANDS:
        if lower is not None and years < lower:
            continue
        if upper is not None and years >= upper:
            continue
        return label
    return "unbanded"


def summarize_age_days(values: Sequence[Any]) -> dict[str, Any]:
    """Summarize age in days without choosing an eligibility cutoff."""
    years_list: list[float] = []
    n_missing = 0
    for value in values:
        years = days_to_years(value)
        if years is None:
            n_missing += 1
        else:
            years_list.append(years)
    bands = {label: 0 for label, *_ in BANDS}
    for years in years_list:
        bands[band_for_years(years)] += 1
    n_known = len(years_list)
    return {
        "n_records": len(values),
        "n_with_age": n_known,
        "n_missing_age": n_missing,
        "year_conversion": "days / 365.25",
        "min_years": min(years_list) if years_list else None,
        "max_years": max(years_list) if years_list else None,
        "bands": bands,
        "n_age_lt_18": sum(years < 18 for years in years_list),
        "n_age_le_18": sum(years <= 18 for years in years_list),
        "n_age_le_21": sum(years <= 21 for years in years_list),
        "n_age_ge_18": sum(years >= 18 for years in years_list),
    }
