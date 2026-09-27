"""Public TARGET-AML access and study-focused GDC source validation."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import requests

from pediastat.config import PROJECT_ROOT

GDC_API_BASE_URL = "https://api.gdc.cancer.gov"
TARGET_AML_PROJECT_ID = "TARGET-AML"
USER_AGENT = "PediaStat (TARGET-AML; public data only)"
DEFAULT_TIMEOUT_SECONDS = 60.0
AUDIT_TIMEOUT_SECONDS = 120.0
DEFAULT_PAGE_SIZE = 500

DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "artifacts" / "source_audit"
DEFAULT_DOWNLOAD_DIR = PROJECT_ROOT / "data" / "raw" / "gdc_open_clinical_supplements"

TARGET_AML_CASES_FILTER: dict[str, Any] = {
    "op": "=",
    "content": {"field": "project.project_id", "value": TARGET_AML_PROJECT_ID},
}
TARGET_AML_CLINICAL_FILES_FILTER: dict[str, Any] = {
    "op": "and",
    "content": [
        {
            "op": "=",
            "content": {
                "field": "cases.project.project_id",
                "value": TARGET_AML_PROJECT_ID,
            },
        },
        {"op": "in", "content": {"field": "data_category", "value": ["Clinical"]}},
    ],
}

# Keep broad ingestion fields until ingest.py and cohort.py are simplified.
GDC_CASE_FIELDS = tuple(
    """
    case_id submitter_id project.project_id disease_type primary_site index_date
    lost_to_followup days_to_lost_to_followup
    demographic.demographic_id demographic.vital_status demographic.days_to_death
    demographic.age_at_index demographic.days_to_birth demographic.sex_at_birth
    demographic.gender demographic.race demographic.ethnicity
    demographic.year_of_birth demographic.year_of_death demographic.cause_of_death
    demographic.age_is_obfuscated
    diagnoses.diagnosis_id diagnoses.age_at_diagnosis diagnoses.days_to_diagnosis
    diagnoses.days_to_last_follow_up diagnoses.primary_diagnosis diagnoses.morphology
    diagnoses.fab_morphology_code diagnoses.tissue_or_organ_of_origin
    diagnoses.site_of_resection_or_biopsy diagnoses.year_of_diagnosis
    diagnoses.icd_10_code diagnoses.classification_of_tumor
    diagnoses.diagnosis_is_primary_disease diagnoses.last_known_disease_status
    diagnoses.progression_or_recurrence diagnoses.days_to_recurrence
    diagnoses.tumor_grade diagnoses.method_of_diagnosis diagnoses.prior_malignancy
    diagnoses.prior_treatment diagnoses.synchronous_malignancy
    diagnoses.residual_disease
    diagnoses.eln_risk_classification diagnoses.calgb_risk_group
    diagnoses.best_overall_response diagnoses.days_to_best_overall_response
    follow_ups.follow_up_id follow_ups.days_to_follow_up follow_ups.timepoint_category
    follow_ups.first_event follow_ups.days_to_first_event follow_ups.year_of_follow_up
    follow_ups.disease_response follow_ups.progression_or_recurrence
    diagnoses.treatments.treatment_id diagnoses.treatments.treatment_type
    diagnoses.treatments.treatment_or_therapy diagnoses.treatments.therapeutic_agents
    diagnoses.treatments.protocol_identifier
    diagnoses.treatments.days_to_treatment_start
    diagnoses.treatments.days_to_treatment_end diagnoses.treatments.timepoint_category
    diagnoses.treatments.treatment_outcome diagnoses.treatments.course_number
    diagnoses.treatments.treatment_intent_type
    diagnoses.treatments.reason_treatment_ended
    """.split()
)
CLINICAL_FILE_FIELDS = tuple(
    (
        "file_id file_name data_category data_type data_format access "
        "file_size md5sum state cases.project.project_id"
    ).split()
)
AUDIT_FIELDS = (
    "case_id",
    "submitter_id",
    "demographic.vital_status",
    "demographic.days_to_death",
    "demographic.sex_at_birth",
    "diagnoses.age_at_diagnosis",
    "diagnoses.days_to_last_follow_up",
    "follow_ups.days_to_follow_up",
)
MISSING_TOKENS = frozenset(
    {
        "not reported",
        "unknown",
        "not allowed to collect",
        "not applicable",
        "missing",
        "not available",
        "--",
        "n/a",
        "na",
    }
)
FIELD_COLUMNS = (
    "field_path",
    "n_cases",
    "n_available",
    "pct_missing",
    "n_usable",
    "n_cases_with_multiple_values",
    "n_cases_with_disagreeing_values",
    "numeric_min",
    "numeric_max",
)
FILE_COLUMNS = (
    "file_id",
    "file_name",
    "data_category",
    "data_type",
    "data_format",
    "access",
    "file_size",
    "md5sum",
    "state",
    "associated_project",
    "n_associated_cases",
)


class GDCAPIError(Exception):
    """GDC request failure with an optional HTTP status code."""

    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


def _request_json(
    method: str,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    payload: dict[str, Any] | None = None,
    session: requests.Session | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    url = f"{GDC_API_BASE_URL}/{path.lstrip('/')}"
    request = getattr(session or requests, method.lower())
    kwargs: dict[str, Any] = {"timeout": timeout}
    if session is None:
        kwargs["headers"] = {"User-Agent": USER_AGENT}
    if params is not None:
        kwargs["params"] = params
    if payload is not None:
        kwargs["json"] = payload
    try:
        response = request(url, **kwargs)
    except requests.RequestException as exc:
        raise GDCAPIError(f"GDC {method} {url} failed: {exc}") from exc
    try:
        if response.status_code >= 400:
            detail = (response.text or "").strip().replace("\n", " ")[:300]
            message = f"GDC request failed ({response.status_code}) for {url}"
            raise GDCAPIError(
                f"{message}: {detail}" if detail else message, response.status_code
            )
        try:
            return response.json()
        except ValueError as exc:
            raise GDCAPIError(f"GDC {method} {url} returned non-JSON") from exc
    finally:
        response.close()


def get_json(
    path: str,
    params: dict[str, Any] | None = None,
    *,
    session: requests.Session | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    return _request_json("GET", path, params=params, session=session, timeout=timeout)


def post_json(
    path: str,
    payload: dict[str, Any],
    *,
    session: requests.Session | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    return _request_json(
        "POST", path, payload=payload, session=session, timeout=timeout
    )


def fetch_project(
    *, timeout: float = DEFAULT_TIMEOUT_SECONDS, session: requests.Session | None = None
) -> dict[str, Any]:
    payload = get_json(
        f"projects/{TARGET_AML_PROJECT_ID}",
        {"expand": "summary,summary.experimental_strategies,summary.data_categories"},
        timeout=timeout,
        session=session,
    )
    data = payload.get("data")
    if not isinstance(data, dict):
        raise GDCAPIError("Unexpected TARGET-AML project payload")
    return data


def fetch_all_cases(
    fields: Sequence[str],
    *,
    page_size: int = DEFAULT_PAGE_SIZE,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    session: requests.Session | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    pagination: dict[str, Any] = {}
    offset = 0
    while True:
        payload = post_json(
            "cases",
            {
                "filters": TARGET_AML_CASES_FILTER,
                "fields": ",".join(fields),
                "size": page_size,
                "from": offset,
            },
            timeout=timeout,
            session=session,
        )
        data = payload.get("data", {})
        page_hits = data.get("hits", [])
        pagination = data.get("pagination", {})
        if not isinstance(page_hits, list):
            raise GDCAPIError("Unexpected cases payload: hits is not a list")
        hits.extend(item for item in page_hits if isinstance(item, dict))
        offset += len(page_hits)
        if not page_hits or offset >= int(pagination.get("total") or 0):
            return hits, pagination


def fetch_clinical_files(
    *, timeout: float = DEFAULT_TIMEOUT_SECONDS, session: requests.Session | None = None
) -> list[dict[str, Any]]:
    payload = post_json(
        "files",
        {
            "filters": TARGET_AML_CLINICAL_FILES_FILTER,
            "fields": ",".join(CLINICAL_FILE_FIELDS),
            "size": 100,
        },
        timeout=timeout,
        session=session,
    )
    hits = payload.get("data", {}).get("hits", [])
    if not isinstance(hits, list):
        raise GDCAPIError("Unexpected files payload: hits is not a list")
    return [item for item in hits if isinstance(item, dict)]


def flatten_clinical_file_row(file_hit: Mapping[str, Any]) -> dict[str, Any]:
    project_ids: list[str] = []
    for case in file_hit.get("cases") or []:
        project = case.get("project") if isinstance(case, dict) else None
        project_id = project.get("project_id") if isinstance(project, dict) else None
        if project_id and str(project_id) not in project_ids:
            project_ids.append(str(project_id))
    return {
        "file_id": file_hit.get("file_id") or file_hit.get("id"),
        "file_name": file_hit.get("file_name"),
        "data_category": file_hit.get("data_category"),
        "data_type": file_hit.get("data_type"),
        "data_format": file_hit.get("data_format"),
        "access": file_hit.get("access"),
        "file_size": file_hit.get("file_size"),
        "md5sum": file_hit.get("md5sum"),
        "state": file_hit.get("state"),
        "associated_project": ";".join(project_ids),
        "n_associated_cases": len(file_hit.get("cases") or []),
    }


def download_open_file(
    file_id: str,
    destination: Path,
    *,
    session: requests.Session | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> None:
    """Download a public file and refuse unauthorized or controlled responses."""
    url = f"{GDC_API_BASE_URL}/data/{file_id}"
    kwargs: dict[str, Any] = {"timeout": timeout, "stream": True}
    if session is None:
        kwargs["headers"] = {"User-Agent": USER_AGENT}
    try:
        response = (session or requests).get(url, **kwargs)
    except requests.RequestException as exc:
        raise GDCAPIError(f"GDC download {url} failed: {exc}") from exc
    try:
        if response.status_code in {401, 403}:
            raise GDCAPIError(
                f"Refusing controlled or unauthorized GDC download for {file_id}",
                response.status_code,
            )
        if response.status_code >= 400:
            raise GDCAPIError(
                f"GDC request failed ({response.status_code}) for {url}",
                response.status_code,
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=64 * 1024):
                if chunk:
                    handle.write(chunk)
    finally:
        response.close()


def md5_file(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(64 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def as_records(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    return []


def classify_vital_status(value: Any) -> str:
    if value is None or (isinstance(value, str) and not value.strip()):
        return "missing"
    token = str(value).strip().lower()
    if token == "alive":
        return "alive"
    if token in {"dead", "deceased"}:
        return "dead"
    return "other"


def _is_null(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def _is_usable(value: Any) -> bool:
    return not _is_null(value) and not (
        isinstance(value, str) and value.strip().lower() in MISSING_TOKENS
    )


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    number = float(value)
    return number if number == number else None


def get_values_at_path(record: Mapping[str, Any], path: str) -> list[Any]:
    """Return every value at a dotted path without collapsing nested records."""
    values: list[Any] = [record]
    for part in path.split("."):
        next_values = []
        for value in values:
            for item in value if isinstance(value, list) else [value]:
                if isinstance(item, Mapping) and part in item:
                    next_values.append(item[part])
        values = next_values
    return values


def summarize_field(
    cases: Sequence[Mapping[str, Any]], field_path: str
) -> dict[str, Any]:
    available = usable = multiple = disagree = 0
    numbers: list[float] = []
    for case in cases:
        values = [v for v in get_values_at_path(case, field_path) if not _is_null(v)]
        available += bool(values)
        usable += any(_is_usable(v) for v in values)
        if len(values) > 1:
            multiple += 1
            disagree += len({repr(v) for v in values}) > 1
        numbers.extend(n for v in values if (n := _number(v)) is not None)
    n_cases = len(cases)
    return {
        "field_path": field_path,
        "n_cases": n_cases,
        "n_available": available,
        "pct_missing": round((n_cases - available) / n_cases * 100, 2)
        if n_cases
        else 0.0,
        "n_usable": usable,
        "n_cases_with_multiple_values": multiple,
        "n_cases_with_disagreeing_values": disagree,
        "numeric_min": min(numbers) if numbers else None,
        "numeric_max": max(numbers) if numbers else None,
    }


def _numeric_values(case: Mapping[str, Any], path: str) -> list[float]:
    return [n for v in get_values_at_path(case, path) if (n := _number(v)) is not None]


def audit_survival_fields(cases: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Compare plausible OS constructions before the endpoint is locked."""
    statuses: Counter[str] = Counter()
    counts: Counter[str] = Counter()
    for case in cases:
        raw = next(
            (
                v
                for v in get_values_at_path(case, "demographic.vital_status")
                if not _is_null(v)
            ),
            None,
        )
        status = classify_vital_status(raw)
        statuses[status] += 1
        death = _numeric_values(case, "demographic.days_to_death")
        dx_fu = _numeric_values(case, "diagnoses.days_to_last_follow_up")
        fu = _numeric_values(case, "follow_ups.days_to_follow_up")

        for name, values in (("death", death), ("dx_fu", dx_fu), ("fu", fu)):
            counts[f"negative_{name}"] += sum(x < 0 for x in values)
            counts[f"zero_{name}"] += sum(x == 0 for x in values)
        counts["multiple_fu"] += len(fu) > 1
        counts["dx_vs_fu_disagree"] += bool(dx_fu and fu and max(dx_fu) != max(fu))

        if status == "dead":
            counts[
                "dead_valid" if any(x >= 0 for x in death) else "dead_missing_time"
            ] += 1
        elif status == "alive":
            dx_valid = any(x >= 0 for x in dx_fu)
            fu_valid = any(x >= 0 for x in fu)
            counts["alive_dx_valid"] += dx_valid
            counts["alive_fu_valid"] += fu_valid
            counts[
                "alive_either_valid" if dx_valid or fu_valid else "alive_missing_time"
            ] += 1

    gdc_style = counts["dead_valid"] + counts["alive_either_valid"]
    return {
        "n_cases": len(cases),
        "vital_status_class_counts": dict(statuses),
        "n_dead_missing_days_to_death": counts["dead_missing_time"],
        "n_alive_missing_all_follow_up_times": counts["alive_missing_time"],
        "n_cases_with_multiple_follow_up_times": counts["multiple_fu"],
        "n_cases_diagnosis_vs_follow_up_time_disagree": counts["dx_vs_fu_disagree"],
        "n_negative_days_to_death_values": counts["negative_death"],
        "n_negative_days_to_last_follow_up_values": counts["negative_dx_fu"],
        "n_negative_days_to_follow_up_values": counts["negative_fu"],
        "n_zero_days_to_death_values": counts["zero_death"],
        "n_zero_days_to_last_follow_up_values": counts["zero_dx_fu"],
        "n_zero_days_to_follow_up_values": counts["zero_fu"],
        "n_cases_with_possible_gdc_style_survival_time": gdc_style,
        "candidate_os_counts": {
            "death_plus_either_follow_up": gdc_style,
            "death_plus_diagnosis_follow_up": counts["dead_valid"]
            + counts["alive_dx_valid"],
            "death_plus_follow_up_records": counts["dead_valid"]
            + counts["alive_fu_valid"],
        },
        "unresolved": [
            "Which follow-up source should define censoring time?",
            "How should disagreement between follow-up sources be handled?",
            "Are zero-day times valid or data errors?",
            "Unknown/missing vital status must not be treated as censored.",
        ],
    }


