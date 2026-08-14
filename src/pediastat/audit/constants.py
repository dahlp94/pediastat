"""Constants for the TARGET-AML GDC source audit."""

from __future__ import annotations

GDC_API_BASE_URL = "https://api.gdc.cancer.gov"
TARGET_AML_PROJECT_ID = "TARGET-AML"
DEFAULT_TIMEOUT_SECONDS = 60.0
DEFAULT_PAGE_SIZE = 500

# Official GDC missing-like codes. Applied only after inspecting values;
# they are not treated as events or as censored survival times.
GDC_MISSING_CODES = frozenset(
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

ALIVE_STATUS_VALUES = frozenset({"alive"})
DEAD_STATUS_VALUES = frozenset({"dead", "deceased"})

CASE_FIELDS: tuple[str, ...] = (
    "case_id",
    "submitter_id",
    "project.project_id",
    "disease_type",
    "primary_site",
    "index_date",
    "lost_to_followup",
    "days_to_lost_to_followup",
)

DEMOGRAPHIC_FIELDS: tuple[str, ...] = (
    "demographic.demographic_id",
    "demographic.vital_status",
    "demographic.days_to_death",
    "demographic.age_at_index",
    "demographic.days_to_birth",
    "demographic.sex_at_birth",
    "demographic.gender",
    "demographic.race",
    "demographic.ethnicity",
    "demographic.year_of_birth",
    "demographic.year_of_death",
    "demographic.cause_of_death",
    "demographic.age_is_obfuscated",
)

DIAGNOSIS_FIELDS: tuple[str, ...] = (
    "diagnoses.diagnosis_id",
    "diagnoses.age_at_diagnosis",
    "diagnoses.days_to_diagnosis",
    "diagnoses.days_to_last_follow_up",
    "diagnoses.primary_diagnosis",
    "diagnoses.morphology",
    "diagnoses.fab_morphology_code",
    "diagnoses.tissue_or_organ_of_origin",
    "diagnoses.site_of_resection_or_biopsy",
    "diagnoses.year_of_diagnosis",
    "diagnoses.icd_10_code",
    "diagnoses.classification_of_tumor",
    "diagnoses.diagnosis_is_primary_disease",
    "diagnoses.last_known_disease_status",
    "diagnoses.progression_or_recurrence",
    "diagnoses.days_to_recurrence",
    "diagnoses.tumor_grade",
    "diagnoses.method_of_diagnosis",
    "diagnoses.prior_malignancy",
    "diagnoses.prior_treatment",
    "diagnoses.synchronous_malignancy",
    "diagnoses.residual_disease",
    "diagnoses.eln_risk_classification",
    "diagnoses.calgb_risk_group",
    "diagnoses.best_overall_response",
    "diagnoses.days_to_best_overall_response",
)

FOLLOW_UP_FIELDS: tuple[str, ...] = (
    "follow_ups.follow_up_id",
    "follow_ups.days_to_follow_up",
    "follow_ups.timepoint_category",
    "follow_ups.first_event",
    "follow_ups.days_to_first_event",
    "follow_ups.year_of_follow_up",
    "follow_ups.disease_response",
    "follow_ups.progression_or_recurrence",
)

TREATMENT_FIELDS: tuple[str, ...] = (
    "diagnoses.treatments.treatment_id",
    "diagnoses.treatments.treatment_type",
    "diagnoses.treatments.treatment_or_therapy",
    "diagnoses.treatments.therapeutic_agents",
    "diagnoses.treatments.protocol_identifier",
    "diagnoses.treatments.days_to_treatment_start",
    "diagnoses.treatments.days_to_treatment_end",
    "diagnoses.treatments.timepoint_category",
    "diagnoses.treatments.treatment_outcome",
    "diagnoses.treatments.course_number",
    "diagnoses.treatments.treatment_intent_type",
    "diagnoses.treatments.reason_treatment_ended",
)

CANDIDATE_FIELDS: tuple[str, ...] = (
    CASE_FIELDS
    + DEMOGRAPHIC_FIELDS
    + DIAGNOSIS_FIELDS
    + FOLLOW_UP_FIELDS
    + TREATMENT_FIELDS
)

CLINICAL_FILE_FIELDS: tuple[str, ...] = (
    "file_id",
    "file_name",
    "data_category",
    "data_type",
    "data_format",
    "access",
    "file_size",
    "md5sum",
    "state",
    "cases.project.project_id",
)
