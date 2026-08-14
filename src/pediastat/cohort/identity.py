"""Map GDC cases to analysis-person identity without guessing.

GDC ``case_id`` is retained. Analysis-person identity is assigned only when
a canonical TARGET patient USI can be established from identifier structure.
Short experimental ``D#`` tokens, cell-line names, and TARGET-00 barcodes
are not treated as unique patients.
"""

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
BIOSPECIMEN_SUFFIX = re.compile(
    r"^(UNSORTED|SORTED(?:-[A-Z0-9]+)*)$",
    re.IGNORECASE,
)
CELL_LINE_OR_CONSTRUCT = re.compile(
    r"^(HL60|KASUMI.*|MV411.*|MOLM14.*|MUTZ3|OCIAML2|REH|TF1|THP1|ML1|"
    r"CMS|CB34POS|ECANDCBTRANSFEREXP|RO\d+)$",
    re.IGNORECASE,
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


def _norm_compare(value: Any) -> str | None:
    if not is_observed(value):
        return None
    if isinstance(value, str):
        return " ".join(value.strip().lower().split())
    return str(value).strip().lower()


def classify_identifier(submitter_id: Any) -> dict[str, Any]:
    """Return identity mapping for one GDC submitter_id."""
    original = None if submitter_id is None else str(submitter_id)
    normalized = normalize_identifier(submitter_id)
    barcode = join_barcode(submitter_id)
    if normalized is None or barcode is None:
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": None,
            "identity_rule": IDENTITY_NOT_PATIENT,
            "identity_confidence": "ineligible",
            "eligible_for_person_level_analysis": False,
            "exclusion_reason": "missing_identifier",
        }
    if SHORT_D_TOKEN.match(barcode):
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": normalized,
            "identity_rule": IDENTITY_D_TOKEN,
            "identity_confidence": "ineligible",
            "eligible_for_person_level_analysis": False,
            "exclusion_reason": "ambiguous_experimental_d_token",
        }
    token = barcode.split("-")[-1]
    if CELL_LINE_OR_CONSTRUCT.match(token) or barcode.startswith("TARGET-00-"):
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": normalized,
            "identity_rule": (
                IDENTITY_EXPERIMENT
                if token.upper() in {"CB34POS", "ECANDCBTRANSFEREXP"}
                or "ECANDCB" in barcode.upper()
                or "CB34POS" in barcode.upper()
                else IDENTITY_NOT_PATIENT
            ),
            "identity_confidence": "ineligible",
            "eligible_for_person_level_analysis": False,
            "exclusion_reason": (
                "ambiguous_experimental_construct"
                if token.upper() in {"CB34POS", "ECANDCBTRANSFEREXP"}
                or "ECANDCB" in barcode.upper()
                or "CB34POS" in barcode.upper()
                else "not_patient_identifier"
            ),
        }
    if PATIENT_USI.match(barcode) and PATIENT_USI.match(normalized):
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": barcode,
            "identity_rule": IDENTITY_CANONICAL,
            "identity_confidence": "high",
            "eligible_for_person_level_analysis": True,
            "exclusion_reason": None,
        }
    extended = EXTENDED_PATIENT.match(normalized)
    if extended and BIOSPECIMEN_SUFFIX.match(extended.group(2)):
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": extended.group(1),
            "identity_rule": IDENTITY_EXTENDED,
            "identity_confidence": "high",
            "eligible_for_person_level_analysis": True,
            "exclusion_reason": None,
        }
    if PATIENT_USI.match(barcode):
        # Canonical join barcode with a non-biospecimen suffix: do not collapse.
        return {
            "original_identifier": original,
            "normalized_identifier": normalized,
            "join_barcode": barcode,
            "analysis_person_id": normalized,
            "identity_rule": IDENTITY_NOT_PATIENT,
            "identity_confidence": "ineligible",
            "eligible_for_person_level_analysis": False,
            "exclusion_reason": "extended_identifier_not_mapped",
        }
    return {
        "original_identifier": original,
        "normalized_identifier": normalized,
        "join_barcode": barcode,
        "analysis_person_id": normalized,
        "identity_rule": IDENTITY_NOT_PATIENT,
        "identity_confidence": "ineligible",
        "eligible_for_person_level_analysis": False,
        "exclusion_reason": "not_patient_identifier",
    }


def _representative_sort_key(row: Mapping[str, Any]) -> tuple[Any, ...]:
    normalized = str(row.get("normalized_identifier") or "")
    barcode = str(row.get("join_barcode") or "")
    has_clinical = 0 if row.get("has_clinical") else 1
    unsorted = 0 if normalized.endswith("-UNSORTED") else 1
    canonical = 0 if normalized == barcode else 1
    return (has_clinical, unsorted, canonical, str(row.get("case_id") or ""))


