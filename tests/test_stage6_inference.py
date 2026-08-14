"""Stage 6 inferential-execution checks. No live database required."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from pediastat.config import PROJECT_ROOT
from pediastat.model_plan.spec import load_model_spec

R_DIR = PROJECT_ROOT / "analysis" / "R"
INF_DIR = PROJECT_ROOT / "artifacts" / "inference"
GITIGNORE = PROJECT_ROOT / ".gitignore"
SPEC = load_model_spec()


def test_stage6_scripts_exist() -> None:
    expected = [
        "20_prepare_inferential_data.R",
        "21_mi_specification.R",
        "22_run_multiple_imputation.R",
        "23_fit_cox_models.R",
        "25_nonlinear_sensitivity.R",
        "26_ph_diagnostics.R",
        "27_influence_diagnostics.R",
        "28_stratified_km.R",
        "29_generate_model_outputs.R",
        "30_render_stage6_report.R",
        "run_stage6.R",
        "tests/test_stage6.R",
    ]
    for name in expected:
        assert (R_DIR / name).is_file(), name


def test_frozen_spec_still_has_no_results() -> None:
    from pediastat.model_plan.spec import assert_spec_has_no_results

    assert_spec_has_no_results(SPEC)
    assert SPEC["missing_data"]["m"] == 30
    assert SPEC["missing_data"]["seed"] == 20260814
    assert "risk_group" not in SPEC["secondary_model"]["formula"]
    assert SPEC["primary_model"]["interactions"] == []


def test_fdr_family_unchanged() -> None:
    assert SPEC["multiplicity"]["secondary"]["fdr_family"] == [
        "flt3_itd_std",
        "npm_std",
        "cebpa_std",
        "cytogenetics_t821_std",
        "cytogenetics_inv16_std",
        "cytogenetics_mll_std",
        "cytogenetics_monosomy7_std",
    ]


def test_gitignore_excludes_stage6_patient_level_files() -> None:
    text = GITIGNORE.read_text(encoding="utf-8")
    assert "data/interim/stage6/" in text
    assert "artifacts/inference/**/*.rds" in text


def test_inference_directory_exists() -> None:
    assert (PROJECT_ROOT / "artifacts" / "inference").is_dir()


def test_no_committed_patient_level_inference_files() -> None:
    result = subprocess.run(
        ["git", "ls-files", "data/interim/stage6", "artifacts/inference"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    tracked = result.stdout.splitlines()
    forbidden = [
        path
        for path in tracked
        if path.endswith((".rds", ".RData"))
        or "patient" in Path(path).name.lower()
        or "dfbeta" in Path(path).name.lower()
    ]
    assert forbidden == []


@pytest.mark.skipif(
    not (INF_DIR / "model_metadata.json").exists(),
    reason="Stage 6 artifacts have not been generated",
)
def test_metadata_matches_frozen_cohort_and_mi() -> None:
    payload = json.loads((INF_DIR / "model_metadata.json").read_text(encoding="utf-8"))
    assert payload["cohort_n"] == 1978
    assert payload["deaths"] == 695
    assert payload["m"] == 30
    assert payload["seed"] == 20260814
    assert payload["ties"] == "efron"
    assert payload["patient_level_data_included"] is False
    assert "risk_group" not in payload["secondary_formula"]


@pytest.mark.skipif(
    not (INF_DIR / "primary_cox_mi.csv").exists(),
    reason="Stage 6 artifacts have not been generated",
)
def test_primary_result_terms_and_no_patient_ids() -> None:
    text = (INF_DIR / "primary_cox_mi.csv").read_text(encoding="utf-8")
    assert "age5" in text
    assert "log2_wbc" in text
    assert "risk_group_stdHigh" in text
    assert "flt3_itd" not in text
    assert "analysis_person_id" not in text
    assert "TARGET-20-" not in text


@pytest.mark.skipif(
    not (INF_DIR / "stratified_km_estimates.csv").exists(),
    reason="Stage 6 artifacts have not been generated",
)
def test_km_limited_to_frozen_predictors() -> None:
    text = (INF_DIR / "stratified_km_estimates.csv").read_text(encoding="utf-8")
    assert "risk_group_std" in text
    assert "flt3_itd_std" in text
    assert "cebpa" not in text
    assert "npm" not in text
