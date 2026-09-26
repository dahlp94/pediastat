"""Build the analysis-person cohort and overall-survival endpoint."""

from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path
from statistics import median
from typing import Any

from sqlalchemy import MetaData, Table, text
from sqlalchemy.engine import Engine

from pediastat.cohort.baseline import (
    NOT_RECOMMENDED,
    availability_rows,
    reconcile_person_baselines,
    workbook_family,
)
from pediastat.cohort.eligibility import evaluate_person, sequential_attrition
from pediastat.cohort.endpoint import EVENT_SOURCE
from pediastat.cohort.gdc_definitions import verify_time_origin
from pediastat.cohort.identity import build_identity_crosswalk, summarize_identity
from pediastat.config import PROJECT_ROOT
from pediastat.database.engine import apply_sql_file
from pediastat.reconciliation.discordance import (
    categorical_agreement,
    numeric_discordance,
)

DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "cohort_definition"
DETAIL_DIR = PROJECT_ROOT / "data" / "interim" / "cohort_definition"
SQL_ANALYTICS = PROJECT_ROOT / "sql" / "07_create_analytics_tables.sql"


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
        json.dumps(payload, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )


def _cells(row: dict[str, Any]) -> dict[str, Any]:
    value = row.get("cells")
    if isinstance(value, dict):
        return value
    return json.loads(value) if isinstance(value, str) else {}


