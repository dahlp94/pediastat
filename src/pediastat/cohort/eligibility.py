"""Primary-cohort eligibility. Covariate completeness does not exclude."""

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
    endpoint = derive_os_endpoint(clinical)
    valid_identity = bool(identity.get("eligible_for_person_level_analysis"))
    conflict = bool(identity.get("identity_conflict"))

    flags = []
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
    elif not endpoint["has_valid_os_time"]:
        flags.append("invalid_status_specific_os_time")
    if endpoint["os_time_invalid_reason"]:
        flags.append(endpoint["os_time_invalid_reason"])

    reason = next(
        (item for item in PRIMARY_EXCLUSION_ORDER if item in flags),
        flags[0] if flags else None,
    )
    os_ok = endpoint["has_known_vital_status"] and endpoint["has_valid_os_time"]
    base_ok = valid_identity and not conflict and has_diagnosis and os_ok
    primary = base_ok and endpoint["has_age"] and endpoint["age_eligible_lt18"]

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
        "sensitivity_le21_eligible": (
            base_ok and endpoint["has_age"] and endpoint["age_eligible_le21"]
        ),
        "sensitivity_unrestricted_age_eligible": base_ok,
        "primary_exclusion_reason": None if primary else reason,
        "all_exclusion_flags": flags,
        "age_at_diagnosis_days": endpoint["age_at_diagnosis_days"],
        "age_at_diagnosis_years": endpoint["age_at_diagnosis_years"],
        "vital_status": clinical.get("vital_status"),
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
    rows = list(eligibility_rows)
    steps = []
    remaining = len(rows)

    def step(name: str, kept: list[Mapping[str, Any]], note: str) -> None:
        nonlocal remaining
        before = remaining
        remaining = len(kept)
        steps.append(
            {
                "criterion": name,
                "unit": "analysis_person",
                "n_before": before,
                "n_excluded": before - remaining,
                "n_remaining": remaining,
                "notes": note,
            }
        )

    step(
        "all_mapped_analysis_persons",
        rows,
        "Every GDC case was assigned an analysis-person key, including "
        "ineligible identities.",
    )
    valid = [row for row in rows if row["has_valid_identity"]]
    step(
        "valid_analysis_person_identity",
        valid,
        "Unambiguous TARGET-20/21 6-character USI, including "
        "biospecimen-suffix collapse.",
    )
    with_dx = [row for row in valid if row["has_diagnosis"]]
    step("diagnosis_available", with_dx, "GDC diagnosis entity present.")
    with_age = [row for row in with_dx if row["has_age"]]
    step(
        "age_available",
        with_age,
        "GDC diagnoses.age_at_diagnosis present and non-negative.",
    )
    pediatric = [row for row in with_age if row["age_eligible_lt18"]]
    step(
        "age_at_diagnosis_lt_18",
        pediatric,
        "Primary eligibility: age_at_diagnosis_days / 365.25 < 18. "
        "Not chosen to maximize N.",
    )
    known = [row for row in pediatric if row["has_known_vital_status"]]
    step(
        "vital_status_alive_or_dead",
        known,
        "Unknown / Not Reported / missing vital status excluded, not censored.",
    )
    valid_os = [row for row in known if row["has_valid_os_time"]]
    step(
        "valid_status_specific_os_time",
        valid_os,
        "Dead requires days_to_death >= 0; Alive requires "
        "days_to_last_follow_up >= 0.",
    )
    return steps