def compare_person_records(
    rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Compare clinical fields across GDC cases mapped to one person."""
    conflicts: list[str] = []
    for field in COMPAT_FIELDS:
        observed = [_norm_compare(row.get(field)) for row in rows]
        present = [item for item in observed if item is not None]
        if len(set(present)) > 1:
            conflicts.append(field)
    return {
        "n_gdc_cases": len(rows),
        "conflict_fields": conflicts,
        "records_compatible": not conflicts,
        "identity_conflict": bool(conflicts),
    }


def build_identity_crosswalk(
    cases: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Assign analysis-person IDs and mark a representative GDC case."""
    assigned: list[dict[str, Any]] = []
    by_person: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case in cases:
        mapped = classify_identifier(case.get("submitter_id"))
        person_id = mapped["analysis_person_id"] or str(case.get("case_id"))
        row = {
            "case_id": case.get("case_id"),
            "submitter_id": case.get("submitter_id"),
            **mapped,
            "analysis_person_id": person_id,
            "has_clinical": bool(
                case.get("vital_status") is not None
                or case.get("age_at_diagnosis_days") is not None
            ),
            "vital_status": case.get("vital_status"),
            "days_to_death": case.get("days_to_death"),
            "days_to_last_follow_up": case.get("days_to_last_follow_up"),
            "age_at_diagnosis_days": case.get("age_at_diagnosis_days"),
            "sex_at_birth": case.get("sex_at_birth"),
            "race": case.get("race"),
            "ethnicity": case.get("ethnicity"),
        }
        assigned.append(row)
        by_person[person_id].append(row)

    out: list[dict[str, Any]] = []
    for person_id, rows in by_person.items():
        comparison = compare_person_records(rows)
        if comparison["identity_conflict"]:
            for row in rows:
                if row["eligible_for_person_level_analysis"]:
                    row["eligible_for_person_level_analysis"] = False
                    row["exclusion_reason"] = "identity_record_conflict"
                    row["identity_confidence"] = "conflict"
        representative = min(rows, key=_representative_sort_key)
        for row in rows:
            out.append(
                {
                    "case_id": row["case_id"],
                    "submitter_id": row["submitter_id"],
                    "original_identifier": row["original_identifier"],
                    "normalized_identifier": row["normalized_identifier"],
                    "join_barcode": row["join_barcode"],
                    "analysis_person_id": person_id,
                    "identity_rule": row["identity_rule"],
                    "identity_confidence": row["identity_confidence"],
                    "eligible_for_person_level_analysis": row[
                        "eligible_for_person_level_analysis"
                    ],
                    "exclusion_reason": row["exclusion_reason"],
                    "n_gdc_cases_for_person": comparison["n_gdc_cases"],
                    "is_representative_case": row["case_id"]
                    == representative["case_id"],
                    "records_compatible": comparison["records_compatible"],
                    "identity_conflict": comparison["identity_conflict"],
                    "conflict_fields": comparison["conflict_fields"],
                }
            )
    return out


def summarize_identity(crosswalk: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    n_cases = len(crosswalk)
    persons = {row["analysis_person_id"] for row in crosswalk}
    eligible_rows = [
        row for row in crosswalk if row["eligible_for_person_level_analysis"]
    ]
    eligible_persons = {row["analysis_person_id"] for row in eligible_rows}
    ineligible = [
        row for row in crosswalk if not row["eligible_for_person_level_analysis"]
    ]
    reason_counts: dict[str, int] = defaultdict(int)
    for row in ineligible:
        reason_counts[str(row.get("exclusion_reason") or "unspecified")] += 1
    multi = [
        row
        for row in eligible_rows
        if (row.get("n_gdc_cases_for_person") or 1) > 1
        and row.get("is_representative_case")
    ]
    max_cases = max(
        (row.get("n_gdc_cases_for_person") or 1) for row in crosswalk
    )
    return {
        "n_gdc_cases": n_cases,
        "n_analysis_person_keys": len(persons),
        "n_gdc_cases_valid_identity": len(eligible_rows),
        "n_valid_analysis_persons": len(eligible_persons),
        "n_gdc_cases_ineligible_identity": len(ineligible),
        "n_excluded_ambiguous_experimental_d_token": reason_counts[
            "ambiguous_experimental_d_token"
        ],
        "n_excluded_ambiguous_experimental_construct": reason_counts[
            "ambiguous_experimental_construct"
        ],
        "n_excluded_not_patient_identifier": reason_counts[
            "not_patient_identifier"
        ],
        "n_excluded_identity_record_conflict": reason_counts[
            "identity_record_conflict"
        ],
        "n_multi_case_persons": len(multi),
        "max_gdc_cases_per_person": max_cases,
        "identity_exclusion_reasons": dict(reason_counts),
    }
