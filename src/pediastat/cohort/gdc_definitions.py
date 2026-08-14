"""Official GDC field definitions used to lock the OS time origin.

Citations are from the GDC Data Dictionary ``_terms.yaml`` (caDSR CDEs)
and GDC submission / clinical-harmonization documentation. These texts
are recorded so the endpoint is not inferred from field names alone.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

# GDC Data Dictionary (gdcdictionary _terms.yaml), retrieved 2026-08-14.
DAYS_TO_DEATH = {
    "field": "demographic.days_to_death",
    "cde_id": 6154724,
    "cde_version": "1.0",
    "term": "Index Date to Death Day Count",
    "description": (
        "Number of days between the date used for index and the date from a "
        "person's date of death represented as a calculated number of days."
    ),
    "source": "GDC Data Dictionary / caDSR",
}

DAYS_TO_LAST_FOLLOW_UP = {
    "field": "diagnoses.days_to_last_follow_up",
    "cde_id": 3008273,
    "cde_version": "1.0",
    "term": (
        "Last Communication Contact Less Initial Pathologic Diagnosis Date "
        "Calculated Day Value"
    ),
    "description": (
        "Time interval from the date of last follow up to the date of initial "
        "pathologic diagnosis, represented as a calculated number of days."
    ),
    "source": "GDC Data Dictionary / caDSR",
}

AGE_AT_DIAGNOSIS = {
    "field": "diagnoses.age_at_diagnosis",
    "cde_id": 3225640,
    "cde_version": "2.0",
    "term": "Patient Diagnosis Age Day Value",
    "description": (
        "Age at the time of diagnosis expressed in number of days since birth."
    ),
    "source": "GDC Data Dictionary / caDSR",
}

DAYS_TO_DIAGNOSIS = {
    "field": "diagnoses.days_to_diagnosis",
    "cde_id": 6154733,
    "cde_version": "1.0",
    "term": "Index Date To Disease Diagnosis Day Count",
    "description": (
        "Number of days between the date used for index and the date the "
        "patient was diagnosed with the malignant disease."
    ),
    "source": "GDC Data Dictionary / caDSR",
}

GDC_INDEX_POLICY = (
    "GDC stores absolute clinical dates as intervals from the date of initial "
    "pathologic diagnosis. Events after diagnosis are positive; events before "
    "diagnosis are negative. The actual calendar date of diagnosis is not stored."
)

TIME_ORIGIN_CONCLUSION = (
    "days_to_last_follow_up is defined from initial pathologic diagnosis. "
    "days_to_death is defined from the GDC index date. GDC policy sets that "
    "index to initial pathologic diagnosis. In this TARGET-AML extract, "
    "index_date is Diagnosis and days_to_diagnosis is 0 whenever those fields "
    "are populated among Alive/Dead cases. The two OS time fields therefore "
    "share a scientifically coherent origin at diagnosis."
)


def verify_time_origin(
    cases: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Check that GDC index metadata is compatible with a diagnosis origin.

    Does not invent a new origin. Returns counts and a proceed/stop flag.
    """
    n = len(cases)
    n_index_diagnosis = 0
    n_index_missing = 0
    n_index_other = 0
    n_days_to_dx_zero = 0
    n_days_to_dx_nonzero = 0
    n_days_to_dx_missing = 0
    n_alive_dead_index_missing = 0
    n_dead_death_equals_last_fu_when_index_missing = 0
    for row in cases:
        index = row.get("index_date")
        status = str(row.get("vital_status") or "").strip().lower()
        days_to_dx = row.get("days_to_diagnosis")
        if index is None or str(index).strip() == "":
            n_index_missing += 1
            if status in {"alive", "dead"}:
                n_alive_dead_index_missing += 1
                death = row.get("days_to_death")
                follow = row.get("days_to_last_follow_up")
                if (
                    status == "dead"
                    and death is not None
                    and follow is not None
                    and float(death) == float(follow)
                ):
                    n_dead_death_equals_last_fu_when_index_missing += 1
        elif str(index).strip().lower() == "diagnosis":
            n_index_diagnosis += 1
        else:
            n_index_other += 1
        if days_to_dx is None:
            n_days_to_dx_missing += 1
        elif float(days_to_dx) == 0:
            n_days_to_dx_zero += 1
        else:
            n_days_to_dx_nonzero += 1
    coherent = n_index_other == 0 and n_days_to_dx_nonzero == 0
    return {
        "n_records_assessed": n,
        "n_index_diagnosis": n_index_diagnosis,
        "n_index_missing": n_index_missing,
        "n_index_other": n_index_other,
        "n_days_to_diagnosis_zero": n_days_to_dx_zero,
        "n_days_to_diagnosis_nonzero": n_days_to_dx_nonzero,
        "n_days_to_diagnosis_missing": n_days_to_dx_missing,
        "n_alive_dead_index_missing": n_alive_dead_index_missing,
        "n_dead_death_equals_last_fu_when_index_missing": (
            n_dead_death_equals_last_fu_when_index_missing
        ),
        "official_index_policy": GDC_INDEX_POLICY,
        "days_to_death": DAYS_TO_DEATH,
        "days_to_last_follow_up": DAYS_TO_LAST_FOLLOW_UP,
        "age_at_diagnosis": AGE_AT_DIAGNOSIS,
        "conclusion": TIME_ORIGIN_CONCLUSION,
        "origin_is_coherent": coherent,
        "proceed_with_endpoint": coherent,
    }