def _fetch_staging(engine: Engine) -> dict[str, list[dict[str, Any]]]:
    queries = {
        "cases": "SELECT * FROM staging.gdc_cases",
        "demographics": "SELECT * FROM staging.gdc_demographics",
        "diagnoses": "SELECT * FROM staging.gdc_diagnoses",
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


def _joined_cases(data: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    demo = {
        row["case_id"]: row
        for row in data["demographics"]
        if row.get("case_id")
    }
    dx = {
        row["case_id"]: row
        for row in data["diagnoses"]
        if row.get("case_id")
    }
    out = []
    for case in data["cases"]:
        case_id = case["case_id"]
        demographic = demo.get(case_id, {})
        diagnosis = dx.get(case_id, {})
        out.append(
            {
                "case_id": case_id,
                "submitter_id": case.get("submitter_id"),
                "join_barcode": case.get("join_barcode"),
                "index_date": case.get("index_date"),
                "vital_status": demographic.get("vital_status_raw"),
                "days_to_death": demographic.get("days_to_death"),
                "sex_at_birth": demographic.get("sex_at_birth_raw"),
                "race": demographic.get("race_raw"),
                "ethnicity": demographic.get("ethnicity_raw"),
                "age_at_diagnosis_days": diagnosis.get(
                    "age_at_diagnosis_days"
                ),
                "days_to_diagnosis": diagnosis.get("days_to_diagnosis"),
                "days_to_last_follow_up": diagnosis.get(
                    "days_to_last_follow_up"
                ),
                "has_demographic": case_id in demo,
                "has_diagnosis": case_id in dx,
            }
        )
    return out


def apply_analytics_ddl(engine: Engine) -> None:
    apply_sql_file(engine, SQL_ANALYTICS.read_text(encoding="utf-8"))


def _replace_analytics(
    engine: Engine,
    *,
    crosswalk: list[dict[str, Any]],
    eligibility: list[dict[str, Any]],
    cohort: list[dict[str, Any]],
    baseline: list[dict[str, Any]],
) -> None:
    payloads = {
        "patient_identity_crosswalk": crosswalk,
        "cohort_eligibility": eligibility,
        "primary_os_cohort": cohort,
        "baseline_covariates_reconciled": baseline,
    }
    delete_order = reversed(tuple(payloads))
    metadata = MetaData()

    with engine.begin() as connection:
        tables = {
            name: Table(
                name,
                metadata,
                schema="analytics",
                autoload_with=connection,
            )
            for name in payloads
        }
        for name in delete_order:
            connection.execute(tables[name].delete())
        for name, rows in payloads.items():
            if rows:
                columns = set(tables[name].c.keys())
                clean = [
                    {key: value for key, value in row.items() if key in columns}
                    for row in rows
                ]
                connection.execute(tables[name].insert(), clean)


def _build_people(
    data: dict[str, list[dict[str, Any]]],
    joined: list[dict[str, Any]],
) -> tuple[
    list[dict[str, Any]],
    dict[str, Any],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    by_case = {row["case_id"]: row for row in joined}
    crosswalk = build_identity_crosswalk(joined)
    identity_summary = summarize_identity(crosswalk)

    supplements: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in data["supplements"]:
        if barcode := row.get("join_barcode"):
            item = dict(row)
            item["cells"] = _cells(item)
            supplements[barcode].append(item)

    eligibility = []
    cohort = []
    baseline = []
    for identity in (
        row for row in crosswalk if row["is_representative_case"]
    ):
        person = identity["analysis_person_id"]
        clinical = by_case.get(identity["case_id"], {})
        evaluated = evaluate_person(
            identity=identity,
            clinical=clinical,
            has_diagnosis=bool(clinical.get("has_diagnosis")),
        )
        eligibility.append(evaluated)
        baseline.extend(
            reconcile_person_baselines(
                analysis_person_id=person,
                gdc={
                    "age_at_diagnosis_days": clinical.get(
                        "age_at_diagnosis_days"
                    ),
                    "sex_at_birth": clinical.get("sex_at_birth"),
                    "race": clinical.get("race"),
                    "ethnicity": clinical.get("ethnicity"),
                },
                supplement_rows=supplements.get(person, []),
            )
        )
        if evaluated["primary_cohort_eligible"]:
            cohort.append(
                {
                    "analysis_person_id": person,
                    "gdc_case_id": identity["case_id"],
                    "submitter_id": identity["submitter_id"],
                    "age_at_diagnosis_days": evaluated[
                        "age_at_diagnosis_days"
                    ],
                    "age_at_diagnosis_years": evaluated[
                        "age_at_diagnosis_years"
                    ],
                    "vital_status": evaluated["vital_status"],
                    "os_event": evaluated["os_event"],
                    "os_days": evaluated["os_days"],
                    "os_years": evaluated["os_years"],
                    "os_time_source": evaluated["os_time_source"],
                    "os_event_source": (
                        evaluated["os_event_source"] or EVENT_SOURCE
                    ),
                    "identity_rule": identity["identity_rule"],
                    "source_provenance": "gdc_cases_api",
                    "qa_flags": {
                        "flags": evaluated["qa_flags"],
                        "n_gdc_cases_for_person": identity[
                            "n_gdc_cases_for_person"
                        ],
                    },
                }
            )
    return crosswalk, identity_summary, eligibility, cohort, baseline


def _attrition(
    joined: list[dict[str, Any]],
    identity: dict[str, Any],
    eligibility: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    n_cases = len(joined)
    n_valid = identity["n_gdc_cases_valid_identity"]
    n_people = identity["n_valid_analysis_persons"]
    rows = [
        {
            "criterion": "all_gdc_cases",
            "unit": "gdc_case",
            "n_before": n_cases,
            "n_excluded": 0,
            "n_remaining": n_cases,
            "notes": "TARGET-AML Cases API extract.",
        },
        {
            "criterion": "valid_analysis_person_identity",
            "unit": "gdc_case",
            "n_before": n_cases,
            "n_excluded": n_cases - n_valid,
            "n_remaining": n_valid,
            "notes": (
                "Canonical TARGET-20/21 6-character USI or "
                "biospecimen-suffix extension mapped to that USI."
            ),
        },
        {
            "criterion": "unique_valid_analysis_persons",
            "unit": "analysis_person",
            "n_before": n_valid,
            "n_excluded": 0,
            "n_remaining": n_people,
            "notes": (
                f"{n_valid} GDC cases map to {n_people} persons; "
                "extra cases are biospecimen-suffix duplicates, "
                "not exclusions."
            ),
        },
    ]
    rows.extend(sequential_attrition(eligibility)[2:])
    return rows


def _endpoint_summary(
    cohort: list[dict[str, Any]],
    origin: dict[str, Any],
) -> dict[str, Any]:
    times = [float(row["os_days"]) for row in cohort]
    deaths = sum(row["os_event"] == 1 for row in cohort)
    return {
        "primary_cohort_n": len(cohort),
        "deaths": deaths,
        "censored": len(cohort) - deaths,
        "event_percent": (
            round(deaths / len(cohort) * 100.0, 2) if cohort else None
        ),
        "os_days_min": min(times) if times else None,
        "os_days_median": median(times) if times else None,
        "os_days_max": max(times) if times else None,
        "n_zero_os_times": sum(day == 0 for day in times),
        "n_negative_os_times": sum(day < 0 for day in times),
        "n_missing_os_times": sum(row["os_days"] is None for row in cohort),
        "n_using_days_to_death": sum(
            row["os_time_source"].endswith("days_to_death") for row in cohort
        ),
        "n_using_days_to_last_follow_up": sum(
            row["os_time_source"].endswith("days_to_last_follow_up")
            for row in cohort
        ),
        "n_index_date_missing_qa_flag": sum(
            "index_date_missing" in row["qa_flags"]["flags"]
            for row in cohort
        ),
        "time_origin": origin["conclusion"],
        "note": (
            "No Kaplan-Meier estimate, log-rank test, or "
            "covariate-stratified survival summary was computed."
        ),
    }


def _supplement_os_qa(
    cohort: list[dict[str, Any]],
    supplements: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    primary = {row["analysis_person_id"]: row for row in cohort}
    grouped: dict[str, list[tuple[Any, Any, Any, Any]]] = defaultdict(list)

    for row in supplements:
        person = row.get("join_barcode")
        family = workbook_family(row.get("workbook_name"))
        if person in primary and family:
            gdc = primary[person]
            grouped[family].append(
                (
                    gdc["vital_status"],
                    row.get("vital_status_raw"),
                    gdc["os_days"],
                    row.get("os_time_days"),
                )
            )

    out = []
    for family, pairs in sorted(grouped.items()):
        status = categorical_agreement(
            [(a, b) for a, b, _, _ in pairs]
        )
        times = numeric_discordance(
            [(a, b) for _, _, a, b in pairs]
        )
        out.append(
            {
                "supplement_family": family,
                "overlap_n": len(pairs),
                "event_both_observed": status["n_both_observed"],
                "event_agreements": status["n_agreements"],
                "event_disagreements": status["n_disagreements"],
                "event_agreement_percent": status["agreement_percent"],
                "time_both_observed": times["n_both_observed"],
                "time_exact_agreements": times["n_exact_agreements"],
                "time_disagreements": times["n_disagreements"],
                "time_agreement_percent": times["agreement_percent"],
                "time_abs_diff_median": times["abs_diff_median"],
            }
        )
    return out


def _validate(
    engine: Engine,
    crosswalk: list[dict[str, Any]],
    eligibility: list[dict[str, Any]],
    cohort: list[dict[str, Any]],
    baseline: list[dict[str, Any]],
) -> dict[str, Any]:
    primary_ids = {row["analysis_person_id"] for row in cohort}
    unique_people = len(primary_ids)
    invalid_event = sum(
        row["vital_status"] not in {"Alive", "Dead"}
        or row["os_event"] not in {0, 1}
        for row in cohort
    )
    dead_bad = sum(
        row["os_event"] == 1
        and (
            row["os_time_source"] != "gdc.demographic.days_to_death"
            or row["os_days"] is None
            or row["os_days"] < 0
        )
        for row in cohort
    )
    alive_bad = sum(
        row["os_event"] == 0
        and (
            row["os_time_source"]
            != "gdc.diagnoses.days_to_last_follow_up"
            or row["os_days"] is None
            or row["os_days"] < 0
        )
        for row in cohort
    )
    excluded_without_reason = sum(
        not row["primary_cohort_eligible"]
        and not row["primary_exclusion_reason"]
        for row in eligibility
    )
    primary_with_reason = sum(
        row["primary_cohort_eligible"]
        and row["primary_exclusion_reason"] is not None
        for row in eligibility
    )
    missing_wbc = sum(
        row["analysis_person_id"] in primary_ids
        and row["concept"] == "wbc_at_diagnosis"
        and row["missingness_class"] != "observed"
        for row in baseline
    )
    with engine.connect() as connection:
        counts = connection.execute(
            text(
                """
                SELECT
                    (SELECT COUNT(*) FROM
                     analytics.patient_identity_crosswalk) AS crosswalk,
                    (SELECT COUNT(*) FROM
                     analytics.cohort_eligibility) AS eligibility,
                    (SELECT COUNT(*) FROM
                     analytics.primary_os_cohort) AS cohort
                """
            )
        ).mappings().one()

    negative_os = sum(row["os_days"] < 0 for row in cohort)
    adults = sum(row["age_at_diagnosis_years"] >= 18 for row in cohort)
    passed = all(
        (
            counts["crosswalk"] == len(crosswalk),
            counts["eligibility"] == len(eligibility),
            counts["cohort"] == len(cohort) == unique_people,
            invalid_event == dead_bad == alive_bad == 0,
            negative_os == adults == 0,
            excluded_without_reason == primary_with_reason == 0,
        )
    )
    return {
        "n_identity_crosswalk_rows": counts["crosswalk"],
        "n_eligibility_rows": counts["eligibility"],
        "n_primary_os_cohort": counts["cohort"],
        "n_unique_persons_in_cohort": unique_people,
        "n_unknown_or_invalid_event": invalid_event,
        "n_dead_invalid_time": dead_bad,
        "n_alive_invalid_time": alive_bad,
        "n_negative_os": negative_os,
        "n_age_ge_18_in_primary": adults,
        "n_excluded_missing_reason": excluded_without_reason,
        "n_primary_with_unobserved_wbc": missing_wbc,
        "passed": passed,
    }


def _write_artifacts(
    output_dir: Path,
    detail_dir: Path,
    payloads: dict[str, Any],
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    detail_dir.mkdir(parents=True, exist_ok=True)
    for filename, payload in payloads.items():
        _write(output_dir / filename, payload)


def build_primary_cohort(
    engine: Engine,
    output_dir: Path = DEFAULT_OUTPUT,
    detail_dir: Path = DETAIL_DIR,
) -> dict[str, Any]:
    """Build, validate, persist, and summarize the primary OS cohort."""
    apply_analytics_ddl(engine)
    data = _fetch_staging(engine)
    joined = _joined_cases(data)

    origin = verify_time_origin(joined)
    if not origin["proceed_with_endpoint"]:
        raise RuntimeError(
            "Official GDC OS time fields do not share a coherent origin "
            "in this extract; the primary endpoint was not created."
        )

    crosswalk, identity, eligibility, cohort, baseline = _build_people(
        data, joined
    )
    attrition = _attrition(joined, identity, eligibility)
    endpoint = _endpoint_summary(cohort, origin)
    sensitivity = {
        "primary_age_lt_18": sum(
            row["primary_cohort_eligible"] for row in eligibility
        ),
        "sensitivity_age_le_21": sum(
            row["sensitivity_le21_eligible"] for row in eligibility
        ),
        "sensitivity_unrestricted_age": sum(
            row["sensitivity_unrestricted_age_eligible"]
            for row in eligibility
        ),
        "note": "Eligibility flags only. No survival comparison was performed.",
    }
    availability = availability_rows(
        primary_person_ids=[row["analysis_person_id"] for row in cohort],
        baseline_rows=baseline,
    )
    os_qa = _supplement_os_qa(cohort, data["supplements"])

    _replace_analytics(
        engine,
        crosswalk=crosswalk,
        eligibility=eligibility,
        cohort=cohort,
        baseline=baseline,
    )
    validation = _validate(
        engine, crosswalk, eligibility, cohort, baseline
    )
    viability = {
        "core_candidate": [
            row["concept"]
            for row in availability
            if row["viability"] == "CORE CANDIDATE"
        ],
        "secondary_candidate": [
            row["concept"]
            for row in availability
            if row["viability"] == "SECONDARY CANDIDATE"
        ],
        "not_recommended": [item["concept"] for item in NOT_RECOMMENDED],
        "needs_review": [
            row["concept"]
            for row in availability
            if row["viability"] == "NEEDS REVIEW"
        ],
        "note": (
            "Viability is scientific/source-quality classification, "
            "not outcome-driven variable selection."
        ),
    }
    _write_artifacts(
        output_dir,
        detail_dir,
        {
            "cohort_attrition.csv": attrition,
            "cohort_attrition.json": attrition,
            "endpoint_summary.json": endpoint,
            "identity_resolution_summary.json": identity,
            "sensitivity_population_counts.json": sensitivity,
            "time_origin_verification.json": origin,
            "baseline_covariate_availability.csv": availability,
            "supplement_os_qa_summary.csv": os_qa,
            "variable_viability.json": viability,
            "database_validation.json": validation,
        },
    )
    return {
        "identity_summary": identity,
        "attrition": attrition,
        "endpoint_summary": endpoint,
        "sensitivity": sensitivity,
        "os_qa": os_qa,
        "availability": availability,
        "time_origin": origin,
        "database_validation": validation,
        "n_baseline_rows": len(baseline),
        "n_eligibility_rows": len(eligibility),
    }
