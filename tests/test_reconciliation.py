"""Tests for reconciliation helpers. No live API or database required."""

from __future__ import annotations

from pediastat.reconciliation.age import days_to_years, summarize_age_days
from pediastat.reconciliation.discordance import (
    categorical_agreement,
    numeric_discordance,
)
from pediastat.reconciliation.overlap import (
    overlap_distribution,
    pairwise_overlap_counts,
    universe_overlap,
)


def test_pairwise_overlap_and_distribution() -> None:
    groups = {
        "a.xlsx": {"P1", "P2", "P3"},
        "b.xlsx": {"P2", "P3", "P4"},
        "c.xlsx": {"P3"},
    }
    pairs = pairwise_overlap_counts(groups)
    shared_ab = next(
        row for row in pairs if row["file_a"] == "a.xlsx" and row["file_b"] == "b.xlsx"
    )
    assert shared_ab["n_shared"] == 2
    self_a = next(
        row for row in pairs if row["file_a"] == "a.xlsx" and row["file_b"] == "a.xlsx"
    )
    assert self_a["n_shared"] == 3
    dist = {
        row["n_files"]: row["n_identifiers"] for row in overlap_distribution(groups)
    }
    assert dist[1] == 2  # P1, P4
    assert dist[2] == 1  # P2
    assert dist[3] == 1  # P3


def test_universe_overlap_percentages() -> None:
    stats = universe_overlap({"A", "B", "C"}, {"B", "C", "D", "E"})
    assert stats["n_intersection"] == 2
    assert stats["n_left_only"] == 1
    assert stats["n_right_only"] == 2
    assert stats["pct_left_matched"] == round(2 / 3 * 100.0, 2)


def test_categorical_agreement_does_not_treat_unknown_as_match_to_alive() -> None:
    pairs = [
        ("Alive", "Alive"),
        ("Dead", "Dead"),
        ("Alive", "Dead"),
        ("Unknown", "Alive"),
        (None, None),
        ("Alive", None),
    ]
    stats = categorical_agreement(pairs)
    assert stats["n_both_observed"] == 3
    assert stats["n_agreements"] == 2
    assert stats["n_disagreements"] == 1
    assert stats["n_missing_a_only"] == 1  # Unknown vs Alive
    assert stats["n_missing_b_only"] == 1
    assert stats["n_missing_both"] == 1


def test_numeric_discordance_tracks_differences() -> None:
    pairs = [(10, 10), (10, 11), (None, 5), ("NA", 8), (3, None)]
    stats = numeric_discordance(pairs)
    assert stats["n_both_observed"] == 2
    assert stats["n_exact_agreements"] == 1
    assert stats["n_within_one"] == 2
    assert stats["diff_min"] == -1
    assert stats["n_missing_a_only"] == 2
    assert stats["n_missing_b_only"] == 1


def test_age_bands_and_thresholds_are_not_a_cohort_rule() -> None:
    # 17.9 years, 18.0 years, 21 years, 29 years, missing
    days = [17.9 * 365.25, 18 * 365.25, 21 * 365.25, 29 * 365.25, None]
    summary = summarize_age_days(days)
    assert summary["n_with_age"] == 4
    assert summary["n_age_lt_18"] == 1
    assert summary["n_age_le_18"] == 2
    assert summary["n_age_le_21"] == 3
    assert days_to_years(365.25) == 1.0
    assert summary["bands"]["15-17"] == 1
    assert summary["bands"]["18-21"] == 2
    assert summary["bands"]["22-29"] == 1
