"""Build and validate the TARGET-AML analysis cohort and OS endpoint.

This module consolidates identity resolution, eligibility, endpoint derivation,
baseline-covariate reconciliation, GDC time-origin checks, cohort persistence,
and cohort QA. Scientific rules and source precedence are intentionally frozen.
"""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from collections.abc import Mapping, Sequence
from pathlib import Path
from statistics import median
from typing import Any

from sqlalchemy import MetaData, Table, text
from sqlalchemy.engine import Engine

from pediastat.config import PROJECT_ROOT
from pediastat.database import apply_sql_file
from pediastat.gdc import classify_vital_status
from pediastat.ingest import (
    DAYS_PER_YEAR,
    _as_number,
    _norm_category,
    categorical_agreement,
    classify_missing,
    days_to_years,
    is_observed,
    join_barcode,
    normalize_identifier,
    numeric_discordance,
)

# GDC definitions and time-origin verification

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


# Overall-survival endpoint derivation

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


# Cohort eligibility and attrition

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


# Analysis-person identity resolution

PATIENT_USI = re.compile(r"^TARGET-(20|21)-[A-Z0-9]{6}$")
EXTENDED_PATIENT = re.compile(r"^(TARGET-(?:20|21)-[A-Z0-9]{6})-(.+)$")
SHORT_D_TOKEN = re.compile(r"^TARGET-20-D\d+$")
BIOSPECIMEN_SUFFIX = re.compile(r"^(UNSORTED|SORTED(?:-[A-Z0-9]+)*)$", re.I)
CELL_LINE_OR_CONSTRUCT = re.compile(
    r"^(HL60|KASUMI.*|MV411.*|MOLM14.*|MUTZ3|OCIAML2|REH|TF1|THP1|ML1|"
    r"CMS|CB34POS|ECANDCBTRANSFEREXP|RO\d+)$",
    re.I,
)

IDENTITY_CANONICAL = "canonical_usi"
IDENTITY_EXTENDED = "extended_usi_collapsed_to_canonical"
IDENTITY_D_TOKEN = "ambiguous_experimental_d_token"
IDENTITY_EXPERIMENT = "ambiguous_experimental_construct"
IDENTITY_NOT_PATIENT = "not_patient_identifier"

COMPAT_FIELDS = (
    "vital_status",
    "days_to_death",
    "days_to_last_follow_up",
    "age_at_diagnosis_days",
    "sex_at_birth",
    "race",
    "ethnicity",
)


def _result(
    original: str | None,
    normalized: str | None,
    barcode: str | None,
    person_id: str | None,
    rule: str,
    reason: str | None = None,
) -> dict[str, Any]:
    eligible = reason is None
    return {
        "original_identifier": original,
        "normalized_identifier": normalized,
        "join_barcode": barcode,
        "analysis_person_id": person_id,
        "identity_rule": rule,
        "identity_confidence": "high" if eligible else "ineligible",
        "eligible_for_person_level_analysis": eligible,
        "exclusion_reason": reason,
    }


def classify_identifier(submitter_id: Any) -> dict[str, Any]:
    original = None if submitter_id is None else str(submitter_id)
    normalized = normalize_identifier(submitter_id)
    barcode = join_barcode(submitter_id)

    if normalized is None or barcode is None:
        return _result(
            original, normalized, barcode, None,
            IDENTITY_NOT_PATIENT, "missing_identifier",
        )
    if SHORT_D_TOKEN.match(barcode):
        return _result(
            original, normalized, barcode, normalized,
            IDENTITY_D_TOKEN, "ambiguous_experimental_d_token",
        )

    token = barcode.split("-")[-1]
    experimental = (
        token.upper() in {"CB34POS", "ECANDCBTRANSFEREXP"}
        or "ECANDCB" in barcode.upper()
        or "CB34POS" in barcode.upper()
    )
    if CELL_LINE_OR_CONSTRUCT.match(token) or barcode.startswith("TARGET-00-"):
        return _result(
            original,
            normalized,
            barcode,
            normalized,
            IDENTITY_EXPERIMENT if experimental else IDENTITY_NOT_PATIENT,
            "ambiguous_experimental_construct" if experimental
            else "not_patient_identifier",
        )

    if PATIENT_USI.match(barcode) and PATIENT_USI.match(normalized):
        return _result(
            original, normalized, barcode, barcode, IDENTITY_CANONICAL
        )

    extended = EXTENDED_PATIENT.match(normalized)
    if extended and BIOSPECIMEN_SUFFIX.match(extended.group(2)):
        return _result(
            original, normalized, barcode, extended.group(1), IDENTITY_EXTENDED
        )

    reason = (
        "extended_identifier_not_mapped"
        if PATIENT_USI.match(barcode)
        else "not_patient_identifier"
    )
    return _result(
        original, normalized, barcode, normalized, IDENTITY_NOT_PATIENT, reason
    )


