"""Write aggregate Stage 5 planning artifacts. No survival associations."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

from pediastat.config import PROJECT_ROOT
from pediastat.model_plan.spec import assert_spec_has_no_results, load_model_spec

DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "model_plan"


def _write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def model_specification_rows(spec: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for model_key, model_name in (
        ("primary_model", "primary_clinical"),
        ("secondary_model", "secondary_molecular"),
    ):
        model = spec[model_key]
        for concept, item in model["predictors"].items():
            rows.append(
                {
                    "model": model_name,
                    "concept": item.get("concept", concept),
                    "analysis_variable": item["variable"],
                    "source": item.get("source", ""),
                    "coding": item.get("coding", ""),
                    "functional_form": item.get("functional_form", ""),
                    "reference_category": item.get("reference") or "",
                    "interpretation": item.get("interpretation", ""),
                    "missing_data_method": item.get("missing_data", ""),
                    "df": item["df"],
                    "role": item["role"],
                }
            )
    return rows


def missing_data_rows(spec: dict[str, Any]) -> list[dict[str, Any]]:
    missing = spec["missing_data"]
    rows = []
    for variable, method in missing["methods"].items():
        rows.append(
            {
                "variable": variable,
                "mice_method": method,
                "imputed": "yes",
                "notes": "",
            }
        )
    for variable in missing["do_not_impute"]:
        rows.append(
            {
                "variable": variable,
                "mice_method": "not_imputed",
                "imputed": "no",
                "notes": "Observed in the frozen primary cohort or identifier/outcome.",
            }
        )
    return rows


def categorical_coding_rows(spec: dict[str, Any]) -> list[dict[str, Any]]:
    coding = spec["coding"]
    rows = [
        {
            "concept": "sex_at_birth",
            "source_value": "female / male (any documented case)",
            "standardized_value": "Female / Male",
            "inferential_status": "observed",
            "reference": coding["sex"]["reference"],
            "notes": (
                "GDC sex at birth. Unknown would be missing; "
                "none in the primary cohort."
            ),
        },
        {
            "concept": "risk_group",
            "source_value": "Low Risk / Standard Risk / High Risk",
            "standardized_value": "Low / Standard / High",
            "inferential_status": "observed",
            "reference": coding["risk_group"]["reference"],
            "notes": "CDE permissible values only.",
        },
        {
            "concept": "risk_group",
            "source_value": "10 / 30",
            "standardized_value": "",
            "inferential_status": "missing_unresolved_token",
            "reference": coding["risk_group"]["reference"],
            "notes": "No CDE mapping. Not guessed from numeric order.",
        },
        {
            "concept": "risk_group",
            "source_value": "Unknown / Not Reported / structurally missing",
            "standardized_value": "",
            "inferential_status": "missing",
            "reference": coding["risk_group"]["reference"],
            "notes": (
                "Unavailable status is missing covariate information, "
                "not a biological level."
            ),
        },
        {
            "concept": "yes_no_molecular_or_lesion",
            "source_value": "Yes / YES / yes",
            "standardized_value": "Yes",
            "inferential_status": "observed",
            "reference": coding["yes_no"]["reference"],
            "notes": "Case harmonization only.",
        },
        {
            "concept": "yes_no_molecular_or_lesion",
            "source_value": "No / NO / no",
            "standardized_value": "No",
            "inferential_status": "observed",
            "reference": coding["yes_no"]["reference"],
            "notes": "Case harmonization only.",
        },
        {
            "concept": "yes_no_molecular_or_lesion",
            "source_value": (
                "Unknown / Not Reported / Not Done / Not Applicable / "
                "structurally missing"
            ),
            "standardized_value": "",
            "inferential_status": "missing",
            "reference": coding["yes_no"]["reference"],
            "notes": "Unavailable status is missing for inferential models.",
        },
    ]
    return rows


def write_model_plan_artifacts(
    output_dir: Path | None = None,
    spec: dict[str, Any] | None = None,
) -> dict[str, Path]:
    spec = spec or load_model_spec()
    assert_spec_has_no_results(spec)
    out = output_dir or DEFAULT_OUTPUT
    out.mkdir(parents=True, exist_ok=True)

    spec_rows = model_specification_rows(spec)
    spec_fields = [
        "model",
        "concept",
        "analysis_variable",
        "source",
        "coding",
        "functional_form",
        "reference_category",
        "interpretation",
        "missing_data_method",
        "df",
        "role",
    ]
    spec_path = out / "model_specification.csv"
    _write_csv(spec_path, spec_rows, spec_fields)

    deaths = spec["cohort"]["deaths"]
    primary_df = spec["primary_model"]["df"]
    secondary_df = spec["secondary_model"]["df"]
    df_payload = {
        "primary_cohort_n": spec["cohort"]["n"],
        "deaths": deaths,
        "censored": spec["cohort"]["censored"],
        "primary_clinical": {
            "model": spec["primary_model"]["formula"],
            "df": primary_df,
            "events_per_df": deaths / primary_df,
            "components": {
                "age5": 1,
                "sex_std": 1,
                "log2_wbc": 1,
                "risk_group_std": 2,
            },
        },
        "secondary_molecular": {
            "model": spec["secondary_model"]["formula"],
            "df": secondary_df,
            "events_per_df": deaths / secondary_df,
            "components": {
                "age5": 1,
                "sex_std": 1,
                "log2_wbc": 1,
                "flt3_itd_std": 1,
                "npm_std": 1,
                "cebpa_std": 1,
                "cytogenetics_t821_std": 1,
                "cytogenetics_inv16_std": 1,
                "cytogenetics_mll_std": 1,
                "cytogenetics_monosomy7_std": 1,
            },
        },
        "note": (
            "Events-per-df is a complexity descriptor, not a formal power calculation "
            "and not a reason to drop prespecified predictors."
        ),
        "overparameterized": False,
    }
    df_path = out / "model_degrees_of_freedom.json"
    _write_json(df_path, df_payload)

    miss_path = out / "missing_data_plan.csv"
    _write_csv(
        miss_path,
        missing_data_rows(spec),
        ["variable", "mice_method", "imputed", "notes"],
    )

    coding_path = out / "categorical_coding_plan.csv"
    _write_csv(
        coding_path,
        categorical_coding_rows(spec),
        [
            "concept",
            "source_value",
            "standardized_value",
            "inferential_status",
            "reference",
            "notes",
        ],
    )

    fdr_rows = [
        {
            "coefficient": name,
            "family": "secondary_molecular_cytogenetic",
            "adjustment": "benjamini_hochberg",
            "included_because": "prespecified secondary biological predictor",
        }
        for name in spec["multiplicity"]["secondary"]["fdr_family"]
    ]
    fdr_path = out / "secondary_fdr_family.csv"
    _write_csv(
        fdr_path,
        fdr_rows,
        ["coefficient", "family", "adjustment", "included_because"],
    )

    return {
        "model_specification": spec_path,
        "model_degrees_of_freedom": df_path,
        "missing_data_plan": miss_path,
        "categorical_coding_plan": coding_path,
        "secondary_fdr_family": fdr_path,
    }
