"""Stage 3 cohort, identity, and OS endpoint tests. No live database."""

from __future__ import annotations

from pediastat.cohort.baseline import reconcile_supplement_concept, workbook_family
from pediastat.cohort.eligibility import evaluate_person
from pediastat.cohort.endpoint import derive_os_endpoint
from pediastat.cohort.gdc_definitions import verify_time_origin
from pediastat.cohort.identity import (
    build_identity_crosswalk,
    classify_identifier,
    compare_person_records,
)


def test_dead_is_event_one() -> None:
    derived = derive_os_endpoint(
        {"vital_status": "Dead", "days_to_death": 100, "index_date": "Diagnosis"}
    )
    assert derived["os_event"] == 1
    assert derived["os_days"] == 100
    assert derived["os_time_source"] == "gdc.demographic.days_to_death"
    assert derived["has_valid_os_time"]


def test_alive_is_event_zero() -> None:
    derived = derive_os_endpoint(
        {
            "vital_status": "Alive",
            "days_to_last_follow_up": 200,
            "index_date": "Diagnosis",
        }
    )
    assert derived["os_event"] == 0
    assert derived["os_days"] == 200
    assert derived["os_time_source"] == "gdc.diagnoses.days_to_last_follow_up"


def test_unknown_vital_status_is_not_primary_eligible() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Unknown",
            "age_at_diagnosis_days": 1000,
            "days_to_last_follow_up": 10,
            "index_date": "Diagnosis",
        },
        has_diagnosis=True,
    )
    assert not evaluated["primary_cohort_eligible"]
    assert evaluated["primary_exclusion_reason"] == "vital_status_not_alive_or_dead"
    assert not evaluated["has_known_vital_status"]


def test_not_reported_vital_status_is_not_primary_eligible() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Not Reported",
            "age_at_diagnosis_days": 1000,
            "days_to_last_follow_up": 10,
            "index_date": "Diagnosis",
        },
        has_diagnosis=True,
    )
    assert not evaluated["primary_cohort_eligible"]
    assert "vital_status_not_alive_or_dead" in evaluated["all_exclusion_flags"]


def test_dead_requires_days_to_death() -> None:
    derived = derive_os_endpoint({"vital_status": "Dead", "index_date": "Diagnosis"})
    assert derived["os_event"] == 1
    assert not derived["has_valid_os_time"]
    assert derived["os_time_invalid_reason"] == "dead_missing_days_to_death"


def test_alive_requires_days_to_last_follow_up() -> None:
    derived = derive_os_endpoint({"vital_status": "Alive", "index_date": "Diagnosis"})
    assert derived["os_event"] == 0
    assert not derived["has_valid_os_time"]
    assert derived["os_time_invalid_reason"] == "alive_missing_days_to_last_follow_up"


def test_age_lt_18_is_eligible() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Alive",
            "days_to_last_follow_up": 30,
            "age_at_diagnosis_days": 17.9 * 365.25,
            "index_date": "Diagnosis",
        },
        has_diagnosis=True,
    )
    assert evaluated["age_eligible_lt18"]
    assert evaluated["primary_cohort_eligible"]


def test_age_ge_18_is_primary_ineligible() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Alive",
            "days_to_last_follow_up": 30,
            "age_at_diagnosis_days": 18 * 365.25,
            "index_date": "Diagnosis",
        },
        has_diagnosis=True,
    )
    assert not evaluated["age_eligible_lt18"]
    assert evaluated["age_eligible_le21"]
    assert not evaluated["primary_cohort_eligible"]
    assert evaluated["primary_exclusion_reason"] == "age_not_lt_18"
    assert evaluated["sensitivity_le21_eligible"]


def test_missing_age_is_excluded() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Dead",
            "days_to_death": 40,
            "index_date": "Diagnosis",
        },
        has_diagnosis=True,
    )
    assert not evaluated["has_age"]
    assert evaluated["primary_exclusion_reason"] == "age_unavailable"


