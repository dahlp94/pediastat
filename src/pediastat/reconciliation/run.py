"""Run Stage 2 source-reconciliation QA from staging tables."""

from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.engine import Engine

from pediastat.config import PROJECT_ROOT
from pediastat.ingestion.identifiers import summarize_identifiers
from pediastat.ingestion.missingness import classify_missing, is_observed
from pediastat.reconciliation.age import summarize_age_days
from pediastat.reconciliation.concepts import CONCEPT_SOURCES, CYTOGENETIC_COLUMNS
from pediastat.reconciliation.discordance import (
    categorical_agreement,
    numeric_discordance,
)
from pediastat.reconciliation.overlap import (
    overlap_distribution,
    pairwise_overlap_counts,
    universe_overlap,
)

DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "ingestion_audit"
DETAIL_DIR = PROJECT_ROOT / "data" / "interim" / "ingestion_audit"
NUMERIC_CONCEPTS = {
    "os_time": "os_time_days",
    "age_at_diagnosis": "age_at_diagnosis_days",
    "wbc": "wbc_raw",
    "marrow_blasts": "marrow_blasts_raw",
    "peripheral_blasts": "peripheral_blasts_raw",
}
CATEGORICAL_CONCEPTS = {
    "vital_status": "vital_status_raw",
    "sex": "sex_raw",
    "race": "race_raw",
    "ethnicity": "ethnicity_raw",
    "risk_group": "risk_group_raw",
    "flt3_itd": "flt3_itd_raw",
    "npm": "npm_raw",
    "cebpa": "cebpa_raw",
    "fab": "fab_raw",
    "cns_disease": "cns_disease_raw",
}
GDC_CONCEPT_VALUES = {
    "demographic.vital_status": ("demographics", "vital_status_raw"),
    "demographic.days_to_death": ("demographics", "days_to_death"),
    "diagnoses.days_to_last_follow_up": ("diagnoses", "days_to_last_follow_up"),
    "follow_ups.days_to_follow_up": ("follow_ups", "days_to_follow_up"),
    "diagnoses.age_at_diagnosis": ("diagnoses", "age_at_diagnosis_days"),
    "demographic.sex_at_birth": ("demographics", "sex_at_birth_raw"),
    "demographic.race": ("demographics", "race_raw"),
    "demographic.ethnicity": ("demographics", "ethnicity_raw"),
}


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _cells(row: Mapping[str, Any]) -> dict[str, Any]:
    value = row.get("cells")
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return {}


def _pct_missing(values: list[Any]) -> float | None:
    if not values:
        return None
    missing = sum(not is_observed(value) for value in values)
    return round(missing / len(values) * 100.0, 2)


def _concept_map_rows(data: dict[str, Any]) -> list[dict[str, Any]]:
    """Expand concept templates onto actual workbooks and observed missingness."""
    rows: list[dict[str, Any]] = []
    supp_by_wb: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in data["supplements"]:
        supp_by_wb[row["workbook_name"]].append(dict(row))
    sheet_by_wb: dict[str, str] = {}
    for sheet in data["sheets"]:
        if sheet["is_patient_level"]:
            sheet_by_wb[sheet["workbook_name"]] = sheet["sheet_name"]
    for item in CONCEPT_SOURCES:
        if item["source_kind"] == "gdc_cases_api":
            table_key, column = GDC_CONCEPT_VALUES.get(
                item["source_column"], (None, None)
            )
            values = (
                [row.get(column) for row in data[table_key]]
                if table_key and column
                else []
            )
            rows.append(
                {
                    "concept": item["concept"],
                    "source_workbook": None,
                    "source_sheet": None,
                    "source_entity": item["source_entity"],
                    "source_column": item["source_column"],
                    "source_definition_if_known": item["source_definition"],
                    "type": item["type"],
                    "units": item["units"],
                    "coding": item["coding"],
                    "missing_percent": _pct_missing(values),
                    "n_records": len(values),
                    "notes": item["notes"],
                }
            )
            continue
        column = item["source_column"]
        for workbook, recs in sorted(supp_by_wb.items()):
            present = any(column in _cells(row) for row in recs)
            if not present:
                continue
            values = [_cells(row).get(column) for row in recs]
            rows.append(
                {
                    "concept": item["concept"],
                    "source_workbook": workbook,
                    "source_sheet": sheet_by_wb.get(workbook),
                    "source_entity": "supplement_row",
                    "source_column": column,
                    "source_definition_if_known": item["source_definition"],
                    "type": item["type"],
                    "units": item["units"],
                    "coding": item["coding"],
                    "missing_percent": _pct_missing(values),
                    "n_records": len(values),
                    "notes": item["notes"],
                }
            )
    return rows


