"""Parse and normalize public TARGET-AML clinical source data.

This module handles source-faithful ingestion only:
- TARGET identifier normalization
- missing-value classification
- GDC case/entity parsing
- TARGET clinical supplement workbook parsing and profiling

Database persistence belongs in ``pediastat.database``.
"""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from pathlib import Path
from typing import Any

from openpyxl import load_workbook

from pediastat.gdc import as_records

CANONICAL_BARCODE = re.compile(r"^TARGET-\d{2}-[A-Z0-9]+$")
EXTENDED_BARCODE = re.compile(r"^TARGET-\d{2}-[A-Z0-9]+(?:-[A-Z0-9]+)+$")
JOIN_BARCODE = re.compile(r"^(TARGET-\d{2}-[A-Z0-9]+)")


def original_identifier(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str) and value.strip() == "":
        return None
    return str(value)


def normalize_identifier(value: Any) -> str | None:
    original = original_identifier(value)
    return None if original is None else original.strip().upper()


def join_barcode(value: Any) -> str | None:
    normalized = normalize_identifier(value)
    if normalized is None:
        return None
    match = JOIN_BARCODE.match(normalized)
    return match.group(1) if match else normalized


def identifier_shape(value: Any) -> str:
    original = original_identifier(value)
    if original is None:
        return "missing"
    stripped = original.strip()
    if original != stripped:
        return "whitespace"
    normalized = stripped.upper()
    if CANONICAL_BARCODE.match(normalized):
        return "canonical"
    if EXTENDED_BARCODE.match(normalized):
        return "extended"
    return "malformed"


def summarize_identifiers(values: list[Any]) -> dict[str, Any]:
    originals = [original_identifier(value) for value in values]
    present = [value for value in originals if value is not None]
    shapes: Counter[str] = Counter()
    normalized_counts: Counter[str] = Counter()
    whitespace = 0
    case_differences = 0
    for original in present:
        shapes[identifier_shape(original)] += 1
        if original != original.strip():
            whitespace += 1
        stripped = original.strip()
        if stripped != stripped.upper():
            case_differences += 1
        normalized = normalize_identifier(original)
        if normalized is not None:
            normalized_counts[normalized] += 1
    duplicate_counts = [count for count in normalized_counts.values() if count > 1]
    return {
        "n_records": len(values),
        "n_non_null": len(present),
        "n_null": len(values) - len(present),
        "n_unique_normalized": len(normalized_counts),
        "n_duplicated_normalized_ids": len(duplicate_counts),
        "n_duplicate_records": sum(count - 1 for count in duplicate_counts),
        "n_whitespace": whitespace,
        "n_case_differences": case_differences,
        "n_canonical": shapes["canonical"],
        "n_extended": shapes["extended"],
        "n_malformed": shapes["malformed"],
        "shapes": dict(shapes),
    }


NOT_REPORTED = frozenset({"not reported", "notreported"})
UNKNOWN = frozenset(
    {
        "unknown",
        "unspecified",
        "na",
        "n/a",
        "n.a.",
        "n.a",
        "--",
        ".",
        "missing",
        "not available",
        "null",
    }
)
NOT_APPLICABLE = frozenset({"not applicable", "notapplicable"})
SENTINEL_NUMBERS = frozenset({-99, -999, -9999})


def classify_missing(value: Any) -> str:
    if value is None:
        return "structurally_missing"
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return "structurally_missing"
        token = " ".join(stripped.lower().split())
        compact = token.replace(" ", "")
        if token in NOT_REPORTED or compact in NOT_REPORTED:
            return "not_reported"
        if token in NOT_APPLICABLE or compact in NOT_APPLICABLE:
            return "not_applicable"
        if token in UNKNOWN or compact in UNKNOWN:
            return "unknown"
        return "observed"
    if isinstance(value, bool):
        return "observed"
    if isinstance(value, int | float) and value in SENTINEL_NUMBERS:
        return "sentinel"
    return "observed"


def is_observed(value: Any) -> bool:
    return classify_missing(value) == "observed"


CASE_NESTED_FIELDS = {
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


def _case_keys(case_id: Any, submitter_id: Any) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "submitter_id": submitter_id,
        "submitter_id_normalized": normalize_identifier(submitter_id),
        "join_barcode": join_barcode(submitter_id),
    }


def _as_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return str(value).lower()
    return str(value)


def parse_case_entities(case: Mapping[str, Any]) -> dict[str, list[dict[str, Any]]]:
    case_id = case.get("case_id") or case.get("id")
    submitter_id = case.get("submitter_id")
    keys = _case_keys(case_id, submitter_id)

    project = case.get("project")
    project_id = project.get("project_id") if isinstance(project, dict) else None

    case_row = {
        **keys,
        "project_id": project_id,
        "disease_type": case.get("disease_type"),
        "primary_site": case.get("primary_site"),
        "index_date": _as_text(case.get("index_date")),
        "lost_to_followup": _as_text(case.get("lost_to_followup")),
        "days_to_lost_to_followup": case.get("days_to_lost_to_followup"),
        "payload": {
            key: value for key, value in case.items() if key not in CASE_NESTED_FIELDS
        },
    }

    demographics = [
        {
            **keys,
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
            "age_is_obfuscated": _as_text(item.get("age_is_obfuscated")),
            "payload": dict(item),
        }
        for item in as_records(case.get("demographic"))
    ]

    diagnoses: list[dict[str, Any]] = []
    treatments: list[dict[str, Any]] = []
    for diagnosis in as_records(case.get("diagnoses")):
        diagnosis_id = diagnosis.get("diagnosis_id")
        diagnoses.append(
            {
                **keys,
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
                "year_of_diagnosis": _as_text(diagnosis.get("year_of_diagnosis")),
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
                    **keys,
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
                    "payload": dict(treatment),
                }
            )

    follow_ups = [
        {
            **keys,
            "follow_up_id": follow_up.get("follow_up_id"),
            "days_to_follow_up": follow_up.get("days_to_follow_up"),
            "timepoint_category": follow_up.get("timepoint_category"),
            "first_event": follow_up.get("first_event"),
            "days_to_first_event": follow_up.get("days_to_first_event"),
            "year_of_follow_up": follow_up.get("year_of_follow_up"),
            "payload": dict(follow_up),
        }
        for follow_up in as_records(case.get("follow_ups"))
    ]

    return {
        "cases": [case_row],
        "demographics": demographics,
        "diagnoses": diagnoses,
        "follow_ups": follow_ups,
        "treatments": treatments,
    }