def test_negative_os_time_is_invalid() -> None:
    derived = derive_os_endpoint(
        {"vital_status": "Dead", "days_to_death": -1, "index_date": "Diagnosis"}
    )
    assert not derived["has_valid_os_time"]
    assert derived["os_time_invalid_reason"] == "negative_os_time"


def test_zero_os_time_is_valid_with_qa_flag() -> None:
    derived = derive_os_endpoint(
        {
            "vital_status": "Alive",
            "days_to_last_follow_up": 0,
            "index_date": "Diagnosis",
        }
    )
    assert derived["has_valid_os_time"]
    assert derived["os_days"] == 0
    assert "zero_os_time" in derived["qa_flags"]


def test_ambiguous_experimental_identity_is_excluded() -> None:
    mapped = classify_identifier("TARGET-20-D7-EC-GFP1")
    assert not mapped["eligible_for_person_level_analysis"]
    assert mapped["exclusion_reason"] == "ambiguous_experimental_d_token"
    assert mapped["analysis_person_id"] != "TARGET-20-D7"


def test_extended_id_maps_only_under_explicit_rule() -> None:
    mapped = classify_identifier("TARGET-20-PAYGWX-Unsorted")
    assert mapped["eligible_for_person_level_analysis"]
    assert mapped["analysis_person_id"] == "TARGET-20-PAYGWX"
    assert mapped["identity_rule"] == "extended_usi_collapsed_to_canonical"
    refused = classify_identifier("TARGET-20-PAYGWX-ExperimentBatch")
    assert not refused["eligible_for_person_level_analysis"]


def test_canonical_usi_is_the_analysis_person() -> None:
    mapped = classify_identifier("TARGET-20-PASFYF")
    assert mapped["analysis_person_id"] == "TARGET-20-PASFYF"
    assert mapped["eligible_for_person_level_analysis"]


def test_identity_collision_conflict_excludes_person() -> None:
    comparison = compare_person_records(
        [
            {"vital_status": "Alive", "age_at_diagnosis_days": 100},
            {"vital_status": "Dead", "age_at_diagnosis_days": 100},
        ]
    )
    assert comparison["identity_conflict"]
    assert "vital_status" in comparison["conflict_fields"]
    crosswalk = build_identity_crosswalk(
        [
            {
                "case_id": "c1",
                "submitter_id": "TARGET-20-PAYGWX-Unsorted",
                "vital_status": "Alive",
                "age_at_diagnosis_days": 100,
                "days_to_last_follow_up": 9,
                "sex_at_birth": "female",
            },
            {
                "case_id": "c2",
                "submitter_id": "TARGET-20-PAYGWX-Sorted-leukemic",
                "vital_status": "Dead",
                "age_at_diagnosis_days": 100,
                "days_to_death": 9,
                "sex_at_birth": "female",
            },
        ]
    )
    assert all(not row["eligible_for_person_level_analysis"] for row in crosswalk)
    assert all(
        row["exclusion_reason"] == "identity_record_conflict" for row in crosswalk
    )


def test_compatible_multi_case_person_is_collapsed() -> None:
    crosswalk = build_identity_crosswalk(
        [
            {
                "case_id": "c1",
                "submitter_id": "TARGET-20-PAYGWX-Unsorted",
                "vital_status": "Alive",
                "age_at_diagnosis_days": 235,
                "days_to_last_follow_up": 9,
                "sex_at_birth": "female",
            },
            {
                "case_id": "c2",
                "submitter_id": "TARGET-20-PAYGWX-Sorted-leukemic",
                "vital_status": "Alive",
                "age_at_diagnosis_days": 235,
                "days_to_last_follow_up": 9,
                "sex_at_birth": "female",
            },
        ]
    )
    persons = {row["analysis_person_id"] for row in crosswalk}
    assert persons == {"TARGET-20-PAYGWX"}
    assert all(row["eligible_for_person_level_analysis"] for row in crosswalk)
    assert sum(row["is_representative_case"] for row in crosswalk) == 1
    representative = next(row for row in crosswalk if row["is_representative_case"])
    assert representative["submitter_id"] == "TARGET-20-PAYGWX-Unsorted"


