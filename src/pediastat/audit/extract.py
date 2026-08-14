"""Extract nested GDC values without silently collapsing one-to-many records."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.audit.constants import GDC_MISSING_CODES


def as_records(value: Any) -> list[dict[str, Any]]:
    """Normalize a GDC entity that may be missing, a dict, or a list of dicts."""
    if value is None:
        return []
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        return [value]
    return []


def is_null(value: Any) -> bool:
    """Return True for API nulls and empty strings, not for 0 or False."""
    if value is None:
        return True
    if isinstance(value, str) and value.strip() == "":
        return True
    return False


def is_gdc_missing_code(value: Any) -> bool:
    """Return True for explicit GDC missing-like category codes."""
    if not isinstance(value, str):
        return False
    return value.strip().lower() in GDC_MISSING_CODES


def is_usable(value: Any) -> bool:
    """Return True if a value is present and not a GDC missing-like code."""
    return not is_null(value) and not is_gdc_missing_code(value)


def get_values_at_path(record: Mapping[str, Any], path: str) -> list[Any]:
    """Return every value at a dotted path, expanding lists at each step.

    Missing intermediate keys yield no placeholder values. This preserves
    nested cardinality instead of taking the first diagnosis or follow-up.
    """
    current: Sequence[Any] = [record]
    for part in path.split("."):
        next_level: list[Any] = []
        for item in current:
            if isinstance(item, list):
                for sub in item:
                    if isinstance(sub, Mapping) and part in sub:
                        next_level.append(sub[part])
            elif isinstance(item, Mapping) and part in item:
                next_level.append(item[part])
        current = next_level
    return list(current)


def first_non_null(values: Sequence[Any]) -> Any:
    """Return the first non-null value, or None."""
    for value in values:
        if not is_null(value):
            return value
    return None


def unique_non_null(values: Sequence[Any]) -> list[Any]:
    """Return unique non-null values, preserving first-seen order."""
    seen: set[str] = set()
    unique: list[Any] = []
    for value in values:
        if is_null(value):
            continue
        key = repr(value)
        if key not in seen:
            seen.add(key)
            unique.append(value)
    return unique


def mapping_field_names(
    mapping_payload: Mapping[str, Any],
) -> dict[str, dict[str, Any]]:
    """Index GDC `_mapping` entries by cases-endpoint field path."""
    raw = mapping_payload.get("_mapping", mapping_payload)
    if not isinstance(raw, Mapping):
        return {}
    indexed: dict[str, dict[str, Any]] = {}
    for name, meta in raw.items():
        if not isinstance(name, str):
            continue
        field = name.removeprefix("cases.")
        info = meta if isinstance(meta, dict) else {}
        indexed.setdefault(field, info)
    return indexed


def field_exists_in_mapping(indexed: Mapping[str, Any], field: str) -> bool:
    return field in indexed or f"cases.{field}" in indexed
