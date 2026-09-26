"""Baseline covariate source rules for the analysis cohort.

Source precedence is fixed from source quality, never from survival results.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.ingestion.missingness import classify_missing, is_observed
from pediastat.reconciliation.discordance import _as_number, _norm_category

MOLECULAR_ORDER = ("AML1031", "Discovery", "Validation", "LowDepth", "additional")
FAB_ORDER = ("Discovery", "Validation", "LowDepth", "additional", "AML1031")
CYTO_CODE_ORDER = ("Discovery", "Validation", "AML1031", "LowDepth", "additional")

# concept, source column, units, precedence, kind, viability
_SUPPLEMENT_SPECS = (
    (
        "wbc_at_diagnosis", "WBC at Diagnosis", "x10^3/mcL",
        MOLECULAR_ORDER, "numeric", "CORE CANDIDATE",
    ),
    (
        "risk_group", "Risk group", None,
        MOLECULAR_ORDER, "categorical", "CORE CANDIDATE",
    ),
    (
        "flt3_itd", "FLT3/ITD positive?", None,
        MOLECULAR_ORDER, "categorical", "CORE CANDIDATE",
    ),
    ("npm", "NPM mutation", None, MOLECULAR_ORDER, "categorical", "CORE CANDIDATE"),
    ("cebpa", "CEBPA mutation", None, MOLECULAR_ORDER, "categorical", "CORE CANDIDATE"),
    ("fab", "FAB Category", None, FAB_ORDER, "categorical", "SECONDARY CANDIDATE"),
    (
        "cns_disease", "CNS disease", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "marrow_blasts", "Bone marrow leukemic blast percentage (%)", "percent",
        MOLECULAR_ORDER, "numeric", "SECONDARY CANDIDATE",
    ),
    (
        "peripheral_blasts", "Peripheral blasts (%)", "percent",
        MOLECULAR_ORDER, "numeric", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_t821", "t(8;21)", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_inv16", "inv(16)", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_mll", "MLL", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "cytogenetics_monosomy7", "monosomy 7", None,
        MOLECULAR_ORDER, "categorical", "SECONDARY CANDIDATE",
    ),
    (
        "primary_cytogenetic_code", "Primary Cytogenetic Code", None,
        CYTO_CODE_ORDER, "categorical", "NEEDS REVIEW",
    ),
)

SUPPLEMENT_CONCEPTS = tuple(
    {
        "concept": concept,
        "column": column,
        "units": units,
        "precedence": precedence,
        "kind": kind,
        "viability": viability,
    }
    for concept, column, units, precedence, kind, viability in _SUPPLEMENT_SPECS
)

# concept, source column, units, viability, joined-case field
_GDC_SPECS = (
    (
        "age_at_diagnosis_days", "diagnoses.age_at_diagnosis", "days",
        "CORE CANDIDATE", "age_at_diagnosis_days",
    ),
    (
        "sex_at_birth", "demographic.sex_at_birth", None,
        "CORE CANDIDATE", "sex_at_birth",
    ),
    ("race", "demographic.race", None, "SECONDARY CANDIDATE", "race"),
    ("ethnicity", "demographic.ethnicity", None, "SECONDARY CANDIDATE", "ethnicity"),
)

GDC_CONCEPTS = tuple(
    {
        "concept": concept,
        "column": column,
        "units": units,
        "viability": viability,
        "field": field,
    }
    for concept, column, units, viability, field in _GDC_SPECS
)

VIABILITY_NOTES = {
    "age_at_diagnosis_days": "Baseline timing; GDC preferred; used for eligibility.",
    "sex_at_birth": "GDC demographic field; CDE Gender is not substituted.",
    "race": "Scientifically interpretable but substantial Unknown/not reported.",
    "ethnicity": "Scientifically interpretable but substantial Unknown/not reported.",
    "wbc_at_diagnosis": (
        "Baseline laboratory measure; AML1031 complete; overlaps agree."
    ),
    "risk_group": (
        "Protocol AML risk; AML1031 nearly complete; small LowDepth disagreements."
    ),
    "flt3_itd": "Baseline molecular marker; complete in AML1031.",
    "npm": "Baseline molecular marker; complete in AML1031.",
    "cebpa": "Baseline molecular marker; complete in AML1031.",
    "fab": "Baseline morphology; AML1031 nearly empty so not preferred.",
    "cns_disease": "Baseline CNS involvement; additional file mostly Unknown.",
    "marrow_blasts": "Baseline disease burden; modest missingness.",
    "peripheral_blasts": "Baseline disease burden; modest missingness.",
    "cytogenetics_t821": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_inv16": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_mll": "Lesion flag retained; not collapsed into a composite.",
    "cytogenetics_monosomy7": "Lesion flag retained; not collapsed into a composite.",
    "primary_cytogenetic_code": (
        "Summary code disagrees with LowDepth in overlaps; not assumed "
        "equivalent to lesion flags."
    ),
}

NOT_RECOMMENDED = tuple(
    {"concept": concept, "viability": "NOT RECOMMENDED", "note": note}
    for concept, note in (
        (
            "protocol_identifier",
            "Possible stratifier, not a biological baseline exposure.",
        ),
        ("primary_diagnosis", "No variation (AML NOS only) on the Cases API."),
        ("mrd_end_course_1", "Post-baseline response measure."),
        ("sct_in_first_cr", "Post-baseline treatment; immortal-time risk."),
        ("gemtuzumab", "Post-baseline treatment; no start day on Cases API."),
        ("first_event", "Outcome/EFS construct, not a baseline covariate."),
    )
)


def workbook_family(workbook_name: str | None) -> str | None:
    if not workbook_name:
        return None
    name = workbook_name.lower()
    rules = (
        ("additional", ("additional", "sortedcells")),
        ("LowDepth", ("lowdepth",)),
        ("Validation", ("validation",)),
        ("Discovery", ("discovery",)),
        ("AML1031", ("aml1031",)),
    )
    if "discovery" in name and "validation" in name:
        return None
    return next(
        (family for family, tokens in rules if any(token in name for token in tokens)),
        None,
    )


def _values_conflict(kind: str, left: Any, right: Any) -> bool:
    if not is_observed(left) or not is_observed(right):
        return False
    if kind == "numeric":
        left_n, right_n = _as_number(left), _as_number(right)
        if left_n is not None and right_n is not None:
            return left_n != right_n
    return _norm_category(left) != _norm_category(right)


def reconcile_supplement_concept(
    *,
    concept: Mapping[str, Any],
    rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Choose one value by locked workbook precedence; never average."""
    column = concept["column"]
    order = {name: rank for rank, name in enumerate(concept["precedence"])}
    candidates = []

    for row in rows:
        family = workbook_family(row.get("workbook_name"))
        if family not in order:
            continue
        cells = row.get("cells") if isinstance(row.get("cells"), dict) else {}
        candidates.append((order[family], row, cells.get(column, row.get(column))))

    observed = [item for item in candidates if is_observed(item[2])]
    ranked = sorted(
        observed or candidates,
        key=lambda item: (item[0], str(item[1].get("workbook_name"))),
    )
    if not ranked:
        return {
            "concept": concept["concept"],
            "value": None,
            "source_workbook": None,
            "source_column": column,
            "source_kind": "clinical_supplement",
            "conflict_flag": False,
            "alternative_source_count": 0,
            "missingness_class": "structurally_missing",
            "units": concept["units"],
        }

    value = ranked[0][2]
    observed_values = [item[2] for item in observed]
    conflict = len(observed_values) > 1 and any(
        _values_conflict(concept["kind"], observed_values[0], other)
        for other in observed_values[1:]
    )
    return {
        "concept": concept["concept"],
        "value": None if value is None else str(value),
        "source_workbook": ranked[0][1].get("workbook_name"),
        "source_column": column,
        "source_kind": "clinical_supplement",
        "conflict_flag": conflict,
        "alternative_source_count": max(len(observed) - 1, 0),
        "missingness_class": classify_missing(value),
        "units": concept["units"],
    }


