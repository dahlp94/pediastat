"""Primary overall-survival endpoint derivation.

Event source: GDC demographic.vital_status.
Time source: days_to_death if Dead; diagnoses.days_to_last_follow_up if Alive.
Unknown / Not Reported / missing vital status are never treated as censored.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from pediastat.audit.survival import classify_vital_status
from pediastat.reconciliation.age import DAYS_PER_YEAR, days_to_years

EVENT_SOURCE = "gdc.demographic.vital_status"
TIME_SOURCE_DEATH = "gdc.demographic.days_to_death"
TIME_SOURCE_LAST_FOLLOW_UP = "gdc.diagnoses.days_to_last_follow_up"
PRIMARY_AGE_YEARS = 18.0
SENSITIVITY_AGE_YEARS = 21.0
IMPLAUSIBLE_OS_DAYS = 365.25 * 50


def _as_float(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number:
        return None
    return number


def derive_os_endpoint(row: Mapping[str, Any]) -> dict[str, Any]:
    """Derive OS event and time for one person/case. Does not apply age rules."""
    status_raw = row.get("vital_status")
    status_class = classify_vital_status(status_raw)
    death = _as_float(row.get("days_to_death"))
    last_fu = _as_float(row.get("days_to_last_follow_up"))
    age_days = _as_float(row.get("age_at_diagnosis_days"))
    age_years = days_to_years(age_days)

    event: int | None = None
    os_days: float | None = None
    time_source: str | None = None
    time_invalid_reason: str | None = None
    known_vital = status_class in {"alive", "dead"}

    if status_class == "dead":
        event = 1
        time_source = TIME_SOURCE_DEATH
        if death is None:
            time_invalid_reason = "dead_missing_days_to_death"
        elif death < 0:
            time_invalid_reason = "negative_os_time"
        else:
            os_days = death
    elif status_class == "alive":
        event = 0
        time_source = TIME_SOURCE_LAST_FOLLOW_UP
        if last_fu is None:
            time_invalid_reason = "alive_missing_days_to_last_follow_up"
        elif last_fu < 0:
            time_invalid_reason = "negative_os_time"
        else:
            os_days = last_fu
    elif status_class == "other":
        time_invalid_reason = "vital_status_unknown_or_not_reported"
    else:
        time_invalid_reason = "vital_status_missing"

    qa_flags: list[str] = []
    if os_days == 0:
        qa_flags.append("zero_os_time")
    if os_days is not None and os_days > IMPLAUSIBLE_OS_DAYS:
        qa_flags.append("implausible_large_os_time")
    if not row.get("index_date"):
        qa_flags.append("index_date_missing")
    index_days = _as_float(row.get("days_to_diagnosis"))
    if known_vital and index_days is None:
        qa_flags.append("days_to_diagnosis_missing")

    return {
        "vital_status_raw": status_raw,
        "vital_status_class": status_class,
        "has_known_vital_status": known_vital,
        "os_event": event,
        "os_days": os_days,
        "os_years": None if os_days is None else os_days / DAYS_PER_YEAR,
        "os_time_source": time_source,
        "os_event_source": EVENT_SOURCE if known_vital else None,
        "has_valid_os_time": os_days is not None and time_invalid_reason is None,
        "os_time_invalid_reason": time_invalid_reason,
        "age_at_diagnosis_days": age_days,
        "age_at_diagnosis_years": age_years,
        "has_age": age_years is not None,
        "age_eligible_lt18": age_years is not None and age_years < PRIMARY_AGE_YEARS,
        "age_eligible_le21": (
            age_years is not None and age_years <= SENSITIVITY_AGE_YEARS
        ),
        "qa_flags": qa_flags,
    }
