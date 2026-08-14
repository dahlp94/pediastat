"""TARGET-AML filter construction for the GDC API."""

from __future__ import annotations

from typing import Any

from pediastat.audit.constants import TARGET_AML_PROJECT_ID


def project_equals_filter(project_id: str = TARGET_AML_PROJECT_ID) -> dict[str, Any]:
    """Return a GDC equality filter for a single project_id."""
    return {
        "op": "=",
        "content": {
            "field": "project.project_id",
            "value": project_id,
        },
    }


def files_project_equals_filter(
    project_id: str = TARGET_AML_PROJECT_ID,
) -> dict[str, Any]:
    """Return a GDC equality filter for files belonging to a project."""
    return {
        "op": "=",
        "content": {
            "field": "cases.project.project_id",
            "value": project_id,
        },
    }


def and_filter(*filters: dict[str, Any]) -> dict[str, Any]:
    """Combine GDC filters with AND."""
    return {"op": "and", "content": list(filters)}


def in_filter(field: str, values: list[str]) -> dict[str, Any]:
    """Return a GDC IN filter."""
    return {
        "op": "in",
        "content": {
            "field": field,
            "value": values,
        },
    }


def target_aml_cases_filter() -> dict[str, Any]:
    """Filter restricted to TARGET-AML cases."""
    return project_equals_filter(TARGET_AML_PROJECT_ID)


def target_aml_clinical_files_filter() -> dict[str, Any]:
    """Filter for TARGET-AML files in the Clinical data category."""
    return and_filter(
        files_project_equals_filter(TARGET_AML_PROJECT_ID),
        in_filter("data_category", ["Clinical"]),
    )
