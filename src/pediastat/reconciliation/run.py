"""Reconcile overlapping TARGET-AML clinical sources."""

from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.engine import Engine

from pediastat.config import PROJECT_ROOT
from pediastat.ingestion.identifiers import summarize_identifiers
from pediastat.reconciliation.age import summarize_age_days
from pediastat.reconciliation.concepts import CYTOGENETIC_COLUMNS
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

NUMERIC_SUPPLEMENT_FIELDS = {
    "wbc": "wbc_raw",
    "marrow_blasts": "marrow_blasts_raw",
    "peripheral_blasts": "peripheral_blasts_raw",
}
CATEGORICAL_SUPPLEMENT_FIELDS = {
    "risk_group": "risk_group_raw",
    "flt3_itd": "flt3_itd_raw",
    "npm": "npm_raw",
    "cebpa": "cebpa_raw",
    "fab": "fab_raw",
    "cns_disease": "cns_disease_raw",
}

_OBSOLETE_ARTIFACTS = (
    "age_distribution.json",
    "clinical_concept_source_map.csv",
    "entity_counts.json",
    "missing_value_policy.json",
    "missing_value_token_inventory.csv",
    "supplement_identifier_quality.csv",
    "supplement_overlap_distribution.csv",
    "supplement_overlap_matrix.csv",
    "supplement_sheet_summary.csv",
    "unmatched_identifier_summary.csv",
)


