"""Build the Stage 3 analysis-person cohort and OS endpoint from staging."""

from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from sqlalchemy import text
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
from pediastat.cohort.identity import (
    build_identity_crosswalk,
    summarize_identity,
)
from pediastat.config import PROJECT_ROOT
from pediastat.database.engine import apply_sql_file
from pediastat.reconciliation.discordance import (
    categorical_agreement,
    numeric_discordance,
)

DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "cohort_definition"
DETAIL_DIR = PROJECT_ROOT / "data" / "interim" / "cohort_definition"
SQL_ANALYTICS = PROJECT_ROOT / "sql" / "07_create_analytics_tables.sql"

ELIGIBILITY_COLUMNS = (
    "analysis_person_id",
    "representative_case_id",
    "submitter_id",
    "has_valid_identity",
    "has_diagnosis",
    "has_age",
    "age_eligible_lt18",
    "age_eligible_le21",
    "has_known_vital_status",
    "has_valid_os_time",
    "records_compatible",
    "identity_conflict",
    "primary_cohort_eligible",
    "sensitivity_le21_eligible",
    "sensitivity_unrestricted_age_eligible",
    "primary_exclusion_reason",
    "all_exclusion_flags",
    "age_at_diagnosis_days",
    "age_at_diagnosis_years",
    "vital_status",
    "os_event",
    "os_days",
)


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
        json.dumps(payload, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )


def _cells(row: dict[str, Any]) -> dict[str, Any]:
    value = row.get("cells")
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return {}


