"""Summaries of nested GDC fields and entity cardinality."""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.audit.extract import (
    as_records,
    get_values_at_path,
    is_gdc_missing_code,
    is_null,
    is_usable,
    unique_non_null,
)

MAX_DISTINCT_TO_LIST = 40


def _as_number(value: Any) -> float | None:
    if isinstance(value, bool) or is_null(value):
        return None
    if isinstance(value, int | float):
        number = float(value)
        if number != number:  # NaN
            return None
        return number
    return None


def _entity_for_field(field_path: str) -> str:
    root = field_path.split(".", maxsplit=1)[0]
    mapping = {
        "demographic": "demographic",
        "diagnoses": "diagnosis",
        "follow_ups": "follow_up",
        "project": "project",
    }
    if field_path.startswith("diagnoses.treatments."):
        return "treatment"
    return mapping.get(root, "case")


def summarize_field(
    cases: Sequence[Mapping[str, Any]],
    field_path: str,
    *,
    exists_in_mapping: bool,
    gdc_type: str | None = None,
    gdc_description: str | None = None,
) -> dict[str, Any]:
    """Summarize a field across cases without collapsing nested records."""
    n_cases = len(cases)
    n_available = 0
    n_usable = 0
    n_multiple = 0
    n_disagree = 0
    n_negative = 0
    n_zero = 0
    n_nested_records = 0
    n_gdc_missing_code = 0
    numbers: list[float] = []
    categorical = Counter()
    saw_number = False
    saw_non_number = False

    for case in cases:
        values = get_values_at_path(case, field_path)
        n_nested_records += len(values)
        non_null = [value for value in values if not is_null(value)]
        usable = [value for value in non_null if is_usable(value)]
        if non_null:
            n_available += 1
        if usable:
            n_usable += 1
        if len(non_null) > 1:
            n_multiple += 1
            if len(unique_non_null(non_null)) > 1:
                n_disagree += 1
        for value in non_null:
            if is_gdc_missing_code(value):
                n_gdc_missing_code += 1
            number = _as_number(value)
            if number is not None:
                saw_number = True
                numbers.append(number)
                if number < 0:
                    n_negative += 1
                if number == 0:
                    n_zero += 1
            else:
                saw_non_number = True
                categorical[str(value)] += 1

    n_missing = n_cases - n_available
    pct_missing = (n_missing / n_cases * 100.0) if n_cases else 0.0
    if saw_number and not saw_non_number:
        value_kind = "numeric"
    elif saw_non_number and not saw_number:
        value_kind = "categorical"
    elif saw_number and saw_non_number:
        value_kind = "mixed"
    else:
        value_kind = "empty"

    distinct: list[str] | None
    if value_kind in {"categorical", "mixed"}:
        items = [f"{name} (n={count})" for name, count in categorical.most_common()]
        distinct = items[:MAX_DISTINCT_TO_LIST]
        n_distinct = len(categorical)
    elif value_kind == "numeric":
        distinct = None
        n_distinct = None
    else:
        distinct = []
        n_distinct = 0

    return {
        "field_path": field_path,
        "source_entity": _entity_for_field(field_path),
        "exists_in_mapping": exists_in_mapping,
        "gdc_type": gdc_type,
        "gdc_description": gdc_description,
        "n_cases": n_cases,
        "n_available": n_available,
        "n_missing": n_missing,
        "pct_missing": round(pct_missing, 2),
        "n_usable": n_usable,
        "n_gdc_missing_code_records": n_gdc_missing_code,
        "value_kind": value_kind,
        "numeric_min": min(numbers) if numbers else None,
        "numeric_max": max(numbers) if numbers else None,
        "n_negative_values": n_negative if saw_number else None,
        "n_zero_values": n_zero if saw_number else None,
        "n_distinct": n_distinct,
        "distinct_values": distinct,
        "n_cases_with_multiple_nonnull": n_multiple,
        "n_cases_with_disagreeing_values": n_disagree,
        "n_nested_records_observed": n_nested_records,
    }


def _count_bucket(counts: Sequence[int]) -> dict[str, int]:
    zero = one = many = 0
    for count in counts:
        if count == 0:
            zero += 1
        elif count == 1:
            one += 1
        else:
            many += 1
    return {
        "n_cases_with_0": zero,
        "n_cases_with_1": one,
        "n_cases_with_gt1": many,
        "min": min(counts) if counts else 0,
        "max": max(counts) if counts else 0,
    }


def entity_cardinality(cases: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Count nested diagnosis, follow-up, and treatment records per case."""
    diagnosis_counts: list[int] = []
    follow_up_counts: list[int] = []
    follow_up_with_time_counts: list[int] = []
    treatment_counts: list[int] = []
    follow_ups_nested_under_diagnosis = 0

    for case in cases:
        diagnoses = as_records(case.get("diagnoses"))
        follow_ups = as_records(case.get("follow_ups"))
        treatments: list[dict[str, Any]] = []
        for diagnosis in diagnoses:
            treatments.extend(as_records(diagnosis.get("treatments")))
            if as_records(diagnosis.get("follow_ups")):
                follow_ups_nested_under_diagnosis += 1

        diagnosis_counts.append(len(diagnoses))
        follow_up_counts.append(len(follow_ups))
        follow_up_with_time_counts.append(
            sum(1 for item in follow_ups if not is_null(item.get("days_to_follow_up")))
        )
        treatment_counts.append(len(treatments))

    return {
        "n_cases": len(cases),
        "diagnoses": _count_bucket(diagnosis_counts),
        "follow_ups": _count_bucket(follow_up_counts),
        "follow_ups_with_days_to_follow_up": _count_bucket(follow_up_with_time_counts),
        "treatments": _count_bucket(treatment_counts),
        "n_cases_with_follow_ups_nested_under_diagnosis": (
            follow_ups_nested_under_diagnosis
        ),
        "follow_up_association": (
            "Follow-up records are returned as a case-level array in the Cases API "
            "response inspected here, not nested under diagnoses. Treatments are "
            "nested under diagnoses."
            if follow_ups_nested_under_diagnosis == 0
            else "At least some follow-up records were nested under diagnoses."
        ),
    }
