"""Tests for the study-focused TARGET-AML source validation."""

from __future__ import annotations

from unittest.mock import Mock

import pytest
import requests

from pediastat.audit import (
    audit_survival_fields,
    get_values_at_path,
    summarize_field,
)
from pediastat.gdc_api import (
    TARGET_AML_CASES_FILTER,
    TARGET_AML_CLINICAL_FILES_FILTER,
    GDCAPIError,
    classify_vital_status,
    download_open_file,
    get_json,
    post_json,
)


def test_target_aml_filters_are_restricted() -> None:
    assert TARGET_AML_CASES_FILTER["content"]["value"] == "TARGET-AML"
    encoded = str(TARGET_AML_CLINICAL_FILES_FILTER)
    assert "TARGET-AML" in encoded
    assert "Clinical" in encoded
    assert "TCGA-LAML" not in encoded


def test_nested_values_are_not_collapsed() -> None:
    case = {
        "diagnoses": [
            {"days_to_last_follow_up": 10},
            {"days_to_last_follow_up": 20},
        ]
    }
    assert get_values_at_path(
        case, "diagnoses.days_to_last_follow_up"
    ) == [10, 20]


def test_study_field_summary_tracks_missingness_and_disagreement() -> None:
    cases = [
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
    summary = summarize_field(cases, "diagnoses.days_to_last_follow_up")
    assert summary["n_cases"] == 4
    assert summary["n_available"] == 2
    assert summary["pct_missing"] == 50.0
    assert summary["n_cases_with_multiple_values"] == 1
    assert summary["n_cases_with_disagreeing_values"] == 1
    assert summary["numeric_min"] == 5.0
    assert summary["numeric_max"] == 100.0


def test_unknown_vital_status_is_not_censored() -> None:
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
        {"demographic": {"vital_status": "Alive"}},
        {"demographic": {"vital_status": "Dead"}},
        {"diagnoses": [{"days_to_last_follow_up": 10}]},
    ]

    audit = audit_survival_fields(cases)
    assert classify_vital_status("Unknown") == "other"
    assert audit["vital_status_class_counts"] == {
        "dead": 2,
        "alive": 2,
        "other": 1,
        "missing": 1,
    }
    assert audit["n_dead_missing_days_to_death"] == 1
    assert audit["n_alive_missing_all_follow_up_times"] == 1
    assert audit["n_cases_with_multiple_follow_up_times"] == 1
    assert audit["n_cases_with_possible_gdc_style_survival_time"] == 2


def test_http_error_is_wrapped() -> None:
    response = Mock()
    response.status_code = 500
    response.text = "internal error"
    session = Mock()
    session.get.return_value = response

    with pytest.raises(GDCAPIError) as exc_info:
        get_json("projects/TARGET-AML", session=session, timeout=1)

    assert exc_info.value.status_code == 500
    assert session.get.call_args.kwargs["timeout"] == 1


def test_http_timeout_is_wrapped() -> None:
    session = Mock()
    session.post.side_effect = requests.Timeout("timed out")

    with pytest.raises(GDCAPIError, match="failed"):
        post_json(
            "cases",
            {"filters": TARGET_AML_CASES_FILTER},
            session=session,
            timeout=0.1,
        )


def test_controlled_download_is_refused(tmp_path) -> None:
    response = Mock()
    response.status_code = 403
    response.text = "forbidden"
    session = Mock()
    session.get.return_value = response
    destination = tmp_path / "secret.bin"

    with pytest.raises(GDCAPIError, match="controlled or unauthorized"):
        download_open_file("file-id", destination, session=session)

    assert not destination.exists()
