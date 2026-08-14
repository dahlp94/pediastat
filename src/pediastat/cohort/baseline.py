"""Deterministic source precedence for baseline AML concepts.

Precedence is locked from Stage 2 source quality, not from survival
association. Completeness alone does not determine rank.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Mapping, Sequence
from typing import Any

from pediastat.ingestion.missingness import classify_missing, is_observed
from pediastat.reconciliation.discordance import _as_number, _norm_category

MOLECULAR_ORDER = (
    "AML1031",
    "Discovery",
    "Validation",
    "LowDepth",
    "additional",
)
FAB_ORDER = (
    "Discovery",
    "Validation",
    "LowDepth",
    "additional",
    "AML1031",
)
CYTO_CODE_ORDER = (
    "Discovery",
    "Validation",
    "AML1031",
    "LowDepth",
    "additional",
)

SUPPLEMENT_CONCEPTS: tuple[dict[str, Any], ...] = (
    {
        "concept": "wbc_at_diagnosis",
        "column": "WBC at Diagnosis",
        "units": "x10^3/mcL",
        "precedence": MOLECULAR_ORDER,
        "kind": "numeric",
        "viability": "CORE CANDIDATE",
    },
    {
        "concept": "risk_group",
        "column": "Risk group",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "CORE CANDIDATE",
    },
    {
        "concept": "flt3_itd",
        "column": "FLT3/ITD positive?",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "CORE CANDIDATE",
    },
    {
        "concept": "npm",
        "column": "NPM mutation",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "CORE CANDIDATE",
    },
    {
        "concept": "cebpa",
        "column": "CEBPA mutation",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "CORE CANDIDATE",
    },
    {
        "concept": "fab",
        "column": "FAB Category",
        "units": None,
        "precedence": FAB_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "cns_disease",
        "column": "CNS disease",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "marrow_blasts",
        "column": "Bone marrow leukemic blast percentage (%)",
        "units": "percent",
        "precedence": MOLECULAR_ORDER,
        "kind": "numeric",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "peripheral_blasts",
        "column": "Peripheral blasts (%)",
        "units": "percent",
        "precedence": MOLECULAR_ORDER,
        "kind": "numeric",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "cytogenetics_t821",
        "column": "t(8;21)",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "cytogenetics_inv16",
        "column": "inv(16)",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "cytogenetics_mll",
        "column": "MLL",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "cytogenetics_monosomy7",
        "column": "monosomy 7",
        "units": None,
        "precedence": MOLECULAR_ORDER,
        "kind": "categorical",
        "viability": "SECONDARY CANDIDATE",
    },
    {
        "concept": "primary_cytogenetic_code",
        "column": "Primary Cytogenetic Code",
        "units": None,
        "precedence": CYTO_CODE_ORDER,
        "kind": "categorical",
        "viability": "NEEDS REVIEW",
    },
)

GDC_CONCEPTS: tuple[dict[str, Any], ...] = (
    {
        "concept": "age_at_diagnosis_days",
        "column": "diagnoses.age_at_diagnosis",
        "units": "days",
        "viability": "CORE CANDIDATE",
        "field": "age_at_diagnosis_days",
    },
    {
        "concept": "sex_at_birth",
        "column": "demographic.sex_at_birth",
        "units": None,
        "viability": "CORE CANDIDATE",
        "field": "sex_at_birth",
    },
    {
        "concept": "race",
        "column": "demographic.race",
        "units": None,
        "viability": "SECONDARY CANDIDATE",
        "field": "race",
    },
    {
        "concept": "ethnicity",
        "column": "demographic.ethnicity",
        "units": None,
        "viability": "SECONDARY CANDIDATE",
        "field": "ethnicity",
    },
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

NOT_RECOMMENDED = (
    {
        "concept": "protocol_identifier",
        "viability": "NOT RECOMMENDED",
        "note": "Possible stratifier, not a biological baseline exposure.",
    },
    {
        "concept": "primary_diagnosis",
        "viability": "NOT RECOMMENDED",
        "note": "No variation (AML NOS only) on the Cases API.",
    },
    {
        "concept": "mrd_end_course_1",
        "viability": "NOT RECOMMENDED",
        "note": "Post-baseline response measure.",
    },
    {
        "concept": "sct_in_first_cr",
        "viability": "NOT RECOMMENDED",
        "note": "Post-baseline treatment; immortal-time risk.",
    },
    {
        "concept": "gemtuzumab",
        "viability": "NOT RECOMMENDED",
        "note": "Post-baseline treatment; no start day on Cases API.",
    },
    {
        "concept": "first_event",
        "viability": "NOT RECOMMENDED",
        "note": "Outcome/EFS construct, not a baseline covariate.",
    },
)


def workbook_family(workbook_name: str | None) -> str | None:
    """Map a workbook filename to a Stage 2 clinical-data family."""
    if not workbook_name:
        return None
    name = workbook_name.lower()
    if "additional" in name or "sortedcells" in name:
        return "additional"
    if "lowdepth" in name:
        return "LowDepth"
    if "discovery" in name and "validation" in name:
        return None
    if "validation" in name:
        return "Validation"
    if "discovery" in name:
        return "Discovery"
    if "aml1031" in name:
        return "AML1031"
    return None


def _values_conflict(kind: str, left: Any, right: Any) -> bool:
    if not is_observed(left) or not is_observed(right):
        return False
    if kind == "numeric":
        left_n = _as_number(left)
        right_n = _as_number(right)
        if left_n is None or right_n is None:
            return _norm_category(left) != _norm_category(right)
        return left_n != right_n
    return _norm_category(left) != _norm_category(right)


def _as_text(value: Any) -> str | None:
    if value is None:
        return None
    return str(value)


def reconcile_supplement_concept(
    *,
    concept: Mapping[str, Any],
    rows: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Choose one source value using locked precedence. Do not average."""
    column = concept["column"]
    order = {name: index for index, name in enumerate(concept["precedence"])}
    observed_ranked: list[tuple[int, Mapping[str, Any], Any]] = []
    missing_ranked: list[tuple[int, Mapping[str, Any], Any]] = []
    for row in rows:
        family = workbook_family(row.get("workbook_name"))
        if family is None or family not in order:
            continue
        cells = row.get("cells") if isinstance(row.get("cells"), dict) else {}
        raw = cells.get(column, row.get(column))
        rank = order[family]
        if is_observed(raw):
            observed_ranked.append((rank, row, raw))
        else:
            missing_ranked.append((rank, row, raw))
    ranked = observed_ranked or missing_ranked
    ranked.sort(key=lambda item: (item[0], str(item[1].get("workbook_name"))))
    observed_sources = len(observed_ranked)
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
    winner = ranked[0]
    observed_values = [
        item[2] for item in ranked if is_observed(item[2])
    ]
    conflict = False
    if len(observed_values) > 1:
        first = observed_values[0]
        conflict = any(
            _values_conflict(concept["kind"], first, other)
            for other in observed_values[1:]
        )
    value = winner[2]
    return {
        "concept": concept["concept"],
        "value": _as_text(value),
        "source_workbook": winner[1].get("workbook_name"),
        "source_column": column,
        "source_kind": "clinical_supplement",
        "conflict_flag": conflict,
        "alternative_source_count": max(observed_sources - 1, 0),
        "missingness_class": classify_missing(value),
        "units": concept["units"],
    }