def test_one_person_appears_at_most_once_in_constructed_rows() -> None:
    crosswalk = build_identity_crosswalk(
        [
            {
                "case_id": "c1",
                "submitter_id": "TARGET-20-PAYGWX-Unsorted",
                "vital_status": "Alive",
                "age_at_diagnosis_days": 235,
                "days_to_last_follow_up": 9,
            },
            {
                "case_id": "c2",
                "submitter_id": "TARGET-20-PAYGWX-Sorted-leukemic",
                "vital_status": "Alive",
                "age_at_diagnosis_days": 235,
                "days_to_last_follow_up": 9,
            },
        ]
    )
    reps = [row for row in crosswalk if row["is_representative_case"]]
    assert len(reps) == 1


def test_covariate_missingness_does_not_exclude() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-AAAAAA",
        "case_id": "c1",
        "submitter_id": "TARGET-20-AAAAAA",
        "eligible_for_person_level_analysis": True,
        "identity_conflict": False,
        "identity_rule": "canonical_usi",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={
            "vital_status": "Alive",
            "days_to_last_follow_up": 40,
            "age_at_diagnosis_days": 2000,
            "index_date": "Diagnosis",
            "wbc": None,
            "flt3": None,
        },
        has_diagnosis=True,
    )
    assert evaluated["primary_cohort_eligible"]
    assert evaluated["primary_exclusion_reason"] is None


def test_endpoint_source_is_recorded() -> None:
    derived = derive_os_endpoint(
        {"vital_status": "Dead", "days_to_death": 12, "index_date": "Diagnosis"}
    )
    assert derived["os_event_source"] == "gdc.demographic.vital_status"
    assert derived["os_time_source"] == "gdc.demographic.days_to_death"


def test_exclusion_reason_populated_for_excluded() -> None:
    identity = {
        "analysis_person_id": "TARGET-20-D7-EC-GFP1",
        "case_id": "c1",
        "submitter_id": "TARGET-20-D7-EC-GFP1",
        "eligible_for_person_level_analysis": False,
        "exclusion_reason": "ambiguous_experimental_d_token",
        "identity_conflict": False,
        "identity_rule": "ambiguous_experimental_d_token",
    }
    evaluated = evaluate_person(
        identity=identity,
        clinical={},
        has_diagnosis=False,
    )
    assert not evaluated["primary_cohort_eligible"]
    assert evaluated["primary_exclusion_reason"]


def test_time_origin_proceeds_when_index_is_diagnosis() -> None:
    report = verify_time_origin(
        [
            {
                "index_date": "Diagnosis",
                "days_to_diagnosis": 0,
                "vital_status": "Alive",
                "days_to_last_follow_up": 10,
            }
        ]
    )
    assert report["origin_is_coherent"]
    assert report["proceed_with_endpoint"]


def test_workbook_family_does_not_treat_tumor_content_as_clinical() -> None:
    name = (
        "TARGET_AML_ClinicalData_Discovery_and_Validation_"
        "Tumor_Content_and_RIN_Supplement_20230720.xlsx"
    )
    assert workbook_family(name) is None
    assert workbook_family("TARGET_AML_ClinicalData_AML1031_20230720.xlsx") == "AML1031"


def test_supplement_precedence_prefers_aml1031_without_averaging() -> None:
    concept = {
        "concept": "wbc_at_diagnosis",
        "column": "WBC at Diagnosis",
        "units": "x10^3/mcL",
        "precedence": ("AML1031", "Discovery", "Validation"),
        "kind": "numeric",
    }
    derived = reconcile_supplement_concept(
        concept=concept,
        rows=[
            {
                "workbook_name": "TARGET_AML_ClinicalData_Discovery_20230720.xlsx",
                "cells": {"WBC at Diagnosis": 20},
            },
            {
                "workbook_name": "TARGET_AML_ClinicalData_AML1031_20230720.xlsx",
                "cells": {"WBC at Diagnosis": 11},
            },
        ],
    )
    assert derived["value"] == "11"
    assert derived["conflict_flag"]
    assert derived["alternative_source_count"] == 1