def _norm(value: Any) -> str | None:
    if not is_observed(value):
        return None
    return " ".join(str(value).strip().lower().split())


def compare_person_records(
    rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    conflicts = [
        field
        for field in COMPAT_FIELDS
        if len({_norm(row.get(field)) for row in rows} - {None}) > 1
    ]
    return {
        "n_gdc_cases": len(rows),
        "conflict_fields": conflicts,
        "records_compatible": not conflicts,
        "identity_conflict": bool(conflicts),
    }


def _representative_key(row: Mapping[str, Any]) -> tuple[Any, ...]:
    normalized = str(row.get("normalized_identifier") or "")
    barcode = str(row.get("join_barcode") or "")
    return (
        not bool(row.get("has_clinical")),
        not normalized.endswith("-UNSORTED"),
        normalized != barcode,
        str(row.get("case_id") or ""),
    )


def build_identity_crosswalk(
    cases: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    by_person: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for case in cases:
        identity = classify_identifier(case.get("submitter_id"))
        person_id = identity["analysis_person_id"] or str(case.get("case_id"))
        by_person[person_id].append(
            {
                "case_id": case.get("case_id"),
                "submitter_id": case.get("submitter_id"),
                **identity,
                "analysis_person_id": person_id,
                "has_clinical": (
                    case.get("vital_status") is not None
                    or case.get("age_at_diagnosis_days") is not None
                ),
                **{field: case.get(field) for field in COMPAT_FIELDS},
            }
        )

    output = []
    for _person_id, rows in by_person.items():
        comparison = compare_person_records(rows)
        if comparison["identity_conflict"]:
            for row in rows:
                if row["eligible_for_person_level_analysis"]:
                    row.update(
                        eligible_for_person_level_analysis=False,
                        exclusion_reason="identity_record_conflict",
                        identity_confidence="conflict",
                    )

        representative = min(rows, key=_representative_key)
        for row in rows:
            output.append(
                {
                    key: row[key]
                    for key in (
                        "case_id",
                        "submitter_id",
                        "original_identifier",
                        "normalized_identifier",
                        "join_barcode",
                        "analysis_person_id",
                        "identity_rule",
                        "identity_confidence",
                        "eligible_for_person_level_analysis",
                        "exclusion_reason",
                    )
                }
                | {
                    "n_gdc_cases_for_person": comparison["n_gdc_cases"],
                    "is_representative_case": (
                        row["case_id"] == representative["case_id"]
                    ),
                    "records_compatible": comparison["records_compatible"],
                    "identity_conflict": comparison["identity_conflict"],
                    "conflict_fields": comparison["conflict_fields"],
                }
            )
    return output


def summarize_identity(
    crosswalk: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    eligible = [
        row for row in crosswalk if row["eligible_for_person_level_analysis"]
    ]
    ineligible = [
        row for row in crosswalk if not row["eligible_for_person_level_analysis"]
    ]
    reasons: dict[str, int] = defaultdict(int)
    for row in ineligible:
        reasons[str(row.get("exclusion_reason") or "unspecified")] += 1

    # Access these standard categories so zero counts remain explicit in the
    # summary, matching the historical artifact shape.
    for reason in (
        "ambiguous_experimental_d_token",
        "ambiguous_experimental_construct",
        "not_patient_identifier",
        "identity_record_conflict",
    ):
        reasons[reason]

    return {
        "n_gdc_cases": len(crosswalk),
        "n_analysis_person_keys": len(
            {row["analysis_person_id"] for row in crosswalk}
        ),
        "n_gdc_cases_valid_identity": len(eligible),
        "n_valid_analysis_persons": len(
            {row["analysis_person_id"] for row in eligible}
        ),
        "n_gdc_cases_ineligible_identity": len(ineligible),
        "n_excluded_ambiguous_experimental_d_token": reasons[
            "ambiguous_experimental_d_token"
        ],
        "n_excluded_ambiguous_experimental_construct": reasons[
            "ambiguous_experimental_construct"
        ],
        "n_excluded_not_patient_identifier": reasons["not_patient_identifier"],
        "n_excluded_identity_record_conflict": reasons[
            "identity_record_conflict"
        ],
        "n_multi_case_persons": sum(
            (row.get("n_gdc_cases_for_person") or 1) > 1
            and bool(row.get("is_representative_case"))
            for row in eligible
        ),
        "max_gdc_cases_per_person": max(
            (row.get("n_gdc_cases_for_person") or 1 for row in crosswalk),
            default=0,
        ),
        "identity_exclusion_reasons": dict(reasons),
    }


# Baseline covariate reconciliation

MOLECULAR_ORDER = ("AML1031", "Discovery", "Validation", "LowDepth", "additional")
FAB_ORDER = ("Discovery", "Validation", "LowDepth", "additional", "AML1031")
CYTO_CODE_ORDER = ("Discovery", "Validation", "AML1031", "LowDepth", "additional")

# concept, source column, units, precedence, kind, viability
_SUPPLEMENT_SPECS = (
    (
        "wbc_at_diagnosis", "WBC at Diagnosis", "x10^3/mcL",
        MOLECULAR_ORDER, "numeric", "CORE CANDIDATE",
    ),
    (
        "risk_group", "Risk group", None,
        MOLECULAR_ORDER, "categorical", "CORE CANDIDATE",
    ),
    (
        "flt3_itd", "FLT3/ITD positive?", None,
        MOLECULAR_ORDER, "categorical", "CORE CANDIDATE",
    ),
    ("npm", "NPM mutation", None, MOLECULAR_ORDER, "categorical", "CORE CANDIDATE"),
    ("cebpa", "CEBPA mutation", None, MOLECULAR_ORDER, "categorical", "CORE CANDIDATE"),
    ("fab", "FAB Category", None, FAB_ORDER, "categorical", "SECONDARY CANDIDATE"),
    (
        "cns_disease", "CNS disease", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "marrow_blasts", "Bone marrow leukemic blast percentage (%)", "percent",
        MOLECULAR_ORDER, "numeric", "SECONDARY CANDIDATE",
    ),
    (
        "peripheral_blasts", "Peripheral blasts (%)", "percent",
        MOLECULAR_ORDER, "numeric", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_t821", "t(8;21)", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_inv16", "inv(16)", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_mll", "MLL", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_monosomy7", "monosomy 7", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "primary_cytogenetic_code", "Primary Cytogenetic Code", None,
        CYTO_CODE_ORDER, "categorical", "NEEDS REVIEW",
    ),
)

SUPPLEMENT_CONCEPTS = tuple(
    {
        "concept": concept,
        "column": column,
        "units": units,
        "precedence": precedence,
        "kind": kind,
        "viability": viability,
    }
    for concept, column, units, precedence, kind, viability in _SUPPLEMENT_SPECS
)

# concept, source column, units, viability, joined-case field
_GDC_SPECS = (
    (
        "age_at_diagnosis_days", "diagnoses.age_at_diagnosis", "days",
        "CORE CANDIDATE", "age_at_diagnosis_days",
    ),
    (
        "sex_at_birth", "demographic.sex_at_birth", None,
        "CORE CANDIDATE", "sex_at_birth",
    ),
    ("race", "demographic.race", None, "SECONDARY CANDIDATE", "race"),
    ("ethnicity", "demographic.ethnicity", None, "SECONDARY CANDIDATE", "ethnicity"),
)

GDC_CONCEPTS = tuple(
    {
        "concept": concept,
        "column": column,
        "units": units,
        "viability": viability,
        "field": field,
    }
    for concept, column, units, viability, field in _GDC_SPECS
)

VIABILITY_NOTES = {
    "age_at_diagnosis_days": "Baseline timing; GDC preferred; used for eligibility.",
    "sex_at_birth": "GDC demographic field; CDE Gender is not substituted.",
    "race": "Scientifically interpretable but substantial Unknown/not reported.",
    "ethnicity": "Scientifically interpretable but substantial Unknown/not reported.",
    "wbc_at_diagnosis": (
        "Baseline laboratory measure; AML1031 complete; overlaps agree."
    ),
    "risk_group": (
        "Protocol AML risk; AML1031 nearly complete; small LowDepth disagreements."
    ),
    "flt3_itd": "Baseline molecular marker; complete in AML1031.",
    "npm": "Baseline molecular marker; complete in AML1031.",
    "cebpa": "Baseline molecular marker; complete in AML1031.",
    "fab": "Baseline morphology; AML1031 nearly empty so not preferred.",
    "cns_disease": "Baseline CNS involvement; additional file mostly Unknown.",
    "marrow_blasts": "Baseline disease burden; modest missingness.",
    "peripheral_blasts": "Baseline disease burden; modest missingness.",
    "cytogenetics_t821": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_inv16": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_mll": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_monosomy7": "Lesion flag retained; not collapsed into a composite.",
    "primary_cytogenetic_code": (
        "Summary code disagrees with LowDepth in overlaps; not assumed "
        "equivalent to lesion flags."
    ),
}

NOT_RECOMMENDED = tuple(
    {"concept": concept, "viability": "NOT RECOMMENDED", "note": note}
    for concept, note in (
        (
            "protocol_identifier",
            "Possible stratifier, not a biological baseline exposure.",
        ),
        ("primary_diagnosis", "No variation (AML NOS only) on the Cases API."),
        ("mrd_end_course_1", "Post-baseline response measure."),
        ("sct_in_first_cr", "Post-baseline treatment; immortal-time risk."),
        ("gemtuzumab", "Post-baseline treatment; no start day on Cases API."),
        ("first_event", "Outcome/EFS construct, not a baseline covariate."),
    )
)


def workbook_family(workbook_name: str | None) -> str | None:
    if not workbook_name:
        return None
    name = workbook_name.lower()
    rules = (
        ("additional", ("additional", "sortedcells")),
        ("LowDepth", ("lowdepth",)),
        ("Validation", ("validation",)),
        ("Discovery", ("discovery",)),
        ("AML1031", ("aml1031",)),
    )
    if "discovery" in name and "validation" in name:
        return None
    return next(
        (family for family, tokens in rules if any(token in name for token in tokens)),
        None,
    )


def _values_conflict(kind: str, left: Any, right: Any) -> bool:
    if not is_observed(left) or not is_observed(right):
        return False
    if kind == "numeric":
        left_n, right_n = _as_number(left), _as_number(right)
        if left_n is not None and right_n is not None:
            return left_n != right_n
    return _norm_category(left) != _norm_category(right)


def reconcile_supplement_concept(
    *,
    concept: Mapping[str, Any],
    rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Choose one value by locked workbook precedence; never average."""
    column = concept["column"]
    order = {name: rank for rank, name in enumerate(concept["precedence"])}
    candidates = []

    for row in rows:
        family = workbook_family(row.get("workbook_name"))
        if family not in order:
            continue
        cells = row.get("cells") if isinstance(row.get("cells"), dict) else {}
        candidates.append((order[family], row, cells.get(column, row.get(column))))

    observed = [item for item in candidates if is_observed(item[2])]
    ranked = sorted(
        observed or candidates,
        key=lambda item: (item[0], str(item[1].get("workbook_name"))),
    )
    if not ranked:
        return {
            "concept": concept["concept"],
            "value": None,
            "source_workbook": None,
            "source_column": column,
            "source_kind": "clinical_supplement",
            "conflict_flag": False,
            "alternative_source_count": 0,
            "missingness_class": "structurally_missing",
            "units": concept["units"],
        }

    value = ranked[0][2]
    observed_values = [item[2] for item in observed]
    conflict = len(observed_values) > 1 and any(
        _values_conflict(concept["kind"], observed_values[0], other)
        for other in observed_values[1:]
    )
    return {
        "concept": concept["concept"],
        "value": None if value is None else str(value),
        "source_workbook": ranked[0][1].get("workbook_name"),
        "source_column": column,
        "source_kind": "clinical_supplement",
        "conflict_flag": conflict,
        "alternative_source_count": max(len(observed) - 1, 0),
        "missingness_class": classify_missing(value),
        "units": concept["units"],
    }


def reconcile_person_baselines(
    *,
    analysis_person_id: str,
    gdc: Mapping[str, Any],
    supplement_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    rows = []
    for item in GDC_CONCEPTS:
        value = gdc.get(item["field"])
        rows.append(
            {
                "analysis_person_id": analysis_person_id,
                "concept": item["concept"],
                "value": None if value is None else str(value),
                "source_workbook": None,
                "source_column": item["column"],
                "source_kind": "gdc_cases_api",
                "conflict_flag": False,
                "alternative_source_count": 0,
                "missingness_class": classify_missing(value),
                "units": item["units"],
            }
        )

    for concept in SUPPLEMENT_CONCEPTS:
        row = reconcile_supplement_concept(concept=concept, rows=supplement_rows)
        row["analysis_person_id"] = analysis_person_id
        rows.append(row)
    return rows


def availability_rows(
    *,
    primary_person_ids: Sequence[str],
    baseline_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Summarize baseline completeness without using outcome information."""
    primary = set(primary_person_ids)
    by_concept: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in baseline_rows:
        if row["analysis_person_id"] in primary:
            by_concept[str(row["concept"])].append(row)

    n = len(primary)
    catalog = {
        item["concept"]: item for item in (*GDC_CONCEPTS, *SUPPLEMENT_CONCEPTS)
    }
    out = []
    for concept, item in catalog.items():
        records = by_concept.get(concept, [])
        observed = sum(row["missingness_class"] == "observed" for row in records)
        missing = n - observed
        out.append(
            {
                "concept": concept,
                "primary_cohort_n": n,
                "observed_n": observed,
                "missing_n": missing,
                "missing_percent": round(missing / n * 100, 2) if n else None,
                "unknown_n": sum(
                    row["missingness_class"] == "unknown" for row in records
                ),
                "conflict_n": sum(bool(row.get("conflict_flag")) for row in records),
                "viability": item["viability"],
                "note": VIABILITY_NOTES.get(concept),
            }
        )

    out.extend(
        {
            "concept": item["concept"],
            "primary_cohort_n": n,
            "observed_n": None,
            "missing_n": None,
            "missing_percent": None,
            "unknown_n": None,
            "conflict_n": None,
            "viability": item["viability"],
            "note": item["note"],
        }
        for item in NOT_RECOMMENDED
    )
    return out


# Cohort build, persistence, validation, and artifacts

DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "cohort_definition"
DETAIL_DIR = PROJECT_ROOT / "data" / "interim" / "cohort_definition"
SQL_ANALYTICS = PROJECT_ROOT / "sql" / "07_create_analytics_tables.sql"


def _write(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".csv":
        rows = payload
        if not rows:
            path.write_text("", encoding="utf-8")
            return
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )


def _cells(row: dict[str, Any]) -> dict[str, Any]:
    value = row.get("cells")
    if isinstance(value, dict):
        return value
    return json.loads(value) if isinstance(value, str) else {}


def _fetch_staging(engine: Engine) -> dict[str, list[dict[str, Any]]]:
    queries = {
        "cases": "SELECT * FROM staging.gdc_cases",
        "demographics": "SELECT * FROM staging.gdc_demographics",
        "diagnoses": "SELECT * FROM staging.gdc_diagnoses",
        "supplements": """
            SELECT * FROM staging.supplement_clinical_rows
            WHERE sheet_name IN ('Clinical Data', 'Sheet1')
        """,
    }
    with engine.connect() as connection:
        return {
            name: [
                dict(row)
                for row in connection.execute(text(sql)).mappings()
            ]
            for name, sql in queries.items()
        }


def _joined_cases(data: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    demo = {
        row["case_id"]: row
        for row in data["demographics"]
        if row.get("case_id")
    }
    dx = {
        row["case_id"]: row
        for row in data["diagnoses"]
        if row.get("case_id")
    }
    out = []
    for case in data["cases"]:
        case_id = case["case_id"]
        demographic = demo.get(case_id, {})
        diagnosis = dx.get(case_id, {})
        out.append(
            {
                "case_id": case_id,
                "submitter_id": case.get("submitter_id"),
                "join_barcode": case.get("join_barcode"),
                "index_date": case.get("index_date"),
                "vital_status": demographic.get("vital_status_raw"),
                "days_to_death": demographic.get("days_to_death"),
                "sex_at_birth": demographic.get("sex_at_birth_raw"),
                "race": demographic.get("race_raw"),
                "ethnicity": demographic.get("ethnicity_raw"),
                "age_at_diagnosis_days": diagnosis.get(
                    "age_at_diagnosis_days"
                ),
                "days_to_diagnosis": diagnosis.get("days_to_diagnosis"),
                "days_to_last_follow_up": diagnosis.get(
                    "days_to_last_follow_up"
                ),
                "has_demographic": case_id in demo,
                "has_diagnosis": case_id in dx,
            }
        )
    return out


def apply_analytics_ddl(engine: Engine) -> None:
    apply_sql_file(engine, SQL_ANALYTICS.read_text(encoding="utf-8"))


def _replace_analytics(
    engine: Engine,
    *,
    crosswalk: list[dict[str, Any]],
    eligibility: list[dict[str, Any]],
    cohort: list[dict[str, Any]],
    baseline: list[dict[str, Any]],
) -> None:
    payloads = {
        "patient_identity_crosswalk": crosswalk,
        "cohort_eligibility": eligibility,
        "primary_os_cohort": cohort,
        "baseline_covariates_reconciled": baseline,
    }
    delete_order = reversed(tuple(payloads))
    metadata = MetaData()

    with engine.begin() as connection:
        tables = {
            name: Table(
                name,
                metadata,
                schema="analytics",
                autoload_with=connection,
            )
            for name in payloads
        }
        for name in delete_order:
            connection.execute(tables[name].delete())
        for name, rows in payloads.items():
            if rows:
                columns = set(tables[name].c.keys())
                clean = [
                    {key: value for key, value in row.items() if key in columns}
                    for row in rows
                ]
                connection.execute(tables[name].insert(), clean)


def _build_people(
    data: dict[str, list[dict[str, Any]]],
    joined: list[dict[str, Any]],
) -> tuple[
    list[dict[str, Any]],
    dict[str, Any],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    by_case = {row["case_id"]: row for row in joined}
    crosswalk = build_identity_crosswalk(joined)
    identity_summary = summarize_identity(crosswalk)

    supplements: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in data["supplements"]:
        if barcode := row.get("join_barcode"):
            item = dict(row)
            item["cells"] = _cells(item)
            supplements[barcode].append(item)

    eligibility = []
    cohort = []
    baseline = []
    for identity in (
        row for row in crosswalk if row["is_representative_case"]
    ):
        person = identity["analysis_person_id"]
        clinical = by_case.get(identity["case_id"], {})
        evaluated = evaluate_person(
            identity=identity,
            clinical=clinical,
            has_diagnosis=bool(clinical.get("has_diagnosis")),
        )
        eligibility.append(evaluated)
        baseline.extend(
            reconcile_person_baselines(
                analysis_person_id=person,
                gdc={
                    "age_at_diagnosis_days": clinical.get(
                        "age_at_diagnosis_days"
                    ),
                    "sex_at_birth": clinical.get("sex_at_birth"),
                    "race": clinical.get("race"),
                    "ethnicity": clinical.get("ethnicity"),
                },
                supplement_rows=supplements.get(person, []),
            )
        )
        if evaluated["primary_cohort_eligible"]:
            cohort.append(
                {
                    "analysis_person_id": person,
                    "gdc_case_id": identity["case_id"],
                    "submitter_id": identity["submitter_id"],
                    "age_at_diagnosis_days": evaluated[
                        "age_at_diagnosis_days"
                    ],
                    "age_at_diagnosis_years": evaluated[
                        "age_at_diagnosis_years"
                    ],
                    "vital_status": evaluated["vital_status"],
                    "os_event": evaluated["os_event"],
                    "os_days": evaluated["os_days"],
                    "os_years": evaluated["os_years"],
                    "os_time_source": evaluated["os_time_source"],
                    "os_event_source": (
                        evaluated["os_event_source"] or EVENT_SOURCE
                    ),
                    "identity_rule": identity["identity_rule"],
                    "source_provenance": "gdc_cases_api",
                    "qa_flags": {
                        "flags": evaluated["qa_flags"],
                        "n_gdc_cases_for_person": identity[
                            "n_gdc_cases_for_person"
                        ],
                    },
                }
            )
    return crosswalk, identity_summary, eligibility, cohort, baseline


def _attrition(
    joined: list[dict[str, Any]],
    identity: dict[str, Any],
    eligibility: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    n_cases = len(joined)
    n_valid = identity["n_gdc_cases_valid_identity"]
    n_people = identity["n_valid_analysis_persons"]
    rows = [
        {
            "criterion": "all_gdc_cases",
            "unit": "gdc_case",
            "n_before": n_cases,
            "n_excluded": 0,
            "n_remaining": n_cases,
            "notes": "TARGET-AML Cases API extract.",
        },
        {
            "criterion": "valid_analysis_person_identity",
            "unit": "gdc_case",
            "n_before": n_cases,
            "n_excluded": n_cases - n_valid,
            "n_remaining": n_valid,
            "notes": (
                "Canonical TARGET-20/21 6-character USI or "
                "biospecimen-suffix extension mapped to that USI."
            ),
        },
        {
            "criterion": "unique_valid_analysis_persons",
            "unit": "analysis_person",
            "n_before": n_valid,
            "n_excluded": 0,
            "n_remaining": n_people,
            "notes": (
                f"{n_valid} GDC cases map to {n_people} persons; "
                "extra cases are biospecimen-suffix duplicates, "
                "not exclusions."
            ),
        },
    ]
    rows.extend(sequential_attrition(eligibility)[2:])
    return rows


def _endpoint_summary(
    cohort: list[dict[str, Any]],
    origin: dict[str, Any],
) -> dict[str, Any]:
    times = [float(row["os_days"]) for row in cohort]
    deaths = sum(row["os_event"] == 1 for row in cohort)
    return {
        "primary_cohort_n": len(cohort),
        "deaths": deaths,
        "censored": len(cohort) - deaths,
        "event_percent": (
            round(deaths / len(cohort) * 100.0, 2) if cohort else None
        ),
        "os_days_min": min(times) if times else None,
        "os_days_median": median(times) if times else None,
        "os_days_max": max(times) if times else None,
        "n_zero_os_times": sum(day == 0 for day in times),
        "n_negative_os_times": sum(day < 0 for day in times),
        "n_missing_os_times": sum(row["os_days"] is None for row in cohort),
        "n_using_days_to_death": sum(
            row["os_time_source"].endswith("days_to_death") for row in cohort
        ),
        "n_using_days_to_last_follow_up": sum(
            row["os_time_source"].endswith("days_to_last_follow_up")
            for row in cohort
        ),
        "n_index_date_missing_qa_flag": sum(
            "index_date_missing" in row["qa_flags"]["flags"]
            for row in cohort
        ),
        "time_origin": origin["conclusion"],
        "note": (
            "No Kaplan-Meier estimate, log-rank test, or "
            "covariate-stratified survival summary was computed."
        ),
    }


def _supplement_os_qa(
    cohort: list[dict[str, Any]],
    supplements: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    primary = {row["analysis_person_id"]: row for row in cohort}
    grouped: dict[str, list[tuple[Any, Any, Any, Any]]] = defaultdict(list)

    for row in supplements:
        person = row.get("join_barcode")
        family = workbook_family(row.get("workbook_name"))
        if person in primary and family:
            gdc = primary[person]
            grouped[family].append(
                (
                    gdc["vital_status"],
                    row.get("vital_status_raw"),
                    gdc["os_days"],
                    row.get("os_time_days"),
                )
            )

    out = []
    for family, pairs in sorted(grouped.items()):
        status = categorical_agreement(
            [(a, b) for a, b, _, _ in pairs]
        )
        times = numeric_discordance(
            [(a, b) for _, _, a, b in pairs]
        )
        out.append(
            {
                "supplement_family": family,
                "overlap_n": len(pairs),
                "event_both_observed": status["n_both_observed"],
                "event_agreements": status["n_agreements"],
                "event_disagreements": status["n_disagreements"],
                "event_agreement_percent": status["agreement_percent"],
                "time_both_observed": times["n_both_observed"],
                "time_exact_agreements": times["n_exact_agreements"],
                "time_disagreements": times["n_disagreements"],
                "time_agreement_percent": times["agreement_percent"],
                "time_abs_diff_median": times["abs_diff_median"],
            }
        )
    return out


def _validate(
    engine: Engine,
    crosswalk: list[dict[str, Any]],
    eligibility: list[dict[str, Any]],
    cohort: list[dict[str, Any]],
    baseline: list[dict[str, Any]],
) -> dict[str, Any]:
    primary_ids = {row["analysis_person_id"] for row in cohort}
    unique_people = len(primary_ids)
    invalid_event = sum(
        row["vital_status"] not in {"Alive", "Dead"}
        or row["os_event"] not in {0, 1}
        for row in cohort
    )
    dead_bad = sum(
        row["os_event"] == 1
        and (
            row["os_time_source"] != "gdc.demographic.days_to_death"
            or row["os_days"] is None
            or row["os_days"] < 0
        )
        for row in cohort
    )
    alive_bad = sum(
        row["os_event"] == 0
        and (
            row["os_time_source"]
            != "gdc.diagnoses.days_to_last_follow_up"
            or row["os_days"] is None
            or row["os_days"] < 0
        )
        for row in cohort
    )
    excluded_without_reason = sum(
        not row["primary_cohort_eligible"]
        and not row["primary_exclusion_reason"]
        for row in eligibility
    )
    primary_with_reason = sum(
        row["primary_cohort_eligible"]
        and row["primary_exclusion_reason"] is not None
        for row in eligibility
    )
    missing_wbc = sum(
        row["analysis_person_id"] in primary_ids
        and row["concept"] == "wbc_at_diagnosis"
        and row["missingness_class"] != "observed"
        for row in baseline
    )
    with engine.connect() as connection:
        counts = connection.execute(
            text(
                """
                SELECT
                    (SELECT COUNT(*) FROM
                     analytics.patient_identity_crosswalk) AS crosswalk,
                    (SELECT COUNT(*) FROM
                     analytics.cohort_eligibility) AS eligibility,
                    (SELECT COUNT(*) FROM
                     analytics.primary_os_cohort) AS cohort
                """
            )
        ).mappings().one()

    negative_os = sum(row["os_days"] < 0 for row in cohort)
    adults = sum(row["age_at_diagnosis_years"] >= 18 for row in cohort)
    passed = all(
        (
            counts["crosswalk"] == len(crosswalk),
            counts["eligibility"] == len(eligibility),
            counts["cohort"] == len(cohort) == unique_people,
            invalid_event == dead_bad == alive_bad == 0,
            negative_os == adults == 0,
            excluded_without_reason == primary_with_reason == 0,
        )
    )
    return {
        "n_identity_crosswalk_rows": counts["crosswalk"],
        "n_eligibility_rows": counts["eligibility"],
        "n_primary_os_cohort": counts["cohort"],
        "n_unique_persons_in_cohort": unique_people,
        "n_unknown_or_invalid_event": invalid_event,
        "n_dead_invalid_time": dead_bad,
        "n_alive_invalid_time": alive_bad,
        "n_negative_os": negative_os,
        "n_age_ge_18_in_primary": adults,
        "n_excluded_missing_reason": excluded_without_reason,
        "n_primary_with_unobserved_wbc": missing_wbc,
        "passed": passed,
    }


def _write_artifacts(
    output_dir: Path,
    detail_dir: Path,
    payloads: dict[str, Any],
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    detail_dir.mkdir(parents=True, exist_ok=True)
    for filename, payload in payloads.items():
        _write(output_dir / filename, payload)


def build_primary_cohort(
    engine: Engine,
    output_dir: Path = DEFAULT_OUTPUT,
    detail_dir: Path = DETAIL_DIR,
) -> dict[str, Any]:
    """Build, validate, persist, and summarize the primary OS cohort."""
    apply_analytics_ddl(engine)
    data = _fetch_staging(engine)
    joined = _joined_cases(data)

    origin = verify_time_origin(joined)
    if not origin["proceed_with_endpoint"]:
        raise RuntimeError(
            "Official GDC OS time fields do not share a coherent origin "
            "in this extract; the primary endpoint was not created."
        )

    crosswalk, identity, eligibility, cohort, baseline = _build_people(
        data, joined
    )
    attrition = _attrition(joined, identity, eligibility)
    endpoint = _endpoint_summary(cohort, origin)
    sensitivity = {
        "primary_age_lt_18": sum(
            row["primary_cohort_eligible"] for row in eligibility
        ),
        "sensitivity_age_le_21": sum(
            row["sensitivity_le21_eligible"] for row in eligibility
        ),
        "sensitivity_unrestricted_age": sum(
            row["sensitivity_unrestricted_age_eligible"]
            for row in eligibility
        ),
        "note": "Eligibility flags only. No survival comparison was performed.",
    }
    availability = availability_rows(
        primary_person_ids=[row["analysis_person_id"] for row in cohort],
        baseline_rows=baseline,
    )
    os_qa = _supplement_os_qa(cohort, data["supplements"])

    _replace_analytics(
        engine,
        crosswalk=crosswalk,
        eligibility=eligibility,
        cohort=cohort,
        baseline=baseline,
    )
    validation = _validate(
        engine, crosswalk, eligibility, cohort, baseline
    )
    viability = {
        "core_candidate": [
            row["concept"]
            for row in availability
            if row["viability"] == "CORE CANDIDATE"
        ],
        "secondary_candidate": [
            row["concept"]
            for row in availability
            if row["viability"] == "SECONDARY CANDIDATE"
        ],
        "not_recommended": [item["concept"] for item in NOT_RECOMMENDED],
        "needs_review": [
            row["concept"]
            for row in availability
            if row["viability"] == "NEEDS REVIEW"
        ],
        "note": (
            "Viability is scientific/source-quality classification, "
            "not outcome-driven variable selection."
        ),
    }
    _write_artifacts(
        output_dir,
        detail_dir,
        {
            "cohort_attrition.csv": attrition,
            "cohort_attrition.json": attrition,
            "endpoint_summary.json": endpoint,
            "identity_resolution_summary.json": identity,
            "sensitivity_population_counts.json": sensitivity,
            "time_origin_verification.json": origin,
            "baseline_covariate_availability.csv": availability,
            "supplement_os_qa_summary.csv": os_qa,
            "variable_viability.json": viability,
            "database_validation.json": validation,
        },
    )
    return {
        "identity_summary": identity,
        "attrition": attrition,
        "endpoint_summary": endpoint,
        "sensitivity": sensitivity,
        "os_qa": os_qa,
        "availability": availability,
        "time_origin": origin,
        "database_validation": validation,
        "n_baseline_rows": len(baseline),
        "n_eligibility_rows": len(eligibility),
    }
