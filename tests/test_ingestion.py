"""Tests for ingestion helpers. These do not call GDC or PostgreSQL."""

from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest
from openpyxl import Workbook

from pediastat.ingestion.gdc import parse_case_entities, parse_cases
from pediastat.ingestion.identifiers import (
    identifier_shape,
    join_barcode,
    normalize_identifier,
    original_identifier,
    summarize_identifiers,
)
from pediastat.ingestion.loaders import replace_gdc_entities
from pediastat.ingestion.missingness import classify_missing, is_observed
from pediastat.ingestion.supplements import identifier_header, read_workbook_sheets


def test_identifier_normalization_preserves_original() -> None:
    raw = " target-20-pasfyf "
    assert original_identifier(raw) == " target-20-pasfyf "
    assert normalize_identifier(raw) == "TARGET-20-PASFYF"
    assert join_barcode(raw) == "TARGET-20-PASFYF"


def test_extended_barcode_suffix_is_not_stripped() -> None:
    raw = "TARGET-20-PAYGWX-Unsorted"
    assert normalize_identifier(raw) == "TARGET-20-PAYGWX-UNSORTED"
    assert join_barcode(raw) == "TARGET-20-PAYGWX"
    assert identifier_shape(raw) == "extended"


def test_malformed_identifier_is_flagged() -> None:
    assert identifier_shape("not-a-barcode") == "malformed"
    assert identifier_shape(None) == "missing"
    assert identifier_shape(" TARGET-20-PASFYF") == "whitespace"


def test_duplicate_identifier_summary() -> None:
    summary = summarize_identifiers(
        ["TARGET-20-AAA", "TARGET-20-AAA", None, "TARGET-20-BBB"]
    )
    assert summary["n_records"] == 4
    assert summary["n_non_null"] == 3
    assert summary["n_unique_normalized"] == 2
    assert summary["n_duplicated_normalized_ids"] == 1
    assert summary["n_duplicate_records"] == 1


def test_missing_value_classes_are_distinct() -> None:
    assert classify_missing(None) == "structurally_missing"
    assert classify_missing("  ") == "structurally_missing"
    assert classify_missing("Not Reported") == "not_reported"
    assert classify_missing("Unknown") == "unknown"
    assert classify_missing("N/A") == "unknown"
    assert classify_missing("Not Applicable") == "not_applicable"
    assert classify_missing(-99) == "sentinel"
    assert classify_missing(0) == "observed"
    assert classify_missing("Alive") == "observed"
    assert is_observed("Dead")
    assert not is_observed("Unknown")


def test_gdc_parser_preserves_one_to_many_follow_ups() -> None:
    case = {
        "case_id": "abc",
        "submitter_id": "TARGET-20-PASFYF",
        "project": {"project_id": "TARGET-AML"},
        "diagnoses": [
            {
                "diagnosis_id": "d1",
                "age_at_diagnosis": 1000,
                "treatments": [
                    {"treatment_id": "t1", "protocol_identifier": "AAML1031"},
                    {
                        "treatment_id": "t2",
                        "treatment_type": "Stem Cell Transplantation, NOS",
                    },
                ],
            }
        ],
        "follow_ups": [
            {
                "follow_up_id": "f1",
                "days_to_follow_up": 10,
                "timepoint_category": "Last Contact",
            },
            {"follow_up_id": "f2"},
            {"follow_up_id": "f3", "days_to_follow_up": 5, "first_event": "Relapse"},
        ],
        "demographic": {"demographic_id": "demo", "vital_status": "Alive"},
    }
    parsed = parse_case_entities(case)
    assert len(parsed["cases"]) == 1
    assert parsed["cases"][0]["join_barcode"] == "TARGET-20-PASFYF"
    assert len(parsed["follow_ups"]) == 3
    assert len(parsed["treatments"]) == 2
    assert parsed["treatments"][0]["diagnosis_id"] == "d1"
    assert "diagnoses" not in parsed["cases"][0]["payload"]
    assert "treatments" not in parsed["diagnoses"][0]["payload"]


def test_parse_cases_empty_nested_entities() -> None:
    parsed = parse_cases([{"case_id": "z", "submitter_id": "TARGET-20-XXXXXX"}])
    assert len(parsed["cases"]) == 1
    assert parsed["demographics"] == []
    assert parsed["diagnoses"] == []
    assert parsed["follow_ups"] == []
    assert parsed["treatments"] == []


