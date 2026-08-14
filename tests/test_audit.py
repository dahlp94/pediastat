"""Tests for TARGET-AML source-audit helpers.

These tests use in-memory fixtures and mock HTTP responses. They do not
call the live GDC API and do not assert a permanent case count.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import Mock

import pytest
import requests

from pediastat.audit.client import GDCAPIError, GDCClient
from pediastat.audit.constants import TARGET_AML_PROJECT_ID
from pediastat.audit.extract import get_values_at_path, is_gdc_missing_code, is_usable
from pediastat.audit.filters import (
    target_aml_cases_filter,
    target_aml_clinical_files_filter,
)
from pediastat.audit.summarize import entity_cardinality, summarize_field
from pediastat.audit.survival import audit_survival_fields, classify_vital_status


def test_target_aml_cases_filter_is_restricted() -> None:
    filt = target_aml_cases_filter()
    assert filt["op"] == "="
    assert filt["content"]["field"] == "project.project_id"
    assert filt["content"]["value"] == TARGET_AML_PROJECT_ID
    assert filt["content"]["value"] != "TCGA-LAML"


def test_clinical_files_filter_requires_target_aml_and_clinical() -> None:
    filt = target_aml_clinical_files_filter()
    assert filt["op"] == "and"
    encoded = str(filt)
    assert "TARGET-AML" in encoded
    assert "Clinical" in encoded
    assert "TCGA-LAML" not in encoded


def test_missing_value_helpers() -> None:
    assert is_gdc_missing_code("not reported")
    assert is_gdc_missing_code("Unknown")
    assert not is_gdc_missing_code("Alive")
    assert not is_usable(None)
    assert not is_usable("not reported")
    assert is_usable("white")
    assert is_usable(0)


def test_get_values_at_path_does_not_collapse_nested_records() -> None:
    case = {
        "diagnoses": [
            {"days_to_last_follow_up": 10},
            {"days_to_last_follow_up": 20},
            {"primary_diagnosis": "Acute myeloid leukemia, NOS"},
        ]
    }
    values = get_values_at_path(case, "diagnoses.days_to_last_follow_up")
    assert values == [10, 20]
    assert get_values_at_path(case, "diagnoses.missing_field") == []
    assert get_values_at_path({}, "diagnoses.days_to_last_follow_up") == []


def test_summarize_field_missingness_and_disagreement() -> None:
    cases: list[dict[str, Any]] = [
        {"diagnoses": [{"days_to_last_follow_up": 100.0}]},
        {
            "diagnoses": [
                {"days_to_last_follow_up": 5.0},
                {"days_to_last_follow_up": 9.0},
            ]
        },
        {"diagnoses": []},
        {},
    ]
    summary = summarize_field(
        cases,
        "diagnoses.days_to_last_follow_up",
        exists_in_mapping=True,
        gdc_type="double",
    )
    assert summary["n_cases"] == 4
    assert summary["n_available"] == 2
    assert summary["n_missing"] == 2
    assert summary["pct_missing"] == 50.0
    assert summary["n_cases_with_multiple_nonnull"] == 1
    assert summary["n_cases_with_disagreeing_values"] == 1
    assert summary["numeric_min"] == 5.0
    assert summary["numeric_max"] == 100.0
    assert summary["source_entity"] == "diagnosis"


def test_entity_cardinality_empty_and_multiple_nested_records() -> None:
    cases = [
        {},
        {"diagnoses": [], "follow_ups": []},
        {
            "diagnoses": [
                {
                    "diagnosis_id": "d1",
                    "treatments": [{"treatment_id": "t1"}, {"treatment_id": "t2"}],
                }
            ],
            "follow_ups": [
                {"follow_up_id": "f1", "days_to_follow_up": 10},
                {"follow_up_id": "f2"},
            ],
        },
        {
            "diagnoses": [{"diagnosis_id": "d2"}, {"diagnosis_id": "d3"}],
            "follow_ups": [{"follow_up_id": "f3", "days_to_follow_up": 1}],
        },
    ]
    card = entity_cardinality(cases)
    assert card["diagnoses"]["n_cases_with_0"] == 2
    assert card["diagnoses"]["n_cases_with_1"] == 1
    assert card["diagnoses"]["n_cases_with_gt1"] == 1
    assert card["follow_ups"]["n_cases_with_0"] == 2
    assert card["follow_ups"]["n_cases_with_gt1"] == 1
    assert card["follow_ups_with_days_to_follow_up"]["n_cases_with_1"] == 2
    assert card["treatments"]["n_cases_with_gt1"] == 1
    assert card["n_cases_with_follow_ups_nested_under_diagnosis"] == 0


def test_survival_audit_does_not_treat_unknown_as_censored() -> None:
    cases = [
        {
            "demographic": {"vital_status": "Dead", "days_to_death": 100},
            "diagnoses": [{"days_to_last_follow_up": 100.0}],
            "follow_ups": [{"days_to_follow_up": 100}],
        },
        {
            "demographic": {"vital_status": "Alive"},
            "diagnoses": [{"days_to_last_follow_up": 200.0}],
            "follow_ups": [
                {"days_to_follow_up": 150},
                {"days_to_follow_up": 200},
            ],
        },
        {
            "demographic": {"vital_status": "Unknown"},
            "diagnoses": [{"days_to_last_follow_up": 30.0}],
        },
        {
            "demographic": {"vital_status": "Alive"},
            "diagnoses": [],
            "follow_ups": [],
        },
        {
            "demographic": {"vital_status": "Dead"},
            "diagnoses": [{"days_to_last_follow_up": -1}],
        },
        {
            "diagnoses": [{"days_to_last_follow_up": 10}],
        },
    ]
    audit = audit_survival_fields(cases)
    assert classify_vital_status("Unknown") == "other"
    assert audit["vital_status_class_counts"]["dead"] == 2
    assert audit["vital_status_class_counts"]["alive"] == 2
    assert audit["vital_status_class_counts"]["other"] == 1
    assert audit["vital_status_class_counts"]["missing"] == 1
    assert audit["n_dead_with_days_to_death"] == 1
    assert audit["n_dead_missing_days_to_death"] == 1
    assert audit["n_alive_with_diagnoses_days_to_last_follow_up"] == 1
    assert audit["n_alive_with_follow_ups_days_to_follow_up"] == 1
    assert audit["n_alive_missing_all_follow_up_times"] == 1
    assert audit["n_cases_with_multiple_follow_up_times"] == 1
    # Unknown and missing vital status must not be counted as usable OS times.
    assert audit["n_cases_with_possible_gdc_style_survival_time"] == 2


def test_http_error_handling() -> None:
    response = Mock()
    response.status_code = 500
    response.text = "internal error"
    session = Mock()
    session.headers = {}
    session.get.return_value = response
    client = GDCClient(session=session, timeout_seconds=1)
    with pytest.raises(GDCAPIError) as exc_info:
        client.get_json("projects/TARGET-AML")
    assert exc_info.value.status_code == 500
    assert "500" in str(exc_info.value)


def test_http_timeout_is_wrapped() -> None:
    session = Mock()
    session.headers = {}
    session.post.side_effect = requests.Timeout("timed out")
    client = GDCClient(session=session, timeout_seconds=0.1)
    with pytest.raises(GDCAPIError, match="failed"):
        client.post_json("cases", {"filters": target_aml_cases_filter()})


def test_controlled_download_is_refused(tmp_path) -> None:
    response = Mock()
    response.status_code = 403
    response.text = "forbidden"
    session = Mock()
    session.headers = {}
    session.get.return_value = response
    client = GDCClient(session=session)
    with pytest.raises(GDCAPIError, match="controlled or unauthorized"):
        client.download_open_file("file-id", tmp_path / "secret.bin")