def _median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return float(ordered[mid])
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def _fetch_staging(engine: Engine) -> dict[str, Any]:
    with engine.connect() as connection:
        cases = list(
            connection.execute(text("SELECT * FROM staging.gdc_cases")).mappings()
        )
        demographics = list(
            connection.execute(
                text("SELECT * FROM staging.gdc_demographics")
            ).mappings()
        )
        diagnoses = list(
            connection.execute(text("SELECT * FROM staging.gdc_diagnoses")).mappings()
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
    return {
        "cases": [dict(row) for row in cases],
        "demographics": [dict(row) for row in demographics],
        "diagnoses": [dict(row) for row in diagnoses],
        "supplements": [dict(row) for row in supplements],
    }


def _index_by_case(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {row["case_id"]: row for row in rows if row.get("case_id")}


def _joined_cases(data: dict[str, Any]) -> list[dict[str, Any]]:
    demo = _index_by_case(data["demographics"])
    dx = _index_by_case(data["diagnoses"])
    joined: list[dict[str, Any]] = []
    for case in data["cases"]:
        case_id = case["case_id"]
        demographic = demo.get(case_id, {})
        diagnosis = dx.get(case_id, {})
        joined.append(
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
                "age_at_diagnosis_days": diagnosis.get("age_at_diagnosis_days"),
                "days_to_diagnosis": diagnosis.get("days_to_diagnosis"),
                "days_to_last_follow_up": diagnosis.get("days_to_last_follow_up"),
                "has_demographic": case_id in demo,
                "has_diagnosis": case_id in dx,
            }
        )
    return joined


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
    with engine.begin() as connection:
        for table in (
            "analytics.baseline_covariates_reconciled",
            "analytics.primary_os_cohort",
            "analytics.cohort_eligibility",
            "analytics.patient_identity_crosswalk",
        ):
            connection.execute(text(f"DELETE FROM {table}"))
        for row in crosswalk:
            connection.execute(
                text(
                    """
                    INSERT INTO analytics.patient_identity_crosswalk (
                        case_id, submitter_id, original_identifier,
                        normalized_identifier, join_barcode, analysis_person_id,
                        identity_rule, identity_confidence,
                        eligible_for_person_level_analysis, exclusion_reason,
                        n_gdc_cases_for_person, is_representative_case
                    ) VALUES (
                        :case_id, :submitter_id, :original_identifier,
                        :normalized_identifier, :join_barcode, :analysis_person_id,
                        :identity_rule, :identity_confidence,
                        :eligible_for_person_level_analysis, :exclusion_reason,
                        :n_gdc_cases_for_person, :is_representative_case
                    )
                    """
                ),
                {
                    "case_id": row["case_id"],
                    "submitter_id": row["submitter_id"],
                    "original_identifier": row["original_identifier"],
                    "normalized_identifier": row["normalized_identifier"],
                    "join_barcode": row["join_barcode"],
                    "analysis_person_id": row["analysis_person_id"],
                    "identity_rule": row["identity_rule"],
                    "identity_confidence": row["identity_confidence"],
                    "eligible_for_person_level_analysis": row[
                        "eligible_for_person_level_analysis"
                    ],
                    "exclusion_reason": row["exclusion_reason"],
                    "n_gdc_cases_for_person": row["n_gdc_cases_for_person"],
                    "is_representative_case": row["is_representative_case"],
                },
            )
        for row in eligibility:
            payload = {key: row[key] for key in ELIGIBILITY_COLUMNS}
            payload["all_exclusion_flags"] = json.dumps(row["all_exclusion_flags"])
            connection.execute(
                text(
                    """
                    INSERT INTO analytics.cohort_eligibility (
                        analysis_person_id, representative_case_id, submitter_id,
                        has_valid_identity, has_diagnosis, has_age,
                        age_eligible_lt18, age_eligible_le21,
                        has_known_vital_status, has_valid_os_time,
                        records_compatible, identity_conflict,
                        primary_cohort_eligible, sensitivity_le21_eligible,
                        sensitivity_unrestricted_age_eligible,
                        primary_exclusion_reason, all_exclusion_flags,
                        age_at_diagnosis_days, age_at_diagnosis_years,
                        vital_status, os_event, os_days
                    ) VALUES (
                        :analysis_person_id, :representative_case_id, :submitter_id,
                        :has_valid_identity, :has_diagnosis, :has_age,
                        :age_eligible_lt18, :age_eligible_le21,
                        :has_known_vital_status, :has_valid_os_time,
                        :records_compatible, :identity_conflict,
                        :primary_cohort_eligible, :sensitivity_le21_eligible,
                        :sensitivity_unrestricted_age_eligible,
                        :primary_exclusion_reason,
                        CAST(:all_exclusion_flags AS JSONB),
                        :age_at_diagnosis_days, :age_at_diagnosis_years,
                        :vital_status, :os_event, :os_days
                    )
                    """
                ),
                payload,
            )
        for row in cohort:
            connection.execute(
                text(
                    """
                    INSERT INTO analytics.primary_os_cohort (
                        analysis_person_id, gdc_case_id, submitter_id,
                        age_at_diagnosis_days, age_at_diagnosis_years,
                        vital_status, os_event, os_days, os_years,
                        os_time_source, os_event_source, identity_rule,
                        source_provenance, qa_flags
                    ) VALUES (
                        :analysis_person_id, :gdc_case_id, :submitter_id,
                        :age_at_diagnosis_days, :age_at_diagnosis_years,
                        :vital_status, :os_event, :os_days, :os_years,
                        :os_time_source, :os_event_source, :identity_rule,
                        :source_provenance, CAST(:qa_flags AS JSONB)
                    )
                    """
                ),
                {
                    **row,
                    "qa_flags": json.dumps(row["qa_flags"]),
                },
            )
        for row in baseline:
            connection.execute(
                text(
                    """
                    INSERT INTO analytics.baseline_covariates_reconciled (
                        analysis_person_id, concept, value, source_workbook,
                        source_column, source_kind, conflict_flag,
                        alternative_source_count, missingness_class, units
                    ) VALUES (
                        :analysis_person_id, :concept, :value, :source_workbook,
                        :source_column, :source_kind, :conflict_flag,
                        :alternative_source_count, :missingness_class, :units
                    )
                    """
                ),
                row,
            )


def _validate_postgres(engine: Engine) -> dict[str, Any]:
    with engine.connect() as connection:
        n_crosswalk = connection.execute(
            text("SELECT COUNT(*) FROM analytics.patient_identity_crosswalk")
        ).scalar_one()
        n_eligibility = connection.execute(
            text("SELECT COUNT(*) FROM analytics.cohort_eligibility")
        ).scalar_one()
        n_cohort = connection.execute(
            text("SELECT COUNT(*) FROM analytics.primary_os_cohort")
        ).scalar_one()
        n_unique = connection.execute(
            text(
                """
                SELECT COUNT(DISTINCT analysis_person_id)
                FROM analytics.primary_os_cohort
                """
            )
        ).scalar_one()
        n_unknown = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.primary_os_cohort
                WHERE vital_status NOT IN ('Alive', 'Dead')
                   OR os_event NOT IN (0, 1)
                """
            )
        ).scalar_one()
        n_dead_bad = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.primary_os_cohort
                WHERE os_event = 1
                  AND (os_time_source <> 'gdc.demographic.days_to_death'
                       OR os_days IS NULL OR os_days < 0)
                """
            )
        ).scalar_one()
        n_alive_bad = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.primary_os_cohort
                WHERE os_event = 0
                  AND (os_time_source <>
                       'gdc.diagnoses.days_to_last_follow_up'
                       OR os_days IS NULL OR os_days < 0)
                """
            )
        ).scalar_one()
        n_neg = connection.execute(
            text(
                "SELECT COUNT(*) FROM analytics.primary_os_cohort WHERE os_days < 0"
            )
        ).scalar_one()
        n_adult = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.primary_os_cohort
                WHERE age_at_diagnosis_years >= 18
                """
            )
        ).scalar_one()
        n_excluded_no_reason = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.cohort_eligibility
                WHERE NOT primary_cohort_eligible
                  AND (primary_exclusion_reason IS NULL
                       OR primary_exclusion_reason = '')
                """
            )
        ).scalar_one()
        n_primary_with_reason = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM analytics.cohort_eligibility
                WHERE primary_cohort_eligible
                  AND primary_exclusion_reason IS NOT NULL
                """
            )
        ).scalar_one()
        n_wbc_missing_still_in = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM analytics.primary_os_cohort c
                JOIN analytics.baseline_covariates_reconciled b
                  ON b.analysis_person_id = c.analysis_person_id
                 AND b.concept = 'wbc_at_diagnosis'
                WHERE b.missingness_class <> 'observed'
                """
            )
        ).scalar_one()
    passed = (
        n_crosswalk > 0
        and n_eligibility > 0
        and n_cohort == n_unique
        and n_unknown == 0
        and n_dead_bad == 0
        and n_alive_bad == 0
        and n_neg == 0
        and n_adult == 0
        and n_excluded_no_reason == 0
        and n_primary_with_reason == 0
    )
    return {
        "n_identity_crosswalk_rows": n_crosswalk,
        "n_eligibility_rows": n_eligibility,
        "n_primary_os_cohort": n_cohort,
        "n_unique_persons_in_cohort": n_unique,
        "n_unknown_or_invalid_event": n_unknown,
        "n_dead_invalid_time": n_dead_bad,
        "n_alive_invalid_time": n_alive_bad,
        "n_negative_os": n_neg,
        "n_age_ge_18_in_primary": n_adult,
        "n_excluded_missing_reason": n_excluded_no_reason,
        "n_primary_with_unobserved_wbc": n_wbc_missing_still_in,
        "passed": passed,
    }


def _supplement_os_qa(
    cohort: list[dict[str, Any]],
    supplements: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    primary = {row["analysis_person_id"]: row for row in cohort}
    by_file: dict[str, list[tuple[Any, Any, Any, Any]]] = defaultdict(list)
    for row in supplements:
        person = row.get("join_barcode")
        if person not in primary:
            continue
        family = workbook_family(row.get("workbook_name"))
        if family is None:
            continue
        gdc = primary[person]
        by_file[family].append(
            (
                gdc["vital_status"],
                row.get("vital_status_raw"),
                gdc["os_days"],
                row.get("os_time_days"),
            )
        )
    out: list[dict[str, Any]] = []
    for family, pairs in sorted(by_file.items()):
        status = categorical_agreement([(item[0], item[1]) for item in pairs])
        times = numeric_discordance([(item[2], item[3]) for item in pairs])
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


def build_primary_cohort(
    engine: Engine,
    output_dir: Path = DEFAULT_OUTPUT,
    detail_dir: Path = DETAIL_DIR,
) -> dict[str, Any]:
    apply_analytics_ddl(engine)
    data = _fetch_staging(engine)
    joined = _joined_cases(data)
    joined_by_case = {row["case_id"]: row for row in joined}
    origin = verify_time_origin(joined)
    if not origin["proceed_with_endpoint"]:
        msg = (
            "Official GDC OS time fields do not share a coherent origin "
            "in this extract; the primary endpoint was not created."
        )
        raise RuntimeError(msg)

    crosswalk = build_identity_crosswalk(joined)
    identity_summary = summarize_identity(crosswalk)
    representatives = [row for row in crosswalk if row["is_representative_case"]]
    supp_by_person: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in data["supplements"]:
        barcode = row.get("join_barcode")
        if barcode:
            item = dict(row)
            item["cells"] = _cells(row)
            supp_by_person[barcode].append(item)

    eligibility: list[dict[str, Any]] = []
    cohort: list[dict[str, Any]] = []
    baseline: list[dict[str, Any]] = []
    for identity in representatives:
        clinical = joined_by_case.get(identity["case_id"], {})
        person_id = identity["analysis_person_id"]
        evaluated = evaluate_person(
            identity=identity,
            clinical=clinical,
            has_diagnosis=bool(clinical.get("has_diagnosis")),
        )
        eligibility.append(evaluated)
        baseline.extend(
            reconcile_person_baselines(
                analysis_person_id=person_id,
                gdc={
                    "age_at_diagnosis_days": clinical.get("age_at_diagnosis_days"),
                    "sex_at_birth": clinical.get("sex_at_birth"),
                    "race": clinical.get("race"),
                    "ethnicity": clinical.get("ethnicity"),
                },
                supplement_rows=supp_by_person.get(person_id, []),
            )
        )
        if evaluated["primary_cohort_eligible"]:
            cohort.append(
                {
                    "analysis_person_id": person_id,
                    "gdc_case_id": identity["case_id"],
                    "submitter_id": identity["submitter_id"],
                    "age_at_diagnosis_days": evaluated["age_at_diagnosis_days"],
                    "age_at_diagnosis_years": evaluated["age_at_diagnosis_years"],
                    "vital_status": evaluated["vital_status"],
                    "os_event": evaluated["os_event"],
                    "os_days": evaluated["os_days"],
                    "os_years": evaluated["os_years"],
                    "os_time_source": evaluated["os_time_source"],
                    "os_event_source": evaluated["os_event_source"] or EVENT_SOURCE,
                    "identity_rule": identity["identity_rule"],
                    "source_provenance": "gdc_cases_api",
                    "qa_flags": {
                        "flags": evaluated["qa_flags"],
                        "n_gdc_cases_for_person": identity["n_gdc_cases_for_person"],
                    },
                }
            )

    n_cases = len(joined)
    n_valid_cases = identity_summary["n_gdc_cases_valid_identity"]
    attrition = [
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
            "n_excluded": n_cases - n_valid_cases,
            "n_remaining": n_valid_cases,
            "notes": (
                "Canonical TARGET-20/21 6-character USI or biospecimen-suffix "
                "extension mapped to that USI."
            ),
        },
        {
            "criterion": "unique_valid_analysis_persons",
            "unit": "analysis_person",
            "n_before": n_valid_cases,
            "n_excluded": 0,
            "n_remaining": identity_summary["n_valid_analysis_persons"],
            "notes": (
                f"{n_valid_cases} GDC cases map to "
                f"{identity_summary['n_valid_analysis_persons']} persons; "
                "extra cases are biospecimen-suffix duplicates, not exclusions."
            ),
        },
    ]
    person_steps = sequential_attrition(eligibility)
    attrition.extend(person_steps[2:])

    os_days = [float(row["os_days"]) for row in cohort]
    n_death = sum(row["os_event"] == 1 for row in cohort)
    n_censor = sum(row["os_event"] == 0 for row in cohort)
    endpoint_summary = {
        "primary_cohort_n": len(cohort),
        "deaths": n_death,
        "censored": n_censor,
        "event_percent": (
            round(n_death / len(cohort) * 100.0, 2) if cohort else None
        ),
        "os_days_min": min(os_days) if os_days else None,
        "os_days_median": _median(os_days),
        "os_days_max": max(os_days) if os_days else None,
        "n_zero_os_times": sum(day == 0 for day in os_days),
        "n_negative_os_times": sum(day < 0 for day in os_days),
        "n_missing_os_times": sum(row["os_days"] is None for row in cohort),
        "n_using_days_to_death": sum(
            row["os_time_source"].endswith("days_to_death") for row in cohort
        ),
        "n_using_days_to_last_follow_up": sum(
            row["os_time_source"].endswith("days_to_last_follow_up") for row in cohort
        ),
        "n_index_date_missing_qa_flag": sum(
            "index_date_missing" in row["qa_flags"]["flags"] for row in cohort
        ),
        "time_origin": origin["conclusion"],
        "note": (
            "No Kaplan-Meier estimate, log-rank test, or covariate-stratified "
            "survival summary was computed."
        ),
    }
    sensitivity = {
        "primary_age_lt_18": sum(
            row["primary_cohort_eligible"] for row in eligibility
        ),
        "sensitivity_age_le_21": sum(
            row["sensitivity_le21_eligible"] for row in eligibility
        ),
        "sensitivity_unrestricted_age": sum(
            row["sensitivity_unrestricted_age_eligible"] for row in eligibility
        ),
        "note": "Eligibility flags only. No survival comparison was performed.",
    }
    primary_ids = [row["analysis_person_id"] for row in cohort]
    availability = availability_rows(
        primary_person_ids=primary_ids, baseline_rows=baseline
    )
    os_qa = _supplement_os_qa(cohort, data["supplements"])

    output_dir.mkdir(parents=True, exist_ok=True)
    detail_dir.mkdir(parents=True, exist_ok=True)
    _write_csv(output_dir / "cohort_attrition.csv", attrition)
    _write_json(output_dir / "cohort_attrition.json", attrition)
    _write_json(output_dir / "endpoint_summary.json", endpoint_summary)
    _write_json(output_dir / "identity_resolution_summary.json", identity_summary)
    _write_json(output_dir / "sensitivity_population_counts.json", sensitivity)
    _write_json(output_dir / "time_origin_verification.json", origin)
    _write_csv(output_dir / "baseline_covariate_availability.csv", availability)
    _write_csv(output_dir / "supplement_os_qa_summary.csv", os_qa)
    _write_json(
        output_dir / "variable_viability.json",
        {
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
                "Viability is scientific/source-quality classification, not "
                "outcome-driven variable selection."
            ),
        },
    )

    _replace_analytics(
        engine,
        crosswalk=crosswalk,
        eligibility=eligibility,
        cohort=cohort,
        baseline=baseline,
    )
    db_validation = _validate_postgres(engine)
    _write_json(output_dir / "database_validation.json", db_validation)
    return {
        "identity_summary": identity_summary,
        "attrition": attrition,
        "endpoint_summary": endpoint_summary,
        "sensitivity": sensitivity,
        "os_qa": os_qa,
        "availability": availability,
        "time_origin": origin,
        "database_validation": db_validation,
        "n_baseline_rows": len(baseline),
        "n_eligibility_rows": len(eligibility),
    }