def _identifier_quality_rows(data: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    gdc = summarize_identifiers([row["submitter_id"] for row in data["gdc_cases"]])
    gdc["source"] = "gdc_cases"
    gdc["workbook"] = None
    gdc["shapes"] = json.dumps(gdc.pop("shapes"), sort_keys=True)
    rows.append(gdc)
    by_wb: dict[str, list[Any]] = defaultdict(list)
    for row in data["supplements"]:
        by_wb[row["workbook_name"]].append(row["original_identifier"])
    for workbook, values in sorted(by_wb.items()):
        summary = summarize_identifiers(values)
        summary["source"] = "patient_level_supplement"
        summary["workbook"] = workbook
        summary["shapes"] = json.dumps(summary.pop("shapes"), sort_keys=True)
        rows.append(summary)
    return rows


def _os_status_patterns(
    pairs: list[tuple[Any, Any]],
) -> dict[str, int]:
    counts: Counter[str] = Counter()
    for left, right in pairs:
        left_key = (
            str(left).strip().lower() if is_observed(left) else classify_missing(left)
        )
        right_key = (
            str(right).strip().lower()
            if is_observed(right)
            else classify_missing(right)
        )
        counts[f"{left_key}|{right_key}"] += 1
    return dict(counts)


def _fetch_maps(engine: Engine) -> dict[str, Any]:
    with engine.connect() as connection:
        gdc_cases = list(
            connection.execute(
                text(
                    """
                    SELECT case_id, submitter_id, submitter_id_normalized, join_barcode
                    FROM staging.gdc_cases
                    """
                )
            ).mappings()
        )
        demographics = list(
            connection.execute(
                text("SELECT * FROM staging.gdc_demographics")
            ).mappings()
        )
        diagnoses = list(
            connection.execute(text("SELECT * FROM staging.gdc_diagnoses")).mappings()
        )
        follow_ups = list(
            connection.execute(text("SELECT * FROM staging.gdc_follow_ups")).mappings()
        )
        treatments = list(
            connection.execute(text("SELECT * FROM staging.gdc_treatments")).mappings()
        )
        supplements = list(
            connection.execute(
                text(
                    """
                    SELECT * FROM staging.supplement_clinical_rows
                    WHERE sheet_name IN ('Clinical Data', 'Sheet1')
                    """
                )
            ).mappings()
        )
        sheets = list(
            connection.execute(text("SELECT * FROM raw.supplement_sheets")).mappings()
        )
        registry = list(
            connection.execute(text("SELECT * FROM raw.source_registry")).mappings()
        )
        raw_counts = {
            "gdc_cases": connection.execute(
                text("SELECT COUNT(*) FROM raw.gdc_cases")
            ).scalar_one(),
            "gdc_demographics": connection.execute(
                text("SELECT COUNT(*) FROM raw.gdc_demographics")
            ).scalar_one(),
            "gdc_diagnoses": connection.execute(
                text("SELECT COUNT(*) FROM raw.gdc_diagnoses")
            ).scalar_one(),
            "gdc_follow_ups": connection.execute(
                text("SELECT COUNT(*) FROM raw.gdc_follow_ups")
            ).scalar_one(),
            "gdc_treatments": connection.execute(
                text("SELECT COUNT(*) FROM raw.gdc_treatments")
            ).scalar_one(),
            "supplement_rows": connection.execute(
                text("SELECT COUNT(*) FROM raw.supplement_rows")
            ).scalar_one(),
        }
    return {
        "gdc_cases": gdc_cases,
        "demographics": demographics,
        "diagnoses": diagnoses,
        "follow_ups": follow_ups,
        "treatments": treatments,
        "supplements": supplements,
        "sheets": sheets,
        "registry": registry,
        "raw_counts": raw_counts,
    }


def _gdc_os_index(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    demo = {
        row["join_barcode"]: row
        for row in data["demographics"]
        if row["join_barcode"]
    }
    dx = {row["join_barcode"]: row for row in data["diagnoses"] if row["join_barcode"]}
    last_contact: dict[str, list[float]] = defaultdict(list)
    any_fu: dict[str, list[float]] = defaultdict(list)
    for row in data["follow_ups"]:
        barcode = row["join_barcode"]
        time = row["days_to_follow_up"]
        if barcode is None or time is None:
            continue
        any_fu[barcode].append(float(time))
        if row["timepoint_category"] == "Last Contact":
            last_contact[barcode].append(float(time))
    index: dict[str, dict[str, Any]] = {}
    for barcode, row in demo.items():
        status = row["vital_status_analysis_class"]
        death = row["days_to_death"]
        follow = dx.get(barcode, {}).get("days_to_last_follow_up")
        candidate = None
        if status == "dead" and death is not None:
            candidate = float(death)
        elif status == "alive" and follow is not None:
            candidate = float(follow)
        index[barcode] = {
            "vital_status_raw": row["vital_status_raw"],
            "vital_status_class": status,
            "days_to_death": death,
            "days_to_last_follow_up": follow,
            "last_contact_days": (
                max(last_contact[barcode]) if last_contact[barcode] else None
            ),
            "max_follow_up_days": max(any_fu[barcode]) if any_fu[barcode] else None,
            "candidate_os_days": candidate,
            "age_at_diagnosis_days": dx.get(barcode, {}).get("age_at_diagnosis_days"),
            "sex_at_birth": row["sex_at_birth_raw"],
            "race": row["race_raw"],
            "ethnicity": row["ethnicity_raw"],
        }
    return index


def run_reconciliation(
    engine: Engine,
    output_dir: Path = DEFAULT_OUTPUT,
    detail_dir: Path = DETAIL_DIR,
) -> dict[str, Any]:
    data = _fetch_maps(engine)
    output_dir.mkdir(parents=True, exist_ok=True)
    detail_dir.mkdir(parents=True, exist_ok=True)

    gdc_ids = {
        row["join_barcode"]
        for row in data["gdc_cases"]
        if row["join_barcode"]
    }
    supp_by_file: dict[str, set[str]] = defaultdict(set)
    supp_rows_by_file: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    for row in data["supplements"]:
        barcode = row["join_barcode"]
        if not barcode:
            continue
        workbook = row["workbook_name"]
        supp_by_file[workbook].add(barcode)
        supp_rows_by_file[workbook][barcode] = dict(row)
    all_supp = set().union(*supp_by_file.values()) if supp_by_file else set()

    id_overlap = universe_overlap(gdc_ids, all_supp)
    id_overlap_out = {
        "gdc_unique_join_barcodes": id_overlap["n_left"],
        "supplement_unique_join_barcodes": id_overlap["n_right"],
        "intersection": id_overlap["n_intersection"],
        "gdc_only": id_overlap["n_left_only"],
        "supplement_only": id_overlap["n_right_only"],
        "pct_gdc_matched": id_overlap["pct_left_matched"],
        "pct_supplement_matched": id_overlap["pct_right_matched"],
        "normalization_rule": (
            "strip whitespace, uppercase; join_barcode is leading TARGET-NN-TOKEN; "
            "suffixes such as -Unsorted are kept on normalized_identifier"
        ),
    }
    _write_json(output_dir / "source_identifier_overlap.json", id_overlap_out)
    _write_csv(
        output_dir / "unmatched_identifier_summary.csv",
        [
            {
                "universe": "gdc_only",
                "n_identifiers": id_overlap["n_left_only"],
                "note": (
                    "Present in GDC staging.gdc_cases, not in patient-level supplements"
                ),
            },
            {
                "universe": "supplement_only",
                "n_identifiers": id_overlap["n_right_only"],
                "note": "Present in patient-level supplements, not in GDC cases",
            },
            {
                "universe": "intersection",
                "n_identifiers": id_overlap["n_intersection"],
                "note": "Matched on join_barcode",
            },
        ],
    )

    pair_rows = pairwise_overlap_counts(supp_by_file)
    _write_csv(output_dir / "supplement_overlap_matrix.csv", pair_rows)
    dist_rows = overlap_distribution(supp_by_file)
    _write_csv(output_dir / "supplement_overlap_distribution.csv", dist_rows)

    id_quality_rows = _identifier_quality_rows(data)
    _write_csv(output_dir / "supplement_identifier_quality.csv", id_quality_rows)
    gdc_id_summary = next(
        row for row in id_quality_rows if row["source"] == "gdc_cases"
    )
    supp_id_summary = summarize_identifiers(
        [row["original_identifier"] for row in data["supplements"]]
    )
    supp_id_summary["source"] = "patient_level_supplements"

    sheet_summary = []
    for sheet in data["sheets"]:
        sheet_summary.append(
            {
                "workbook": sheet["workbook_name"],
                "sheet": sheet["sheet_name"],
                "n_rows": sheet["n_rows"],
                "n_columns": sheet["n_columns"],
                "identifier_field": sheet["identifier_field"],
                "is_patient_level": sheet["is_patient_level"],
            }
        )
    _write_csv(output_dir / "supplement_sheet_summary.csv", sheet_summary)

    concept_rows = _concept_map_rows(data)
    _write_csv(output_dir / "clinical_concept_source_map.csv", concept_rows)

    gdc_os = _gdc_os_index(data)
    os_rows: list[dict[str, Any]] = []
    os_detail_rows: list[dict[str, Any]] = []
    gdc_vs_supp_rows: list[dict[str, Any]] = []
    for workbook, rows in supp_rows_by_file.items():
        pairs_status = []
        pairs_time = []
        pairs_last_contact = []
        pairs_age = []
        pairs_sex = []
        n_zero_os = 0
        n_neg_os = 0
        n_zero_gdc = 0
        n_neg_gdc = 0
        shared = set(rows) & set(gdc_os)
        for barcode in shared:
            gdc = gdc_os[barcode]
            supp = rows[barcode]
            pairs_status.append((gdc["vital_status_raw"], supp.get("vital_status_raw")))
            pairs_time.append((gdc["candidate_os_days"], supp.get("os_time_days")))
            pairs_last_contact.append(
                (gdc["last_contact_days"], supp.get("os_time_days"))
            )
            pairs_age.append(
                (gdc["age_at_diagnosis_days"], supp.get("age_at_diagnosis_days"))
            )
            pairs_sex.append((gdc["sex_at_birth"], supp.get("sex_raw")))
            os_time = supp.get("os_time_days")
            if os_time == 0:
                n_zero_os += 1
            if os_time is not None and os_time < 0:
                n_neg_os += 1
            gdc_time = gdc["candidate_os_days"]
            if gdc_time == 0:
                n_zero_gdc += 1
            if gdc_time is not None and gdc_time < 0:
                n_neg_gdc += 1
            status_match = categorical_agreement(
                [(gdc["vital_status_raw"], supp.get("vital_status_raw"))]
            )
            time_match = numeric_discordance(
                [(gdc["candidate_os_days"], supp.get("os_time_days"))]
            )
            if status_match["n_disagreements"] or time_match["n_disagreements"]:
                os_detail_rows.append(
                    {
                        "join_barcode": barcode,
                        "workbook": workbook,
                        "gdc_vital_status": gdc["vital_status_raw"],
                        "supplement_vital_status": supp.get("vital_status_raw"),
                        "gdc_candidate_os_days": gdc["candidate_os_days"],
                        "gdc_days_to_death": gdc["days_to_death"],
                        "gdc_days_to_last_follow_up": gdc["days_to_last_follow_up"],
                        "gdc_last_contact_days": gdc["last_contact_days"],
                        "supplement_os_time_days": supp.get("os_time_days"),
                    }
                )
        status = categorical_agreement(pairs_status)
        times = numeric_discordance(pairs_time)
        last_contact = numeric_discordance(pairs_last_contact)
        ages = numeric_discordance(pairs_age)
        sex = categorical_agreement(pairs_sex)
        patterns = _os_status_patterns(pairs_status)
        os_rows.append(
            {
                "comparison": f"gdc_vs_{workbook}",
                "n_shared_patients": len(shared),
                "vital_status_both_observed": status["n_both_observed"],
                "vital_status_agreements": status["n_agreements"],
                "vital_status_disagreements": status["n_disagreements"],
                "vital_status_agreement_percent": status["agreement_percent"],
                "vital_status_pair_patterns": json.dumps(patterns, sort_keys=True),
                "os_time_both_observed": times["n_both_observed"],
                "os_time_exact_agreements": times["n_exact_agreements"],
                "os_time_within_one_day": times["n_within_one"],
                "os_time_agreement_percent": times["agreement_percent"],
                "os_time_diff_min": times["diff_min"],
                "os_time_diff_max": times["diff_max"],
                "os_time_abs_diff_median": times["abs_diff_median"],
                "last_contact_vs_os_exact": last_contact["n_exact_agreements"],
                "last_contact_vs_os_both_observed": last_contact["n_both_observed"],
                "last_contact_vs_os_agreement_percent": last_contact[
                    "agreement_percent"
                ],
                "age_exact_agreements": ages["n_exact_agreements"],
                "age_both_observed": ages["n_both_observed"],
                "age_agreement_percent": ages["agreement_percent"],
                "sex_agreement_percent": sex["agreement_percent"],
                "sex_disagreements": sex["n_disagreements"],
                "supplement_zero_os_times_in_overlap": n_zero_os,
                "supplement_negative_os_times_in_overlap": n_neg_os,
                "gdc_zero_candidate_os_in_overlap": n_zero_gdc,
                "gdc_negative_candidate_os_in_overlap": n_neg_gdc,
            }
        )
        gdc_vs_supp_rows.extend(
            [
                {
                    "workbook": workbook,
                    "concept": "vital_status",
                    **{
                        key: status[key]
                        for key in (
                            "n_both_observed",
                            "n_agreements",
                            "n_disagreements",
                            "agreement_percent",
                            "n_missing_a_only",
                            "n_missing_b_only",
                            "n_missing_both",
                        )
                    },
                },
                {
                    "workbook": workbook,
                    "concept": "os_time_gdc_candidate_vs_supplement",
                    "n_both_observed": times["n_both_observed"],
                    "n_agreements": times["n_exact_agreements"],
                    "n_disagreements": times["n_disagreements"],
                    "agreement_percent": times["agreement_percent"],
                    "n_missing_a_only": times["n_missing_a_only"],
                    "n_missing_b_only": times["n_missing_b_only"],
                    "n_missing_both": times["n_missing_both"],
                },
                {
                    "workbook": workbook,
                    "concept": "age_at_diagnosis",
                    "n_both_observed": ages["n_both_observed"],
                    "n_agreements": ages["n_exact_agreements"],
                    "n_disagreements": ages["n_disagreements"],
                    "agreement_percent": ages["agreement_percent"],
                    "n_missing_a_only": ages["n_missing_a_only"],
                    "n_missing_b_only": ages["n_missing_b_only"],
                    "n_missing_both": ages["n_missing_both"],
                },
                {
                    "workbook": workbook,
                    "concept": "sex_gdc_sex_at_birth_vs_supplement_gender",
                    **{
                        key: sex[key]
                        for key in (
                            "n_both_observed",
                            "n_agreements",
                            "n_disagreements",
                            "agreement_percent",
                            "n_missing_a_only",
                            "n_missing_b_only",
                            "n_missing_both",
                        )
                    },
                },
            ]
        )
    _write_csv(output_dir / "os_source_reconciliation.csv", os_rows)
    _write_csv(output_dir / "gdc_vs_supplement_discordance.csv", gdc_vs_supp_rows)
    if os_detail_rows:
        _write_csv(detail_dir / "os_discordance_examples.csv", os_detail_rows)

    unmatched_detail = []
    for barcode in sorted(gdc_ids - all_supp):
        unmatched_detail.append({"universe": "gdc_only", "join_barcode": barcode})
    for barcode in sorted(all_supp - gdc_ids):
        unmatched_detail.append(
            {"universe": "supplement_only", "join_barcode": barcode}
        )
    if unmatched_detail:
        _write_csv(detail_dir / "unmatched_identifiers.csv", unmatched_detail)

    discordance_rows: list[dict[str, Any]] = []
    workbooks = sorted(supp_rows_by_file)
    for i, left_name in enumerate(workbooks):
        for right_name in workbooks[i + 1 :]:
            shared = set(supp_rows_by_file[left_name]) & set(
                supp_rows_by_file[right_name]
            )
            comparisons: dict[str, tuple[str, str]] = {
                **{
                    concept: ("staging", column)
                    for concept, column in CATEGORICAL_CONCEPTS.items()
                },
                **{
                    concept: ("staging", column)
                    for concept, column in NUMERIC_CONCEPTS.items()
                },
                **{
                    f"cytogenetics:{column}": ("cells", column)
                    for column in CYTOGENETIC_COLUMNS
                },
            }
            for concept, (origin, column) in comparisons.items():
                pairs = []
                for barcode in shared:
                    left_row = supp_rows_by_file[left_name][barcode]
                    right_row = supp_rows_by_file[right_name][barcode]
                    if origin == "cells":
                        left_val = _cells(left_row).get(column)
                        right_val = _cells(right_row).get(column)
                    else:
                        left_val = left_row.get(column)
                        right_val = right_row.get(column)
                    pairs.append((left_val, right_val))
                numeric = origin == "staging" and concept in NUMERIC_CONCEPTS
                if numeric:
                    stats = numeric_discordance(pairs)
                    discordance_rows.append(
                        {
                            "file_a": left_name,
                            "file_b": right_name,
                            "concept": concept,
                            "value_kind": "numeric",
                            "n_shared_patients": len(shared),
                            "n_both_observed": stats["n_both_observed"],
                            "n_agreements": stats["n_exact_agreements"],
                            "n_disagreements": stats["n_disagreements"],
                            "agreement_percent": stats["agreement_percent"],
                            "n_missing_a_only": stats["n_missing_a_only"],
                            "n_missing_b_only": stats["n_missing_b_only"],
                            "n_missing_both": stats["n_missing_both"],
                            "diff_min": stats["diff_min"],
                            "diff_max": stats["diff_max"],
                            "abs_diff_median": stats["abs_diff_median"],
                        }
                    )
                else:
                    stats = categorical_agreement(pairs)
                    discordance_rows.append(
                        {
                            "file_a": left_name,
                            "file_b": right_name,
                            "concept": concept,
                            "value_kind": "categorical",
                            "n_shared_patients": len(shared),
                            "n_both_observed": stats["n_both_observed"],
                            "n_agreements": stats["n_agreements"],
                            "n_disagreements": stats["n_disagreements"],
                            "agreement_percent": stats["agreement_percent"],
                            "n_missing_a_only": stats["n_missing_a_only"],
                            "n_missing_b_only": stats["n_missing_b_only"],
                            "n_missing_both": stats["n_missing_both"],
                            "diff_min": None,
                            "diff_max": None,
                            "abs_diff_median": None,
                        }
                    )
    _write_csv(output_dir / "supplement_discordance_summary.csv", discordance_rows)

    ages = summarize_age_days(
        [row["age_at_diagnosis_days"] for row in data["diagnoses"]]
    )
    _write_json(output_dir / "age_distribution.json", ages)

    missing_tokens: Counter[tuple[str, str, str, str]] = Counter()
    for row in data["supplements"]:
        workbook = row["workbook_name"]
        for column, value in _cells(row).items():
            missing_class = classify_missing(value)
            if missing_class == "observed":
                continue
            token = "" if value is None else str(value).strip()
            missing_tokens[(workbook, column, token, missing_class)] += 1
    missing_token_rows = [
        {
            "workbook": workbook,
            "column": column,
            "token": token,
            "missing_class": missing_class,
            "n": count,
        }
        for (workbook, column, token, missing_class), count in sorted(
            missing_tokens.items()
        )
        if count >= 5
    ]
    _write_csv(output_dir / "missing_value_token_inventory.csv", missing_token_rows)
    missing_notes = {
        "policy": (
            "structurally_missing vs not_reported vs unknown vs not_applicable "
            "vs sentinel vs observed. NA/N/A classified as unknown because "
            "spreadsheet N/A is ambiguous. Unknown vital status is not censored."
        ),
        "token_inventory": "missing_value_token_inventory.csv",
        "note": (
            "Inventory is aggregated; tokens with fewer than 5 occurrences omitted."
        ),
    }
    _write_json(output_dir / "missing_value_policy.json", missing_notes)

    follow_up_counts = Counter(row["case_id"] for row in data["follow_ups"])
    treatment_counts = Counter(row["case_id"] for row in data["treatments"])
    entity_counts = {
        "raw": data["raw_counts"],
        "staging": {
            "gdc_cases": len(data["gdc_cases"]),
            "gdc_demographics": len(data["demographics"]),
            "gdc_diagnoses": len(data["diagnoses"]),
            "gdc_follow_ups": len(data["follow_ups"]),
            "gdc_treatments": len(data["treatments"]),
            "supplement_clinical_rows": len(data["supplements"]),
        },
        "follow_ups_per_case_max": max(follow_up_counts.values(), default=0),
        "treatments_per_case_max": max(treatment_counts.values(), default=0),
        "n_cases_with_multiple_follow_ups": sum(
            count > 1 for count in follow_up_counts.values()
        ),
        "n_cases_with_multiple_treatments": sum(
            count > 1 for count in treatment_counts.values()
        ),
    }
    _write_json(output_dir / "entity_counts.json", entity_counts)

    return {
        "identifier_overlap": id_overlap_out,
        "entity_counts": entity_counts,
        "age": ages,
        "os_rows": os_rows,
        "discordance_rows": discordance_rows,
        "gdc_id_summary": gdc_id_summary,
        "supp_id_summary": supp_id_summary,
        "sheet_summary": sheet_summary,
        "overlap_distribution": dist_rows,
        "pairwise_overlap": pair_rows,
    }