def _xlsx_sheets(path: Path) -> list[dict[str, Any]]:
    from openpyxl import load_workbook

    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        output = []
        for name in workbook.sheetnames:
            rows = workbook[name].iter_rows(values_only=True)
            header = next(rows, None) or ()
            output.append(
                {
                    "sheet": name,
                    "n_rows": sum(1 for _ in rows),
                    "columns": [
                        "" if value is None else str(value) for value in header
                    ],
                }
            )
        return output
    finally:
        workbook.close()


def _download_supplements(
    rows: Sequence[Mapping[str, Any]],
    download_dir: Path,
    *,
    session: requests.Session,
    timeout: float,
) -> list[dict[str, Any]]:
    inspections = []
    for row in rows:
        file_id = str(row.get("file_id") or "")
        file_name = str(row.get("file_name") or file_id)
        record: dict[str, Any] = {
            "file_id": file_id,
            "file_name": file_name,
            "access": row.get("access"),
        }
        if str(row.get("access") or "").lower() != "open":
            record["downloaded"] = False
            inspections.append(record)
            continue
        destination = download_dir / file_name
        download_open_file(file_id, destination, session=session, timeout=timeout)
        checksum = md5_file(destination)
        record.update(
            downloaded=True,
            checksum_match=checksum == row.get("md5sum") if row.get("md5sum") else None,
        )
        if destination.suffix.lower() == ".xlsx":
            record["sheets"] = _xlsx_sheets(destination)
        inspections.append(record)
    return inspections


