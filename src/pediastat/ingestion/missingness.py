"""Missing-value classification for clinical source fields.

Original values stay in raw tables. Staging may attach a class without
collapsing distinct source semantics.

Classes:
- structurally_missing: null, blank, or whitespace-only
- not_reported: explicit not-reported wording
- unknown: explicit unknown / unspecified / common NA tokens
- not_applicable: explicit not-applicable wording
- sentinel: numeric codes such as -99 that may be missing sentinels
- observed: any other value, including 0

``NA`` / ``N/A`` are classified as unknown rather than not-applicable unless
the source string is clearly ``not applicable``. That choice is documented
because spreadsheet ``N/A`` is ambiguous.
"""

from __future__ import annotations

from typing import Any

NOT_REPORTED = frozenset({"not reported", "notreported"})
UNKNOWN = frozenset(
    {
        "unknown",
        "unspecified",
        "na",
        "n/a",
        "n.a.",
        "n.a",
        "--",
        ".",
        "missing",
        "not available",
        "null",
    }
)
NOT_APPLICABLE = frozenset({"not applicable", "notapplicable"})
SENTINEL_NUMBERS = frozenset({-99, -999, -9999})


def classify_missing(value: Any) -> str:
    """Return a missingness class for a source value."""
    if value is None:
        return "structurally_missing"
    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return "structurally_missing"
        token = " ".join(stripped.lower().split())
        compact = token.replace(" ", "")
        if token in NOT_REPORTED or compact in NOT_REPORTED:
            return "not_reported"
        if token in NOT_APPLICABLE or compact in NOT_APPLICABLE:
            return "not_applicable"
        if token in UNKNOWN or compact in UNKNOWN:
            return "unknown"
        return "observed"
    if isinstance(value, bool):
        return "observed"
    if isinstance(value, int | float) and value in SENTINEL_NUMBERS:
        return "sentinel"
    return "observed"


def is_structurally_missing(value: Any) -> bool:
    return classify_missing(value) == "structurally_missing"


def is_observed(value: Any) -> bool:
    return classify_missing(value) == "observed"
