"""Descriptive-analysis checks. No live database required."""

from __future__ import annotations

from pathlib import Path

import pytest

from pediastat.config import PROJECT_ROOT

R_DIR = PROJECT_ROOT / "analysis" / "R"
DESC_DIR = PROJECT_ROOT / "artifacts" / "descriptive"
GITIGNORE = PROJECT_ROOT / ".gitignore"


def _descriptive_scripts() -> list[Path]:
    names = {
        "setup.R",
        "descriptive.R",
        "render_descriptive_report.R",
        "run_descriptive.R",
        "test_descriptive.R",
    }
    return [path for path in R_DIR.rglob("*.R") if path.name in names]


def test_descriptive_scripts_do_not_fit_cox_or_logrank() -> None:
    for path in _descriptive_scripts():
        text = path.read_text(encoding="utf-8")
        assert "coxph(" not in text, f"{path} contains coxph("
        assert "survdiff(" not in text, f"{path} contains survdiff("
        assert "cox.zph(" not in text, f"{path} contains cox.zph("


def test_gitignore_excludes_patient_level_extracts() -> None:
    text = GITIGNORE.read_text(encoding="utf-8")
    assert "data/interim/*" in text
    assert "data/interim/stage4/" in text or "data/interim/*" in text


def test_no_committed_patient_level_extract_files() -> None:
    import subprocess

    result = subprocess.run(
        ["git", "ls-files", "data/interim/stage4", "artifacts/descriptive"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    tracked = result.stdout.splitlines()
    forbidden = [
        path
        for path in tracked
        if path.endswith((".csv", ".rds")) and "primary_cohort_extract" in path
    ]
    assert forbidden == []


def test_cohort_extract_view_does_not_filter_eligibility() -> None:
    sql = (PROJECT_ROOT / "sql" / "08_create_stage4_extract_view.sql").read_text(
        encoding="utf-8"
    )
    assert "analytics.primary_os_cohort" in sql
    assert "age_at_diagnosis_years < 18" not in sql
    assert "os_event =" not in sql


@pytest.mark.skipif(
    not (DESC_DIR / "endpoint_followup_description.json").exists(),
    reason="Descriptive artifacts have not been generated",
)
def test_endpoint_artifact_matches_frozen_cohort() -> None:
    import json

    payload = json.loads(
        (DESC_DIR / "endpoint_followup_description.json").read_text(encoding="utf-8")
    )
    assert payload["primary_cohort_n"] == 1978
    assert payload["deaths"] == 695
    assert payload["censored"] == 1283


@pytest.mark.skipif(
    not (DESC_DIR / "table1_primary_cohort.csv").exists(),
    reason="Descriptive artifacts have not been generated",
)
def test_table1_has_no_pvalue_column() -> None:
    import csv

    with (DESC_DIR / "table1_primary_cohort.csv").open(encoding="utf-8") as handle:
        header = next(csv.reader(handle))
    joined = " ".join(header).lower()
    assert "p.value" not in joined
    assert "p-value" not in joined
    assert "pvalue" not in joined


@pytest.mark.skipif(
    not (DESC_DIR / "figures").is_dir(),
    reason="Descriptive figures have not been generated",
)
def test_only_overall_km_figure_exists() -> None:
    figures = [path.name for path in (DESC_DIR / "figures").glob("*.png")]
    assert "overall_kaplan_meier.png" in figures
    stratified = [
        name
        for name in figures
        if any(
            token in name.lower()
            for token in (
                "by_risk",
                "by_flt3",
                "by_sex",
                "by_age",
                "by_wbc",
                "by_fab",
                "stratified",
            )
        )
    ]
    assert stratified == []


@pytest.mark.skipif(
    not (DESC_DIR / "overall_survival_estimates.csv").exists(),
    reason="Descriptive artifacts have not been generated",
)
def test_km_estimates_are_probabilities() -> None:
    import csv

    with (DESC_DIR / "overall_survival_estimates.csv").open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    times = {float(row["time_years"]) for row in rows}
    assert {1.0, 3.0, 5.0} <= times
    for row in rows:
        surv = float(row["survival"])
        assert 0.0 <= surv <= 1.0
        assert float(row["surv_lcl"]) <= surv <= float(row["surv_ucl"])