def _write_json(path: Path, value: Any) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _write_csv(
    path: Path, columns: Sequence[str], rows: Sequence[Mapping[str, Any]]
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(columns), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def run_audit(
    *,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    download_dir: Path = DEFAULT_DOWNLOAD_DIR,
    skip_download: bool = False,
    page_size: int = DEFAULT_PAGE_SIZE,
    timeout: float = AUDIT_TIMEOUT_SECONDS,
) -> dict[str, Any]:
    """Validate that public TARGET-AML sources can support the survival study."""
    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT
    try:
        started = datetime.now(UTC).replace(microsecond=0).isoformat()
        project = fetch_project(timeout=timeout, session=session)
        cases, pagination = fetch_all_cases(
            AUDIT_FIELDS, page_size=page_size, timeout=timeout, session=session
        )
        fields = [summarize_field(cases, field) for field in AUDIT_FIELDS]
        survival = audit_survival_fields(cases)
        files = [
            flatten_clinical_file_row(row)
            for row in fetch_clinical_files(timeout=timeout, session=session)
        ]
        supplements = (
            []
            if skip_download
            else _download_supplements(
                files, download_dir, session=session, timeout=timeout
            )
        )
        metadata = {
            "audit_timestamp_utc": started,
            "api_base_url": GDC_API_BASE_URL,
            "project_id": project.get("project_id"),
            "name": project.get("name"),
            "n_cases_retrieved": len(cases),
            "cases_api_pagination_total": pagination.get("total"),
            "question": (
                "Can public TARGET-AML clinical sources support a defensible "
                "pediatric overall-survival analysis?"
            ),
        }

        output_dir.mkdir(parents=True, exist_ok=True)
        _write_json(output_dir / "project_metadata.json", metadata)
        _write_csv(
            output_dir / "clinical_field_availability.csv", FIELD_COLUMNS, fields
        )
        _write_json(output_dir / "survival_field_audit.json", survival)
        _write_csv(output_dir / "open_clinical_files.csv", FILE_COLUMNS, files)
        if supplements:
            _write_json(
                output_dir / "open_clinical_supplement_columns.json", supplements
            )
        (output_dir / "entity_cardinality.json").unlink(missing_ok=True)

        return {
            "project_metadata": metadata,
            "field_summaries": fields,
            "survival": survival,
            "clinical_files": files,
            "supplement_inspections": supplements,
            "n_cases": len(cases),
            "output_dir": str(output_dir),
        }
    finally:
        session.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate public TARGET-AML sources for the survival analysis."
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--download-dir", type=Path, default=DEFAULT_DOWNLOAD_DIR)
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE)
    args = parser.parse_args(argv)
    result = run_audit(
        output_dir=args.output_dir,
        download_dir=args.download_dir,
        skip_download=args.skip_download,
        page_size=args.page_size,
    )
    print("TARGET-AML source validation")
    print(f"Cases retrieved: {result['n_cases']}")
    print(
        "Possible GDC-style OS times: "
        f"{result['survival']['n_cases_with_possible_gdc_style_survival_time']}"
    )
    print(f"Artifacts: {result['output_dir']}")
    print("No patient-level dataset was written.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