def _write(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".csv":
        rows = payload
        if not rows:
            path.write_text("", encoding="utf-8")
            return
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _cells(row: dict[str, Any]) -> dict[str, Any]:
    value = row.get("cells")
    if isinstance(value, dict):
        return value
    return json.loads(value) if isinstance(value, str) else {}


def _fetch(engine: Engine) -> dict[str, list[dict[str, Any]]]:
    queries = {
        "cases": """
            SELECT case_id, submitter_id, join_barcode
            FROM staging.gdc_cases
        """,
        "demographics": "SELECT * FROM staging.gdc_demographics",
        "diagnoses": "SELECT * FROM staging.gdc_diagnoses",
        "follow_ups": "SELECT * FROM staging.gdc_follow_ups",
        "supplements": """
            SELECT * FROM staging.supplement_clinical_rows
            WHERE sheet_name IN ('Clinical Data', 'Sheet1')
        """,
    }
    with engine.connect() as connection:
        return {
            name: [
                dict(row)
                for row in connection.execute(text(sql)).mappings()
            ]
            for name, sql in queries.items()
        }


def _supplements_by_workbook(
    rows: list[dict[str, Any]],
) -> dict[str, dict[str, dict[str, Any]]]:
    out: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    for row in rows:
        if barcode := row.get("join_barcode"):
            out[row["workbook_name"]][barcode] = row
    return out


def _identifier_overlap(
    cases: list[dict[str, Any]],
    supplements: dict[str, dict[str, dict[str, Any]]],
) -> dict[str, Any]:
    gdc_ids = {row["join_barcode"] for row in cases if row["join_barcode"]}
    supplement_ids = set().union(
        *(set(rows) for rows in supplements.values())
    ) if supplements else set()
    stats = universe_overlap(gdc_ids, supplement_ids)
    return {
        "gdc_unique_join_barcodes": stats["n_left"],
        "supplement_unique_join_barcodes": stats["n_right"],
        "intersection": stats["n_intersection"],
        "gdc_only": stats["n_left_only"],
        "supplement_only": stats["n_right_only"],
        "pct_gdc_matched": stats["pct_left_matched"],
        "pct_supplement_matched": stats["pct_right_matched"],
        "normalization_rule": (
            "strip whitespace, uppercase; join_barcode is leading "
            "TARGET-NN-TOKEN"
        ),
    }


def _gdc_index(data: dict[str, list[dict[str, Any]]]) -> dict[str, dict[str, Any]]:
    demographics = {
        row["join_barcode"]: row
        for row in data["demographics"]
        if row["join_barcode"]
    }
    diagnoses = {
        row["join_barcode"]: row
        for row in data["diagnoses"]
        if row["join_barcode"]
    }
    last_contact: dict[str, list[float]] = defaultdict(list)
    for row in data["follow_ups"]:
        barcode = row["join_barcode"]
        value = row["days_to_follow_up"]
        if (
            barcode
            and value is not None
            and row["timepoint_category"] == "Last Contact"
        ):
            last_contact[barcode].append(float(value))

    out = {}
    for barcode, demographic in demographics.items():
        diagnosis = diagnoses.get(barcode, {})
        status = demographic["vital_status_analysis_class"]
        death = demographic["days_to_death"]
        follow = diagnosis.get("days_to_last_follow_up")
        os_days = None
        if status == "dead" and death is not None:
            os_days = float(death)
        elif status == "alive" and follow is not None:
            os_days = float(follow)

        out[barcode] = {
            "vital_status": demographic["vital_status_raw"],
            "os_days": os_days,
            "days_to_death": death,
            "days_to_last_follow_up": follow,
            "last_contact_days": (
                max(last_contact[barcode])
                if last_contact[barcode]
                else None
            ),
            "age_at_diagnosis_days": diagnosis.get(
                "age_at_diagnosis_days"
            ),
            "sex_at_birth": demographic["sex_at_birth_raw"],
        }
    return out


def _compact_stats(
    workbook: str,
    concept: str,
    stats: dict[str, Any],
    *,
    numeric: bool,
) -> dict[str, Any]:
    return {
        "workbook": workbook,
        "concept": concept,
        "n_both_observed": stats["n_both_observed"],
        "n_agreements": (
            stats["n_exact_agreements"] if numeric else stats["n_agreements"]
        ),
        "n_disagreements": stats["n_disagreements"],
        "agreement_percent": stats["agreement_percent"],
        "n_missing_a_only": stats["n_missing_a_only"],
        "n_missing_b_only": stats["n_missing_b_only"],
        "n_missing_both": stats["n_missing_both"],
    }


def _gdc_vs_supplement(
    data: dict[str, list[dict[str, Any]]],
    supplements: dict[str, dict[str, dict[str, Any]]],
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    gdc = _gdc_index(data)
    os_rows = []
    summary_rows = []
    detail_rows = []

    for workbook, records in supplements.items():
        shared = set(records) & set(gdc)
        status_pairs = []
        time_pairs = []
        contact_pairs = []
        age_pairs = []
        sex_pairs = []

        for barcode in shared:
            left = gdc[barcode]
            right = records[barcode]
            status_pair = (left["vital_status"], right.get("vital_status_raw"))
            time_pair = (left["os_days"], right.get("os_time_days"))
            status_pairs.append(status_pair)
            time_pairs.append(time_pair)
            contact_pairs.append(
                (left["last_contact_days"], right.get("os_time_days"))
            )
            age_pairs.append(
                (
                    left["age_at_diagnosis_days"],
                    right.get("age_at_diagnosis_days"),
                )
            )
            sex_pairs.append((left["sex_at_birth"], right.get("sex_raw")))

            status_one = categorical_agreement([status_pair])
            time_one = numeric_discordance([time_pair])
            if status_one["n_disagreements"] or time_one["n_disagreements"]:
                detail_rows.append(
                    {
                        "join_barcode": barcode,
                        "workbook": workbook,
                        "gdc_vital_status": left["vital_status"],
                        "supplement_vital_status": right.get(
                            "vital_status_raw"
                        ),
                        "gdc_candidate_os_days": left["os_days"],
                        "gdc_days_to_death": left["days_to_death"],
                        "gdc_days_to_last_follow_up": left[
                            "days_to_last_follow_up"
                        ],
                        "gdc_last_contact_days": left["last_contact_days"],
                        "supplement_os_time_days": right.get("os_time_days"),
                    }
                )

        status = categorical_agreement(status_pairs)
        times = numeric_discordance(time_pairs)
        contact = numeric_discordance(contact_pairs)
        ages = numeric_discordance(age_pairs)
        sex = categorical_agreement(sex_pairs)

        patterns = Counter(
            f"{str(left).strip().lower()}|{str(right).strip().lower()}"
            for left, right in status_pairs
        )
        supplement_times = [
            records[barcode].get("os_time_days") for barcode in shared
        ]
        gdc_times = [gdc[barcode]["os_days"] for barcode in shared]

        os_rows.append(
            {
                "comparison": f"gdc_vs_{workbook}",
                "n_shared_patients": len(shared),
                "vital_status_both_observed": status["n_both_observed"],
                "vital_status_agreements": status["n_agreements"],
                "vital_status_disagreements": status["n_disagreements"],
                "vital_status_agreement_percent": status[
                    "agreement_percent"
                ],
                "vital_status_pair_patterns": json.dumps(
                    dict(patterns),
                    sort_keys=True,
                ),
                "os_time_both_observed": times["n_both_observed"],
                "os_time_exact_agreements": times["n_exact_agreements"],
                "os_time_within_one_day": times["n_within_one"],
                "os_time_agreement_percent": times["agreement_percent"],
                "os_time_diff_min": times["diff_min"],
                "os_time_diff_max": times["diff_max"],
                "os_time_abs_diff_median": times["abs_diff_median"],
                "last_contact_vs_os_exact": contact["n_exact_agreements"],
                "last_contact_vs_os_both_observed": contact[
                    "n_both_observed"
                ],
                "last_contact_vs_os_agreement_percent": contact[
                    "agreement_percent"
                ],
                "age_exact_agreements": ages["n_exact_agreements"],
                "age_both_observed": ages["n_both_observed"],
                "age_agreement_percent": ages["agreement_percent"],
                "sex_agreement_percent": sex["agreement_percent"],
                "sex_disagreements": sex["n_disagreements"],
                "supplement_zero_os_times_in_overlap": sum(
                    value == 0 for value in supplement_times
                ),
                "supplement_negative_os_times_in_overlap": sum(
                    value is not None and value < 0
                    for value in supplement_times
                ),
                "gdc_zero_candidate_os_in_overlap": sum(
                    value == 0 for value in gdc_times
                ),
                "gdc_negative_candidate_os_in_overlap": sum(
                    value is not None and value < 0 for value in gdc_times
                ),
            }
        )
        summary_rows.extend(
            (
                _compact_stats(
                    workbook,
                    "vital_status",
                    status,
                    numeric=False,
                ),
                _compact_stats(
                    workbook,
                    "os_time_gdc_candidate_vs_supplement",
                    times,
                    numeric=True,
                ),
                _compact_stats(
                    workbook,
                    "age_at_diagnosis",
                    ages,
                    numeric=True,
                ),
                _compact_stats(
                    workbook,
                    "sex_gdc_sex_at_birth_vs_supplement_gender",
                    sex,
                    numeric=False,
                ),
            )
        )
    return os_rows, summary_rows, detail_rows


def _supplement_discordance(
    supplements: dict[str, dict[str, dict[str, Any]]],
) -> list[dict[str, Any]]:
    comparisons = [
        *(
            (name, "staging", column, True)
            for name, column in NUMERIC_SUPPLEMENT_FIELDS.items()
        ),
        *(
            (name, "staging", column, False)
            for name, column in CATEGORICAL_SUPPLEMENT_FIELDS.items()
        ),
        *(
            (f"cytogenetics:{column}", "cells", column, False)
            for column in CYTOGENETIC_COLUMNS
        ),
    ]
    rows = []
    workbooks = sorted(supplements)

    for index, left_name in enumerate(workbooks):
        for right_name in workbooks[index + 1 :]:
            shared = set(supplements[left_name]) & set(
                supplements[right_name]
            )
            for concept, origin, column, numeric in comparisons:
                pairs = []
                for barcode in shared:
                    left = supplements[left_name][barcode]
                    right = supplements[right_name][barcode]
                    if origin == "cells":
                        pairs.append(
                            (
                                _cells(left).get(column),
                                _cells(right).get(column),
                            )
                        )
                    else:
                        pairs.append((left.get(column), right.get(column)))

                stats = (
                    numeric_discordance(pairs)
                    if numeric
                    else categorical_agreement(pairs)
                )
                rows.append(
                    {
                        "file_a": left_name,
                        "file_b": right_name,
                        "concept": concept,
                        "value_kind": (
                            "numeric" if numeric else "categorical"
                        ),
                        "n_shared_patients": len(shared),
                        "n_both_observed": stats["n_both_observed"],
                        "n_agreements": (
                            stats["n_exact_agreements"]
                            if numeric
                            else stats["n_agreements"]
                        ),
                        "n_disagreements": stats["n_disagreements"],
                        "agreement_percent": stats["agreement_percent"],
                        "n_missing_a_only": stats["n_missing_a_only"],
                        "n_missing_b_only": stats["n_missing_b_only"],
                        "n_missing_both": stats["n_missing_both"],
                        "diff_min": stats["diff_min"] if numeric else None,
                        "diff_max": stats["diff_max"] if numeric else None,
                        "abs_diff_median": (
                            stats["abs_diff_median"] if numeric else None
                        ),
                    }
                )
    return rows


def _source_decisions() -> dict[str, Any]:
    return {
        "overall_survival": {
            "source": "GDC",
            "event": "demographic.vital_status",
            "time": (
                "days_to_death for deaths; diagnoses.days_to_last_follow_up "
                "for survivors"
            ),
            "reason": (
                "Overlapping supplement OS fields are retained for QA but "
                "are not treated as the primary endpoint source."
            ),
        },
        "age_at_diagnosis": {
            "source": "GDC diagnoses.age_at_diagnosis",
            "reason": "Used for cohort eligibility and baseline age.",
        },
        "sex": {
            "source": "GDC demographic.sex_at_birth",
            "reason": "The supplement Gender field is not substituted.",
        },
        "aml_specific_baselines": {
            "source": "TARGET clinical supplements",
            "reason": (
                "WBC, protocol risk, molecular markers, morphology, and "
                "cytogenetic fields are primarily available in supplements."
            ),
            "precedence_note": (
                "Per-variable workbook precedence is locked in "
                "cohort/baseline.py and is not outcome-driven."
            ),
        },
    }


def _compatibility_summaries(
    data: dict[str, list[dict[str, Any]]],
    supplements: dict[str, dict[str, dict[str, Any]]],
) -> dict[str, Any]:
    supplement_sets = {
        workbook: set(rows) for workbook, rows in supplements.items()
    }
    gdc_summary = summarize_identifiers(
        [row["submitter_id"] for row in data["cases"]]
    )
    supplement_summary = summarize_identifiers(
        [row["original_identifier"] for row in data["supplements"]]
    )
    return {
        "entity_counts": {},
        "age": summarize_age_days(
            [row["age_at_diagnosis_days"] for row in data["diagnoses"]]
        ),
        "gdc_id_summary": gdc_summary,
        "supp_id_summary": supplement_summary,
        "overlap_distribution": overlap_distribution(supplement_sets),
        "pairwise_overlap": pairwise_overlap_counts(supplement_sets),
    }


def _remove_obsolete(output_dir: Path) -> None:
    for filename in _OBSOLETE_ARTIFACTS:
        (output_dir / filename).unlink(missing_ok=True)


def run_reconciliation(
    engine: Engine,
    output_dir: Path = DEFAULT_OUTPUT,
    detail_dir: Path = DETAIL_DIR,
) -> dict[str, Any]:
    """Validate source linkage and concordance before cohort construction."""
    data = _fetch(engine)
    supplements = _supplements_by_workbook(data["supplements"])

    identifier_overlap = _identifier_overlap(data["cases"], supplements)
    os_rows, source_discordance, os_detail = _gdc_vs_supplement(
        data,
        supplements,
    )
    supplement_discordance = _supplement_discordance(supplements)
    decisions = _source_decisions()

    _remove_obsolete(output_dir)
    _write(output_dir / "source_identifier_overlap.json", identifier_overlap)
    _write(output_dir / "os_source_reconciliation.csv", os_rows)
    _write(
        output_dir / "gdc_vs_supplement_discordance.csv",
        source_discordance,
    )
    _write(
        output_dir / "supplement_discordance_summary.csv",
        supplement_discordance,
    )
    _write(output_dir / "source_decisions.json", decisions)
    if os_detail:
        _write(detail_dir / "os_discordance_examples.csv", os_detail)

    compatibility = _compatibility_summaries(data, supplements)
    return {
        "identifier_overlap": identifier_overlap,
        "entity_counts": compatibility["entity_counts"],
        "age": compatibility["age"],
        "os_rows": os_rows,
        "discordance_rows": supplement_discordance,
        "gdc_id_summary": compatibility["gdc_id_summary"],
        "supp_id_summary": compatibility["supp_id_summary"],
        "sheet_summary": [],
        "overlap_distribution": compatibility["overlap_distribution"],
        "pairwise_overlap": compatibility["pairwise_overlap"],
        "source_decisions": decisions,
    }
