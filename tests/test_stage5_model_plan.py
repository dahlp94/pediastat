"""Stage 5 inferential-plan tests. No Cox fits. No mice execution."""

from __future__ import annotations

import pytest

from pediastat.config import (
    PROJECT_ROOT,
    assert_spec_has_no_results,
    load_model_spec,
)

R_DIR = PROJECT_ROOT / "analysis" / "R"
SPEC = load_model_spec()


def test_primary_and_secondary_formulas_are_separated() -> None:
    primary = SPEC["primary_model"]["formula"]
    secondary = SPEC["secondary_model"]["formula"]

    assert "risk_group_std" in primary
    assert "flt3_itd_std" not in primary
    assert "cytogenetics_" not in primary
    assert "risk_group" not in secondary
    assert "flt3_itd_std" in secondary
    assert SPEC["primary_model"]["interactions"] == []
    assert SPEC["secondary_model"]["interactions"] == []


def test_fdr_family_is_biological_predictors_only() -> None:
    family = SPEC["multiplicity"]["secondary"]["fdr_family"]

    assert family == [
        "flt3_itd_std",
        "npm_std",
        "cebpa_std",
        "cytogenetics_t821_std",
        "cytogenetics_inv16_std",
        "cytogenetics_mll_std",
        "cytogenetics_monosomy7_std",
    ]

    for excluded in SPEC["multiplicity"]["secondary"]["fdr_not_applied_to"]:
        assert excluded not in family


def test_mi_does_not_impute_outcome_or_id() -> None:
    forbidden = set(SPEC["missing_data"]["do_not_impute"])

    assert "os_event" in forbidden
    assert "os_days" in forbidden
    assert "analysis_person_id" in forbidden
    assert "age5" in forbidden
    assert "sex_std" in forbidden

    methods = SPEC["missing_data"]["methods"]
    for name in forbidden:
        assert name not in methods

    assert SPEC["missing_data"]["m"] == 30
    assert SPEC["missing_data"]["implementation"] == "mice"


def test_model_spec_contains_no_results() -> None:
    assert_spec_has_no_results(SPEC)


def test_events_per_df_are_recorded() -> None:
    deaths = SPEC["cohort"]["deaths"]

    assert deaths == 695
    assert SPEC["primary_model"]["df"] == 5
    assert SPEC["secondary_model"]["df"] == 10
    assert deaths / 5 == pytest.approx(139.0)
    assert deaths / 10 == pytest.approx(69.5)


def test_stage5_r_scripts_do_not_fit_cox_or_run_mice() -> None:
    stage5 = [
        R_DIR / "10_model_coding.R",
        R_DIR / "11_preflight.R",
        R_DIR / "run_stage5.R",
        R_DIR / "tests" / "test_stage5.R",
    ]

    for path in stage5:
        text = path.read_text(encoding="utf-8")
        assert "coxph(" not in text, f"{path} contains coxph("
        assert "mice(" not in text, f"{path} contains mice("
        assert "survdiff(" not in text, f"{path} contains survdiff("
        assert "cox.zph(" not in text, f"{path} contains cox.zph("


def test_committed_model_plan_has_no_patient_level_extracts() -> None:
    plan_dir = PROJECT_ROOT / "artifacts" / "model_plan"

    if not plan_dir.exists():
        pytest.skip("model plan artifacts not generated")

    forbidden = list(plan_dir.glob("*.rds")) + [
        path for path in plan_dir.glob("*.csv") if "extract" in path.name
    ]

    assert forbidden == []