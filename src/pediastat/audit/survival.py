"""Investigate how overall survival could be constructed.

This module does not define the final endpoint or apply a censoring rule.
Unknown or missing vital status is never treated as censored.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.audit.constants import ALIVE_STATUS_VALUES, DEAD_STATUS_VALUES
from pediastat.audit.extract import get_values_at_path, is_null


def classify_vital_status(value: Any) -> str:
    """Classify vital status into missing, alive, dead, or other."""
    if is_null(value):
        return "missing"
    token = str(value).strip().lower()
    if token in ALIVE_STATUS_VALUES:
        return "alive"
    if token in DEAD_STATUS_VALUES:
        return "dead"
    return "other"


def _numeric_values(values: Sequence[Any]) -> list[float]:
    numbers: list[float] = []
    for value in values:
        if isinstance(value, bool) or is_null(value):
            continue
        if isinstance(value, int | float):
            number = float(value)
            if number == number:
                numbers.append(number)
    return numbers


def _has_nonneg(numbers: Sequence[float]) -> bool:
    return any(number >= 0 for number in numbers)


def audit_survival_fields(cases: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Summarize survival-related fields and possible construction rules."""
    vital_raw = Counter()
    vital_class = Counter()
    n_dead_with_days_to_death = 0
    n_dead_with_nonneg_days_to_death = 0
    n_alive_with_dx_follow_up = 0
    n_alive_with_fu_follow_up = 0
    n_alive_with_either_follow_up = 0
    n_negative_death = 0
    n_zero_death = 0
    n_negative_dx_follow_up = 0
    n_zero_dx_follow_up = 0
    n_negative_fu_follow_up = 0
    n_zero_fu_follow_up = 0
    n_multiple_fu_with_time = 0
    n_dx_fu_disagree = 0
    n_death_vs_dx_disagree = 0
    n_death_vs_fu_disagree = 0
    n_gdc_style_possible = 0
    n_dead_missing_death_time = 0
    n_alive_missing_all_follow_up_times = 0

    for case in cases:
        vital_values = get_values_at_path(case, "demographic.vital_status")
        raw = next((value for value in vital_values if not is_null(value)), None)
        if raw is None:
            vital_raw["<null>"] += 1
        else:
            vital_raw[str(raw)] += 1
        status = classify_vital_status(raw)
        vital_class[status] += 1

        death_times = _numeric_values(
            get_values_at_path(case, "demographic.days_to_death")
        )
        dx_times = _numeric_values(
            get_values_at_path(case, "diagnoses.days_to_last_follow_up")
        )
        fu_times = _numeric_values(
            get_values_at_path(case, "follow_ups.days_to_follow_up")
        )

        n_negative_death += sum(time < 0 for time in death_times)
        n_zero_death += sum(time == 0 for time in death_times)
        n_negative_dx_follow_up += sum(time < 0 for time in dx_times)
        n_zero_dx_follow_up += sum(time == 0 for time in dx_times)
        n_negative_fu_follow_up += sum(time < 0 for time in fu_times)
        n_zero_fu_follow_up += sum(time == 0 for time in fu_times)

        if len(fu_times) > 1:
            n_multiple_fu_with_time += 1

        if dx_times and fu_times:
            dx_max = max(dx_times)
            fu_max = max(fu_times)
            if dx_max != fu_max:
                n_dx_fu_disagree += 1
        if death_times and dx_times and max(death_times) != max(dx_times):
            n_death_vs_dx_disagree += 1
        if death_times and fu_times and max(death_times) != max(fu_times):
            n_death_vs_fu_disagree += 1

        if status == "dead":
            if death_times:
                n_dead_with_days_to_death += 1
            if _has_nonneg(death_times):
                n_dead_with_nonneg_days_to_death += 1
                n_gdc_style_possible += 1
            else:
                n_dead_missing_death_time += 1
        elif status == "alive":
            if dx_times:
                n_alive_with_dx_follow_up += 1
            if fu_times:
                n_alive_with_fu_follow_up += 1
            if dx_times or fu_times:
                n_alive_with_either_follow_up += 1
            if _has_nonneg(dx_times) or _has_nonneg(fu_times):
                n_gdc_style_possible += 1
            else:
                n_alive_missing_all_follow_up_times += 1

    n_cases = len(cases)
    return {
        "n_cases": n_cases,
        "vital_status_raw_counts": dict(vital_raw.most_common()),
        "vital_status_class_counts": dict(vital_class),
        "n_dead_with_days_to_death": n_dead_with_days_to_death,
        "n_dead_with_nonnegative_days_to_death": n_dead_with_nonneg_days_to_death,
        "n_dead_missing_days_to_death": n_dead_missing_death_time,
        "n_alive_with_diagnoses_days_to_last_follow_up": n_alive_with_dx_follow_up,
        "n_alive_with_follow_ups_days_to_follow_up": n_alive_with_fu_follow_up,
        "n_alive_with_either_follow_up_time": n_alive_with_either_follow_up,
        "n_alive_missing_all_follow_up_times": n_alive_missing_all_follow_up_times,
        "n_cases_with_multiple_follow_up_times": n_multiple_fu_with_time,
        "n_cases_diagnosis_vs_follow_up_time_disagree": n_dx_fu_disagree,
        "n_cases_death_vs_diagnosis_follow_up_disagree": n_death_vs_dx_disagree,
        "n_cases_death_vs_follow_up_time_disagree": n_death_vs_fu_disagree,
        "n_negative_days_to_death_values": n_negative_death,
        "n_zero_days_to_death_values": n_zero_death,
        "n_negative_days_to_last_follow_up_values": n_negative_dx_follow_up,
        "n_zero_days_to_last_follow_up_values": n_zero_dx_follow_up,
        "n_negative_days_to_follow_up_values": n_negative_fu_follow_up,
        "n_zero_days_to_follow_up_values": n_zero_fu_follow_up,
        "n_cases_with_possible_gdc_style_survival_time": n_gdc_style_possible,
        "possible_rules": {
            "gdc_style_alive_dead_only": {
                "description": (
                    "Event if vital_status is dead; censored if alive. Time from "
                    "days_to_death for deaths and from "
                    "diagnoses.days_to_last_follow_up and/or "
                    "follow_ups.days_to_follow_up for living cases. Exclude "
                    "missing/unknown/other vital_status. Do not treat unknown as "
                    "censored."
                ),
                "n_cases_with_required_fields": n_gdc_style_possible,
            },
            "diagnosis_follow_up_only_for_censoring": {
                "description": (
                    "Same event rule, but living cases use only "
                    "diagnoses.days_to_last_follow_up."
                ),
                "n_cases_with_required_fields": (
                    n_dead_with_nonneg_days_to_death + n_alive_with_dx_follow_up
                ),
            },
            "max_follow_up_time_for_censoring": {
                "description": (
                    "Same event rule, but living cases use the maximum "
                    "follow_ups.days_to_follow_up."
                ),
                "n_cases_with_required_fields": (
                    n_dead_with_nonneg_days_to_death + n_alive_with_fu_follow_up
                ),
            },
        },
        "unresolved": [
            (
                "Exact censoring-time field (diagnosis vs follow-up vs combination) "
                "is not locked."
            ),
            "How to handle disagreements among time fields is not locked.",
            "Whether zero times are valid events or data errors is not locked.",
            "Unknown/not reported vital status must not be recoded as censored.",
        ],
    }
