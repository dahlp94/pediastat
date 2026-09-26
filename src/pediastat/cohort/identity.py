"""Resolve GDC cases to analysis-person identity without guessing."""

from __future__ import annotations

import re
from collections import defaultdict
from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.ingestion.identifiers import join_barcode, normalize_identifier
from pediastat.ingestion.missingness import is_observed

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