def parse_cases(cases: Sequence[Mapping[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    buckets: dict[str, list[dict[str, Any]]] = {
        "cases": [],
        "demographics": [],
        "diagnoses": [],
        "follow_ups": [],
        "treatments": [],
    }
    for case in cases:
        parsed = parse_case_entities(case)
        for name, rows in parsed.items():
            buckets[name].extend(rows)
    return buckets


IDENTIFIER_HEADERS = frozenset({"target usi", "target barcode", "submitter_id"})


def cell_to_jsonable(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, str | bool | int | float):
        return value
    return str(value)


def _header_names(row: tuple[Any, ...] | None) -> list[str]:
    if row is None:
        return []
    return [
        f"unnamed_{index + 1}"
        if value is None or str(value).strip() == ""
        else str(value).strip()
        for index, value in enumerate(row)
    ]


def identifier_header(columns: list[str]) -> str | None:
    for name in columns:
        if name.strip().lower() in IDENTIFIER_HEADERS:
            return name
    return None


def _infer_type(values: list[Any]) -> str:
    observed = [value for value in values if is_observed(value)]
    if not observed:
        return "empty"
    kinds: set[str] = set()
    for value in observed:
        if isinstance(value, bool):
            kinds.add("bool")
        elif isinstance(value, int):
            kinds.add("int")
        elif isinstance(value, float):
            kinds.add("float")
        else:
            kinds.add("str")
    if len(kinds) == 1:
        return next(iter(kinds))
    if kinds <= {"int", "float"}:
        return "float"
    return "mixed"


def read_workbook_sheets(path: Path) -> list[dict[str, Any]]:
    workbook = load_workbook(path, read_only=True, data_only=True)
    sheets: list[dict[str, Any]] = []
    try:
        for sheet_name in workbook.sheetnames:
            worksheet = workbook[sheet_name]
            rows = worksheet.iter_rows(values_only=True)
            columns = _header_names(next(rows, None))
            id_column = identifier_header(columns)
            records: list[dict[str, Any]] = []
            identifiers: list[Any] = []
            for row_number, row in enumerate(rows, start=2):
                cells = {
                    column: cell_to_jsonable(row[index] if index < len(row) else None)
                    for index, column in enumerate(columns)
                }
                identifier = cells.get(id_column) if id_column else None
                identifiers.append(identifier)
                records.append(
                    {
                        "row_number": row_number,
                        "original_identifier": original_identifier(identifier),
                        "normalized_identifier": normalize_identifier(identifier),
                        "join_barcode": join_barcode(identifier),
                        "identifier_shape": identifier_shape(identifier),
                        "cells": cells,
                    }
                )
            sheets.append(
                {
                    "workbook": path.name,
                    "path": str(path),
                    "sheet": sheet_name,
                    "columns": columns,
                    "identifier_field": id_column,
                    "n_rows": len(records),
                    "n_columns": len(columns),
                    "is_patient_level": id_column is not None,
                    "records": records,
                    "identifier_summary": summarize_identifiers(identifiers),
                }
            )
    finally:
        workbook.close()
    return sheets


def profile_sheet(
    sheet: dict[str, Any], *, include_samples: bool = False
) -> list[dict[str, Any]]:
    columns: list[str] = sheet["columns"]
    records: list[dict[str, Any]] = sheet["records"]
    n_rows = len(records)
    id_field = sheet.get("identifier_field")
    profiles: list[dict[str, Any]] = []
    for column in columns:
        values = [record["cells"].get(column) for record in records]
        observed = [value for value in values if is_observed(value)]
        missing = n_rows - len(observed)
        numeric = [
            float(value)
            for value in observed
            if isinstance(value, int | float) and not isinstance(value, bool)
        ]
        profiles.append(
            {
                "workbook": sheet["workbook"],
                "sheet": sheet["sheet"],
                "column": column,
                "is_identifier": column == id_field,
                "n_rows": n_rows,
                "n_missing": missing,
                "pct_missing": round(missing / n_rows * 100.0, 2) if n_rows else 0.0,
                "n_unique_observed": len({repr(value) for value in observed}),
                "inferred_type": _infer_type(values),
                "numeric_min": min(numeric) if numeric else None,
                "numeric_max": max(numeric) if numeric else None,
                "sample_values": (
                    [str(value) for value in observed[:5]]
                    if include_samples and column != id_field
                    else None
                ),
            }
        )
    return profiles


def column_value_counts(sheet: dict[str, Any], column: str) -> Counter[str]:
    counts: Counter[str] = Counter()
    for record in sheet["records"]:
        value = record["cells"].get(column)
        if is_observed(value):
            counts[str(value)] += 1
    return counts
