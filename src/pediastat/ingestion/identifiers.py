"""Identifier normalization for TARGET barcodes.

Normalization is for join comparison only. Original identifiers are never
overwritten.

Rule (Stage 2):
1. Coerce to string.
2. Strip leading and trailing whitespace.
3. Uppercase ASCII letters.
4. Do not remove hyphens or barcode suffixes.

A join barcode is the leading ``TARGET-<NN>-<TOKEN>`` component when present.
Suffixes such as ``-Unsorted`` are retained on the normalized identifier and
are not stripped, because they may distinguish biospecimen context.
"""

from __future__ import annotations

import re
from typing import Any

CANONICAL_BARCODE = re.compile(r"^TARGET-\d{2}-[A-Z0-9]+$")
EXTENDED_BARCODE = re.compile(r"^TARGET-\d{2}-[A-Z0-9]+(?:-[A-Z0-9]+)+$")
JOIN_BARCODE = re.compile(r"^(TARGET-\d{2}-[A-Z0-9]+)")


def original_identifier(value: Any) -> str | None:
    """Return the original identifier as a string, or None if absent."""
    if value is None:
        return None
    if isinstance(value, str) and value.strip() == "":
        return None
    return str(value)


def normalize_identifier(value: Any) -> str | None:
    """Return the join-comparison identifier without mutating the original."""
    original = original_identifier(value)
    if original is None:
        return None
    return original.strip().upper()


def join_barcode(value: Any) -> str | None:
    """Return the core TARGET-NN-TOKEN barcode used to join to GDC submitter_id."""
    normalized = normalize_identifier(value)
    if normalized is None:
        return None
    match = JOIN_BARCODE.match(normalized)
    if match:
        return match.group(1)
    return normalized


def identifier_shape(value: Any) -> str:
    """Classify identifier shape without rewriting it."""
    original = original_identifier(value)
    if original is None:
        return "missing"
    stripped = original.strip()
    if original != stripped:
        return "whitespace"
    normalized = stripped.upper()
    if CANONICAL_BARCODE.match(normalized):
        return "canonical"
    if EXTENDED_BARCODE.match(normalized):
        return "extended"
    return "malformed"


def has_case_difference(value: Any) -> bool:
    original = original_identifier(value)
    if original is None:
        return False
    stripped = original.strip()
    return stripped != stripped.upper()


def summarize_identifiers(values: list[Any]) -> dict[str, Any]:
    """Summarize identifier quality for one source."""
    originals = [original_identifier(value) for value in values]
    present = [item for item in originals if item is not None]
    normalized = [normalize_identifier(item) for item in present]
    unique_normalized = set(normalized)
    shapes: dict[str, int] = {}
    whitespace = 0
    case_diff = 0
    duplicates: dict[str, int] = {}
    counts: dict[str, int] = {}
    for original in present:
        shape = identifier_shape(original)
        shapes[shape] = shapes.get(shape, 0) + 1
        if original != original.strip():
            whitespace += 1
        if has_case_difference(original):
            case_diff += 1
        key = normalize_identifier(original) or ""
        counts[key] = counts.get(key, 0) + 1
    for key, count in counts.items():
        if count > 1:
            duplicates[key] = count
    return {
        "n_records": len(values),
        "n_non_null": len(present),
        "n_null": len(values) - len(present),
        "n_unique_normalized": len(unique_normalized),
        "n_duplicated_normalized_ids": len(duplicates),
        "n_duplicate_records": sum(count - 1 for count in duplicates.values()),
        "n_whitespace": whitespace,
        "n_case_differences": case_diff,
        "n_canonical": shapes.get("canonical", 0),
        "n_extended": shapes.get("extended", 0),
        "n_malformed": shapes.get("malformed", 0),
        "shapes": shapes,
    }
