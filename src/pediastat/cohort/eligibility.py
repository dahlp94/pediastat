"""Sequential primary-cohort eligibility. Covariate completeness is not used."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.cohort.endpoint import derive_os_endpoint

PRIMARY_EXCLUSION_ORDER = (
    "invalid_analysis_person_identity",
    "identity_record_conflict",
    "diagnosis_unavailable",
    "age_unavailable",
    "age_not_lt_18",
    "vital_status_not_alive_or_dead",
    "invalid_status_specific_os_time",
)


def evaluate_person(
    *,
    identity: Mapping[str, Any],
    clinical: Mapping[str, Any],
    has_diagnosis: bool,
) -> dict[str, Any]:
    """Evaluate one analysis person. Missing covariates do not exclude."""
    endpoint = derive_os_endpoint(clinical)
    valid_identity = bool(identity.get("eligible_for_person_level_analysis"))
    conflict = bool(identity.get("identity_conflict"))
    flags: list[str] = []
    if not valid_identity:
        flags.append("invalid_analysis_person_identity")
        if identity.get("exclusion_reason"):
            flags.append(str(identity["exclusion_reason"]))
    if conflict:
        flags.append("identity_record_conflict")
    if not has_diagnosis:
        flags.append("diagnosis_unavailable")
    if not endpoint["has_age"]:
        flags.append("age_unavailable")
    elif not endpoint["age_eligible_lt18"]:
        flags.append("age_not_lt_18")
    if not endpoint["has_known_vital_status"]:
        flags.append("vital_status_not_alive_or_dead")
        if endpoint["os_time_invalid_reason"]:
            flags.append(endpoint["os_time_invalid_reason"])
    elif not endpoint["has_valid_os_time"]:
        flags.append("invalid_status_specific_os_time")
        if endpoint["os_time_invalid_reason"]:
            flags.append(endpoint["os_time_invalid_reason"])

    primary_reason = next(
        (item for item in PRIMARY_EXCLUSION_ORDER if item in flags),
        flags[0] if flags else None,
    )
    os_ok = endpoint["has_known_vital_status"] and endpoint["has_valid_os_time"]
    primary = (
        valid_identity
        and not conflict
        and has_diagnosis
        and endpoint["has_age"]
        and endpoint["age_eligible_lt18"]
        and os_ok
    )
    sensitivity_le21 = (
        valid_identity
        and not conflict
        and has_diagnosis
        and endpoint["has_age"]
        and endpoint["age_eligible_le21"]
        and os_ok
    )
    sensitivity_unrestricted = (
        valid_identity and not conflict and has_diagnosis and os_ok
    )
    return {
        "analysis_person_id": identity.get("analysis_person_id"),
        "representative_case_id": identity.get("case_id"),
        "submitter_id": identity.get("submitter_id"),
        "has_valid_identity": valid_identity and not conflict,
        "has_diagnosis": has_diagnosis,
        "has_age": endpoint["has_age"],
        "age_eligible_lt18": bool(endpoint["age_eligible_lt18"]),
        "age_eligible_le21": bool(endpoint["age_eligible_le21"]),
        "has_known_vital_status": endpoint["has_known_vital_status"],
        "has_valid_os_time": endpoint["has_valid_os_time"],
        "records_compatible": not conflict,
        "identity_conflict": conflict,
        "primary_cohort_eligible": primary,
        "sensitivity_le21_eligible": sensitivity_le21,
        "sensitivity_unrestricted_age_eligible": sensitivity_unrestricted,
        "primary_exclusion_reason": None if primary else primary_reason,
        "all_exclusion_flags": flags,
        "age_at_diagnosis_days": endpoint["age_at_diagnosis_days"],
        "age_at_diagnosis_years": endpoint["age_at_diagnosis_years"],
        "vital_status": clinical.get("vital_status")
        if endpoint["has_known_vital_status"]
        else clinical.get("vital_status"),
        "os_event": endpoint["os_event"],
        "os_days": endpoint["os_days"],
        "os_years": endpoint["os_years"],
        "os_time_source": endpoint["os_time_source"],
        "os_event_source": endpoint["os_event_source"],
        "qa_flags": endpoint["qa_flags"],
        "identity_rule": identity.get("identity_rule"),
        "endpoint": endpoint,
    }


def sequential_attrition(
    eligibility_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Person-level sequential attrition. Covariates are not criteria."""
    rows = list(eligibility_rows)
    n_start = len(rows)

    def _count(predicate) -> int:
        return sum(1 for row in rows if predicate(row))

    remaining = n_start
    steps: list[dict[str, Any]] = []

    def _step(name: str, excluded: int, notes: str) -> None:
        nonlocal remaining
        before = remaining
        remaining = before - excluded
        steps.append(
            {
                "criterion": name,
                "unit": "analysis_person",
                "n_before": before,
                "n_excluded": excluded,
                "n_remaining": remaining,
                "notes": notes,
            }
        )

    _step(
        "all_mapped_analysis_persons",
        0,
        "Every GDC case was assigned an analysis-person key, "
        "including ineligible identities.",
    )
    n_invalid = _count(lambda row: not row["has_valid_identity"])
    _step(
        "valid_analysis_person_identity",
        n_invalid,
        "Unambiguous TARGET-20/21 6-character USI, including "
        "biospecimen-suffix collapse.",
    )
    valid = [row for row in rows if row["has_valid_identity"]]
    n_no_dx = sum(1 for row in valid if not row["has_diagnosis"])
    _step("diagnosis_available", n_no_dx, "GDC diagnosis entity present.")
    with_dx = [row for row in valid if row["has_diagnosis"]]
    n_no_age = sum(1 for row in with_dx if not row["has_age"])
    _step(
        "age_available",
        n_no_age,
        "GDC diagnoses.age_at_diagnosis present and non-negative.",
    )
    with_age = [row for row in with_dx if row["has_age"]]
    n_adult = sum(1 for row in with_age if not row["age_eligible_lt18"])
    _step(
        "age_at_diagnosis_lt_18",
        n_adult,
        "Primary eligibility: age_at_diagnosis_days / 365.25 < 18. "
        "Not chosen to maximize N.",
    )
    pediatric = [row for row in with_age if row["age_eligible_lt18"]]
    n_bad_status = sum(1 for row in pediatric if not row["has_known_vital_status"])
    _step(
        "vital_status_alive_or_dead",
        n_bad_status,
        "Unknown / Not Reported / missing vital status excluded, not censored.",
    )
    known = [row for row in pediatric if row["has_known_vital_status"]]
    n_bad_time = sum(1 for row in known if not row["has_valid_os_time"])
    _step(
        "valid_status_specific_os_time",
        n_bad_time,
        "Dead requires days_to_death >= 0; Alive requires days_to_last_follow_up >= 0.",
    )
    return steps
