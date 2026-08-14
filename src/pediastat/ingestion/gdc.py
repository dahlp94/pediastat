"""Parse GDC case payloads into source-faithful entity rows.

Nested follow-ups and treatments are not collapsed.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.audit.extract import as_records
from pediastat.ingestion.identifiers import join_barcode, normalize_identifier


def _copy_payload(record: Mapping[str, Any]) -> dict[str, Any]:
    return dict(record)


def _as_text(value: Any) -> str | None:
    """Preserve source text without sending Python bools into TEXT columns."""
    if value is None:
        return None
    if isinstance(value, bool):
        return str(value).lower()
    return str(value)


def parse_case_entities(case: Mapping[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Split one GDC case into entity rows, preserving one-to-many lists."""
    case_id = case.get("case_id") or case.get("id")
    submitter_id = case.get("submitter_id")
    project = case.get("project") if isinstance(case.get("project"), dict) else {}
    project_id = project.get("project_id") if isinstance(project, dict) else None

    case_row = {
        "case_id": case_id,
        "submitter_id": submitter_id,
        "submitter_id_normalized": normalize_identifier(submitter_id),
        "join_barcode": join_barcode(submitter_id),
        "project_id": project_id,
        "disease_type": case.get("disease_type"),
        "primary_site": case.get("primary_site"),
        "index_date": _as_text(case.get("index_date")),
        "lost_to_followup": _as_text(case.get("lost_to_followup")),
        "days_to_lost_to_followup": case.get("days_to_lost_to_followup"),
        "payload": {
            key: value
            for key, value in case.items()
            if key
            not in {
                "demographic",
                "diagnoses",
                "follow_ups",
                "samples",
                "aliquot_ids",
                "submitter_aliquot_ids",
                "sample_ids",
                "submitter_sample_ids",
                "diagnosis_ids",
                "submitter_diagnosis_ids",
            }
        },
    }

    demographics: list[dict[str, Any]] = []
    for item in as_records(case.get("demographic")):
        demographics.append(
            {
                "case_id": case_id,
                "submitter_id": submitter_id,
                "submitter_id_normalized": normalize_identifier(submitter_id),
                "join_barcode": join_barcode(submitter_id),
                "demographic_id": item.get("demographic_id"),
                "vital_status": item.get("vital_status"),
                "days_to_death": item.get("days_to_death"),
                "age_at_index": item.get("age_at_index"),
                "days_to_birth": item.get("days_to_birth"),
                "sex_at_birth": item.get("sex_at_birth"),
                "race": item.get("race"),
                "ethnicity": item.get("ethnicity"),
                "year_of_birth": item.get("year_of_birth"),
                "year_of_death": item.get("year_of_death"),
                "cause_of_death": item.get("cause_of_death"),
                "age_is_obfuscated": (
                    None
                    if item.get("age_is_obfuscated") is None
                    else str(item.get("age_is_obfuscated"))
                ),
                "payload": _copy_payload(item),
            }
        )

    diagnoses: list[dict[str, Any]] = []
    treatments: list[dict[str, Any]] = []
    for diagnosis in as_records(case.get("diagnoses")):
        diagnosis_id = diagnosis.get("diagnosis_id")
        diagnoses.append(
            {
                "case_id": case_id,
                "submitter_id": submitter_id,
                "submitter_id_normalized": normalize_identifier(submitter_id),
                "join_barcode": join_barcode(submitter_id),
                "diagnosis_id": diagnosis_id,
                "age_at_diagnosis": diagnosis.get("age_at_diagnosis"),
                "days_to_diagnosis": diagnosis.get("days_to_diagnosis"),
                "days_to_last_follow_up": diagnosis.get("days_to_last_follow_up"),
                "primary_diagnosis": diagnosis.get("primary_diagnosis"),
                "morphology": diagnosis.get("morphology"),
                "tissue_or_organ_of_origin": diagnosis.get("tissue_or_organ_of_origin"),
                "site_of_resection_or_biopsy": diagnosis.get(
                    "site_of_resection_or_biopsy"
                ),
                "year_of_diagnosis": (
                    None
                    if diagnosis.get("year_of_diagnosis") is None
                    else str(diagnosis.get("year_of_diagnosis"))
                ),
                "icd_10_code": diagnosis.get("icd_10_code"),
                "classification_of_tumor": _as_text(
                    diagnosis.get("classification_of_tumor")
                ),
                "diagnosis_is_primary_disease": _as_text(
                    diagnosis.get("diagnosis_is_primary_disease")
                ),
                "payload": {
                    key: value
                    for key, value in diagnosis.items()
                    if key != "treatments"
                },
            }
        )
        for treatment in as_records(diagnosis.get("treatments")):
            treatments.append(
                {
                    "case_id": case_id,
                    "submitter_id": submitter_id,
                    "submitter_id_normalized": normalize_identifier(submitter_id),
                    "join_barcode": join_barcode(submitter_id),
                    "diagnosis_id": diagnosis_id,
                    "treatment_id": treatment.get("treatment_id"),
                    "treatment_type": treatment.get("treatment_type"),
                    "treatment_or_therapy": treatment.get("treatment_or_therapy"),
                    "therapeutic_agents": treatment.get("therapeutic_agents"),
                    "protocol_identifier": treatment.get("protocol_identifier"),
                    "days_to_treatment_start": treatment.get("days_to_treatment_start"),
                    "days_to_treatment_end": treatment.get("days_to_treatment_end"),
                    "timepoint_category": treatment.get("timepoint_category"),
                    "treatment_outcome": treatment.get("treatment_outcome"),
                    "course_number": treatment.get("course_number"),
                    "payload": _copy_payload(treatment),
                }
            )

    follow_ups: list[dict[str, Any]] = []
    for follow_up in as_records(case.get("follow_ups")):
        follow_ups.append(
            {
                "case_id": case_id,
                "submitter_id": submitter_id,
                "submitter_id_normalized": normalize_identifier(submitter_id),
                "join_barcode": join_barcode(submitter_id),
                "follow_up_id": follow_up.get("follow_up_id"),
                "days_to_follow_up": follow_up.get("days_to_follow_up"),
                "timepoint_category": follow_up.get("timepoint_category"),
                "first_event": follow_up.get("first_event"),
                "days_to_first_event": follow_up.get("days_to_first_event"),
                "year_of_follow_up": follow_up.get("year_of_follow_up"),
                "payload": _copy_payload(follow_up),
            }
        )

    return {
        "cases": [case_row],
        "demographics": demographics,
        "diagnoses": diagnoses,
        "follow_ups": follow_ups,
        "treatments": treatments,
    }


def parse_cases(cases: Sequence[Mapping[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Parse many GDC cases without flattening nested entities."""
    buckets: dict[str, list[dict[str, Any]]] = {
        "cases": [],
        "demographics": [],
        "diagnoses": [],
        "follow_ups": [],
        "treatments": [],
    }
    for case in cases:
        parsed = parse_case_entities(case)
        for key, rows in parsed.items():
            buckets[key].extend(rows)
    return buckets
