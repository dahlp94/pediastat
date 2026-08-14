"""Stage 5 inferential-plan tests. No Cox fits. No mice execution."""

from __future__ import annotations

import math
from pathlib import Path

import pytest

from pediastat.config import PROJECT_ROOT
from pediastat.model_plan.artifacts import write_model_plan_artifacts
from pediastat.model_plan.coding import (
    UNRESOLVED_RISK_FLAG,
    age5,
    factor_levels,
    harmonize_yes_no,
    log2_wbc,
    standardize_risk_group,
    standardize_sex,
)
from pediastat.model_plan.spec import assert_spec_has_no_results, load_model_spec

R_DIR = PROJECT_ROOT / "analysis" / "R"
SPEC = load_model_spec()


def test_age5_is_years_divided_by_five() -> None:
    assert age5(10.0) == pytest.approx(2.0)
    assert age5(0.0) == pytest.approx(0.0)
    assert age5(None) is None


def test_log2_wbc_is_log2_of_positive_values() -> None:
    assert log2_wbc(8.0) == pytest.approx(3.0)
    assert log2_wbc(26.7) == pytest.approx(math.log2(26.7))


def test_log2_wbc_rejects_nonpositive() -> None:
    assert log2_wbc(0.0) is None
    assert log2_wbc(-1.0) is None
    assert log2_wbc(None) is None


def test_yes_no_case_harmonization() -> None:
    coding = SPEC["coding"]["yes_no"]
    kwargs = dict(
        yes_tokens=coding["yes_tokens"],
        no_tokens=coding["no_tokens"],
        missing_tokens=coding["missing_tokens"],
    )
    assert harmonize_yes_no("YES", **kwargs) == "Yes"
    assert harmonize_yes_no("NO", **kwargs) == "No"
    assert harmonize_yes_no("Yes", **kwargs) == "Yes"
    assert harmonize_yes_no("Unknown", **kwargs) is None


def test_risk_group_maps_cde_labels_only() -> None:
    coding = SPEC["coding"]["risk_group"]
    mapped = standardize_risk_group(
        "Low Risk",
        mapping=coding["map"],
        unresolved_tokens=coding["unresolved_tokens"],
        missing_tokens=coding["missing_tokens"],
    )
    assert mapped["standardized"] == "Low"
    assert mapped["mapping_action"] == "mapped"


def test_unresolved_risk_codes_become_missing() -> None:
    coding = SPEC["coding"]["risk_group"]
    for token in ("10", "30"):
        result = standardize_risk_group(
            token,
            mapping=coding["map"],
            unresolved_tokens=coding["unresolved_tokens"],
            missing_tokens=coding["missing_tokens"],
        )
        assert result["standardized"] is None
        assert result["original"] == token
        assert result["qa_flag"] == UNRESOLVED_RISK_FLAG
        assert result["mapping_action"] == "unresolved_set_missing"


def test_unknown_risk_is_missing_not_a_level() -> None:
    coding = SPEC["coding"]["risk_group"]
    result = standardize_risk_group(
        "Unknown",
        mapping=coding["map"],
        unresolved_tokens=coding["unresolved_tokens"],
        missing_tokens=coding["missing_tokens"],
    )
    assert result["standardized"] is None
    assert result["mapping_action"] == "source_missing"


def test_sex_reference_is_female() -> None:
    coding = SPEC["coding"]["sex"]
    assert standardize_sex("male", coding["map"], coding["missing_tokens"]) == "Male"
    assert (
        standardize_sex("female", coding["map"], coding["missing_tokens"]) == "Female"
    )
    levels = factor_levels(["Male", "Female"], coding["reference"])
    assert levels[0] == "Female"


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


def test_export_model_plan_artifacts(tmp_path: Path) -> None:
    paths = write_model_plan_artifacts(tmp_path, SPEC)
    spec_csv = (tmp_path / "model_specification.csv").read_text(encoding="utf-8")
    assert "primary_clinical" in spec_csv
    assert "secondary_molecular" in spec_csv
    assert "hazard" not in spec_csv.lower() or "HR per" in spec_csv
    fdr = (tmp_path / "secondary_fdr_family.csv").read_text(encoding="utf-8")
    assert "age5" not in fdr
    assert "flt3_itd_std" in fdr
    df_json = (tmp_path / "model_degrees_of_freedom.json").read_text(encoding="utf-8")
    assert "139" in df_json
    assert paths["model_specification"].exists()


def test_committed_model_plan_has_no_patient_level_extracts() -> None:
    plan_dir = PROJECT_ROOT / "artifacts" / "model_plan"
    if not plan_dir.exists():
        pytest.skip("model plan artifacts not generated")
    forbidden = list(plan_dir.glob("*.rds")) + [
        path for path in plan_dir.glob("*.csv") if "extract" in path.name
    ]
    assert forbidden == []