def reconcile_person_baselines(
    *,
    analysis_person_id: str,
    gdc: Mapping[str, Any],
    supplement_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    rows = []
    for item in GDC_CONCEPTS:
        value = gdc.get(item["field"])
        rows.append(
            {
                "analysis_person_id": analysis_person_id,
                "concept": item["concept"],
                "value": None if value is None else str(value),
                "source_workbook": None,
                "source_column": item["column"],
                "source_kind": "gdc_cases_api",
                "conflict_flag": False,
                "alternative_source_count": 0,
                "missingness_class": classify_missing(value),
                "units": item["units"],
            }
        )

    for concept in SUPPLEMENT_CONCEPTS:
        row = reconcile_supplement_concept(concept=concept, rows=supplement_rows)
        row["analysis_person_id"] = analysis_person_id
        rows.append(row)
    return rows


def availability_rows(
    *,
    primary_person_ids: Sequence[str],
    baseline_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Summarize baseline completeness without using outcome information."""
    primary = set(primary_person_ids)
    by_concept: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in baseline_rows:
        if row["analysis_person_id"] in primary:
            by_concept[str(row["concept"])].append(row)

    n = len(primary)
    catalog = {
        item["concept"]: item for item in (*GDC_CONCEPTS, *SUPPLEMENT_CONCEPTS)
    }
    out = []
    for concept, item in catalog.items():
        records = by_concept.get(concept, [])
        observed = sum(row["missingness_class"] == "observed" for row in records)
        missing = n - observed
        out.append(
            {
                "concept": concept,
                "primary_cohort_n": n,
                "observed_n": observed,
                "missing_n": missing,
                "missing_percent": round(missing / n * 100, 2) if n else None,
                "unknown_n": sum(
                    row["missingness_class"] == "unknown" for row in records
                ),
                "conflict_n": sum(bool(row.get("conflict_flag")) for row in records),
                "viability": item["viability"],
                "note": VIABILITY_NOTES.get(concept),
            }
        )

    out.extend(
        {
            "concept": item["concept"],
            "primary_cohort_n": n,
            "observed_n": None,
            "missing_n": None,
            "missing_percent": None,
            "unknown_n": None,
            "conflict_n": None,
            "viability": item["viability"],
            "note": item["note"],
        }
        for item in NOT_RECOMMENDED
    )
    return out
