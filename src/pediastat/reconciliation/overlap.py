"""Set-overlap helpers for source-identifier QA."""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping


def pairwise_overlap_counts(
    groups: Mapping[str, set[str]],
) -> list[dict[str, str | int]]:
    """Return pairwise intersection sizes, including a file with itself."""
    names = list(groups)
    rows: list[dict[str, str | int]] = []
    for left in names:
        for right in names:
            rows.append(
                {
                    "file_a": left,
                    "file_b": right,
                    "n_shared": len(groups[left] & groups[right]),
                    "n_a": len(groups[left]),
                    "n_b": len(groups[right]),
                }
            )
    return rows


def overlap_distribution(
    groups: Mapping[str, set[str]],
) -> list[dict[str, int | str]]:
    """Count how many groups each identifier belongs to."""
    membership: Counter[str] = Counter()
    for values in groups.values():
        for item in values:
            membership[item] += 1
    dist = Counter(membership.values())
    rows = [
        {"n_files": n_files, "n_identifiers": count}
        for n_files, count in sorted(dist.items())
    ]
    return rows


def universe_overlap(left: set[str], right: set[str]) -> dict[str, int | float]:
    """Compare two identifier universes."""
    intersection = left & right
    left_only = left - right
    right_only = right - left
    n_left = len(left)
    n_right = len(right)
    n_intersection = len(intersection)
    return {
        "n_left": n_left,
        "n_right": n_right,
        "n_intersection": n_intersection,
        "n_left_only": len(left_only),
        "n_right_only": len(right_only),
        "pct_left_matched": (
            round(n_intersection / n_left * 100.0, 2) if n_left else 0.0
        ),
        "pct_right_matched": (
            round(n_intersection / n_right * 100.0, 2) if n_right else 0.0
        ),
    }