def test_workbook_sheet_provenance_fields(tmp_path: Path) -> None:
    assert identifier_header(["TARGET USI", "Vital Status"]) == "TARGET USI"
    assert identifier_header(["Column Header"]) is None
    path = tmp_path / "TARGET_AML_ClinicalData_fixture.xlsx"
    workbook = Workbook()
    sheet = workbook.active
    assert sheet is not None
    sheet.title = "Clinical Data"
    sheet.append(["TARGET USI", "Vital Status", "WBC at Diagnosis"])
    sheet.append([" TARGET-20-PASFYF ", "Alive", 12.5])
    sheet.append(["TARGET-20-PAYGWX-Unsorted", "Dead", None])
    extra = workbook.create_sheet("Notes")
    extra.append(["not", "patient", "data"])
    extra.append(["a", "b", "c"])
    workbook.save(path)
    sheets = read_workbook_sheets(path)
    by_name = {item["sheet"]: item for item in sheets}
    clinical = by_name["Clinical Data"]
    notes = by_name["Notes"]
    assert clinical["workbook"] == path.name
    assert clinical["is_patient_level"] is True
    assert notes["is_patient_level"] is False
    first = clinical["records"][0]
    assert first["original_identifier"] == " TARGET-20-PASFYF "
    assert first["normalized_identifier"] == "TARGET-20-PASFYF"
    assert first["join_barcode"] == "TARGET-20-PASFYF"
    assert first["cells"]["Vital Status"] == "Alive"
    second = clinical["records"][1]
    assert second["normalized_identifier"] == "TARGET-20-PAYGWX-UNSORTED"
    assert second["join_barcode"] == "TARGET-20-PAYGWX"


class _FakeResult:
    def scalar_one(self) -> object:
        return uuid4()


class _FakeConnection:
    def __init__(self, fail_on: str | None = None) -> None:
        self.statements: list[str] = []
        self.fail_on = fail_on
        self.exited_with: type[BaseException] | None = None

    def execute(self, statement: object, params: object = None) -> _FakeResult:
        sql = str(statement)
        self.statements.append(sql)
        if self.fail_on and self.fail_on in sql:
            raise RuntimeError("forced failure")
        return _FakeResult()


class _FakeTransaction:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection

    def __enter__(self) -> _FakeConnection:
        return self.connection

    def __exit__(
        self, exc_type: type[BaseException] | None, exc: object, tb: object
    ) -> bool:
        self.connection.exited_with = exc_type
        return False


class _FakeEngine:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection

    def begin(self) -> _FakeTransaction:
        return _FakeTransaction(self.connection)


def test_replace_gdc_entities_deletes_before_insert_and_rolls_back() -> None:
    parsed = parse_cases(
        [
            {
                "case_id": "abc",
                "submitter_id": "TARGET-20-PASFYF",
                "follow_ups": [
                    {"follow_up_id": "f1", "days_to_follow_up": 1},
                    {"follow_up_id": "f2", "days_to_follow_up": 2},
                ],
            }
        ]
    )
    connection = _FakeConnection()
    counts = replace_gdc_entities(
        _FakeEngine(connection),  # type: ignore[arg-type]
        source_id=uuid4(),
        run_id=uuid4(),
        entities=parsed,
    )
    assert counts["follow_ups"] == 2
    deletes = [sql for sql in connection.statements if sql.upper().startswith("DELETE")]
    inserts = [sql for sql in connection.statements if "INSERT INTO raw.gdc_" in sql]
    assert deletes
    assert any("raw.gdc_follow_ups" in sql for sql in inserts)

    failing = _FakeConnection(fail_on="INSERT INTO raw.gdc_follow_ups")
    with pytest.raises(RuntimeError, match="forced failure"):
        replace_gdc_entities(
            _FakeEngine(failing),  # type: ignore[arg-type]
            source_id=uuid4(),
            run_id=uuid4(),
            entities=parsed,
        )
    assert failing.exited_with is RuntimeError
    assert not any(
        "INSERT INTO staging.gdc_follow_ups" in sql for sql in failing.statements
    )
