"""Small helpers for reading public TARGET-AML data from the GDC API."""

from __future__ import annotations

import hashlib
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

import requests

GDC_API_BASE_URL = "https://api.gdc.cancer.gov"
TARGET_AML_PROJECT_ID = "TARGET-AML"
DEFAULT_TIMEOUT_SECONDS = 60.0
USER_AGENT = "PediaStat (TARGET-AML; public data only)"

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
        {
            "op": "in",
            "content": {"field": "data_category", "value": ["Clinical"]},
        },
    ],
}

# Fields needed by the current ingestion tables. The source audit uses a much
# smaller study-focused subset defined in pediastat.audit.
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
    diagnoses.residual_disease diagnoses.eln_risk_classification
    diagnoses.calgb_risk_group diagnoses.best_overall_response
    diagnoses.days_to_best_overall_response
    follow_ups.follow_up_id follow_ups.days_to_follow_up follow_ups.timepoint_category
    follow_ups.first_event follow_ups.days_to_first_event follow_ups.year_of_follow_up
    follow_ups.disease_response follow_ups.progression_or_recurrence
    diagnoses.treatments.treatment_id diagnoses.treatments.treatment_type
    diagnoses.treatments.treatment_or_therapy diagnoses.treatments.therapeutic_agents
    diagnoses.treatments.protocol_identifier
    diagnoses.treatments.days_to_treatment_start
    diagnoses.treatments.days_to_treatment_end
    diagnoses.treatments.timepoint_category diagnoses.treatments.treatment_outcome
    diagnoses.treatments.course_number diagnoses.treatments.treatment_intent_type
    diagnoses.treatments.reason_treatment_ended
    """.split()
)

CLINICAL_FILE_FIELDS = tuple(
    """
    file_id file_name data_category data_type data_format access file_size md5sum state
    cases.project.project_id
    """.split()
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
            if detail:
                message += f": {detail}"
            raise GDCAPIError(message, status_code=response.status_code)
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
    return _request_json(
        "GET",
        path,
        params=params,
        session=session,
        timeout=timeout,
    )


def post_json(
    path: str,
    payload: dict[str, Any],
    *,
    session: requests.Session | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    return _request_json(
        "POST",
        path,
        payload=payload,
        session=session,
        timeout=timeout,
    )


def fetch_project(
    *,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    session: requests.Session | None = None,
) -> dict[str, Any]:
    payload = get_json(
        f"projects/{TARGET_AML_PROJECT_ID}",
        params={
            "expand": (
                "summary,summary.experimental_strategies,"
                "summary.data_categories"
            )
        },
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
    page_size: int = 500,
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
    *,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    session: requests.Session | None = None,
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
    project_ids = []
    for case in file_hit.get("cases") or []:
        project = case.get("project") if isinstance(case, dict) else None
        if isinstance(project, dict) and project.get("project_id"):
            project_id = str(project["project_id"])
            if project_id not in project_ids:
                project_ids.append(project_id)

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
    """Download a public file; refuse unauthorized/controlled responses."""
    url = f"{GDC_API_BASE_URL}/data/{file_id}"
    request = (session or requests).get
    kwargs: dict[str, Any] = {"timeout": timeout, "stream": True}
    if session is None:
        kwargs["headers"] = {"User-Agent": USER_AGENT}

    try:
        response = request(url, **kwargs)
    except requests.RequestException as exc:
        raise GDCAPIError(f"GDC download {url} failed: {exc}") from exc

    try:
        if response.status_code in {401, 403}:
            raise GDCAPIError(
                f"Refusing controlled or unauthorized GDC download for {file_id}",
                status_code=response.status_code,
            )
        if response.status_code >= 400:
            raise GDCAPIError(
                f"GDC request failed ({response.status_code}) for {url}",
                status_code=response.status_code,
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
    """Map GDC vital status to alive/dead/missing/other."""
    if value is None or (isinstance(value, str) and not value.strip()):
        return "missing"
    token = str(value).strip().lower()
    if token == "alive":
        return "alive"
    if token in {"dead", "deceased"}:
        return "dead"
    return "other"