def reconcile_person_baselines(
    *,
    analysis_person_id: str,
    gdc: Mapping[str, Any],
    supplement_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Build provenance-preserving concept rows for one person."""
    rows: list[dict[str, Any]] = []
    for item in GDC_CONCEPTS:
        value = gdc.get(item["field"])
        rows.append(
            {
                "analysis_person_id": analysis_person_id,
                "concept": item["concept"],
                "value": _as_text(value),
                "source_workbook": None,
                "source_column": item["column"],
                "source_kind": "gdc_cases_api",
                "conflict_flag": False,
                "alternative_source_count": 0,
                "missingness_class": classify_missing(value),
                "units": item["units"],
            }
        )
    by_barcode_rows = list(supplement_rows)
    for concept in SUPPLEMENT_CONCEPTS:
        derived = reconcile_supplement_concept(
            concept=concept, rows=by_barcode_rows
        )
        derived["analysis_person_id"] = analysis_person_id
        rows.append(derived)
    return rows


def availability_rows(
    *,
    primary_person_ids: Sequence[str],
    baseline_rows: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Missingness within the primary cohort only. No outcome stratification."""
    primary = set(primary_person_ids)
    n_primary = len(primary)
    by_concept: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in baseline_rows:
        if row["analysis_person_id"] in primary:
            by_concept[str(row["concept"])].append(row)
    out: list[dict[str, Any]] = []
    catalog = {item["concept"]: item for item in (*GDC_CONCEPTS, *SUPPLEMENT_CONCEPTS)}
    for concept, item in catalog.items():
        recs = by_concept.get(concept, [])
        observed = sum(row["missingness_class"] == "observed" for row in recs)
        unknown = sum(row["missingness_class"] == "unknown" for row in recs)
        missing = n_primary - observed
        conflict = sum(bool(row.get("conflict_flag")) for row in recs)
        out.append(
            {
                "concept": concept,
                "primary_cohort_n": n_primary,
                "observed_n": observed,
                "missing_n": missing,
                "missing_percent": (
                    round(missing / n_primary * 100.0, 2) if n_primary else None
                ),
                "unknown_n": unknown,
                "conflict_n": conflict,
                "viability": item["viability"],
                "note": VIABILITY_NOTES.get(concept),
            }
        )
    for item in NOT_RECOMMENDED:
        out.append(
            {
                "concept": item["concept"],
                "primary_cohort_n": n_primary,
                "observed_n": None,
                "missing_n": None,
                "missing_percent": None,
                "unknown_n": None,
                "conflict_n": None,
                "viability": item["viability"],
                "note": item["note"],
            }
        )
    return out
