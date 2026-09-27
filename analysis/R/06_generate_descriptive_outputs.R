# Provenance and compact descriptive-analysis summaries.

MODEL_PLANNING_ARTIFACTS <- c(
  "core_candidate_readiness.csv",
  "redundancy_continuous_spearman.csv",
  "redundancy_findings.csv",
  "redundancy_primary_code_by_inv16.csv",
  "redundancy_primary_code_by_mll.csv",
  "redundancy_primary_code_by_monosomy7.csv",
  "redundancy_primary_code_by_t821.csv",
  "redundancy_risk_group_by_flt3.csv",
  "redundancy_risk_group_by_t821.csv",
  "missingness_patterns_top15.csv"
)

remove_stale_stage4_artifacts <- function() {
  paths <- file.path(DESCRIPTIVE_DIR, MODEL_PLANNING_ARTIFACTS)
  existing <- paths[file.exists(paths)]
  if (length(existing)) {
    unlink(existing)
  }
  invisible(existing)
}

source_provenance_table <- function(long_baseline) {
  family <- workbook_family(long_baseline$source_workbook)
  family[long_baseline$source_kind == "gdc_cases_api"] <- "GDC"
  family[is.na(family)] <- "none/unresolved"
  long_baseline$family <- family

  families <- c(
    "AML1031",
    "Discovery",
    "Validation",
    "LowDepth",
    "additional",
    "GDC",
    "none/unresolved"
  )

  rows <- lapply(unique(long_baseline$concept), function(concept_name) {
    sub <- long_baseline[long_baseline$concept == concept_name, ]
    observed <- sub[sub$missingness_class == "observed", ]
    counts <- table(factor(observed$family, levels = families))

    data.frame(
      concept = concept_name,
      n_primary_cohort = nrow(sub),
      n_observed = nrow(observed),
      n_AML1031 = unname(counts["AML1031"]),
      n_Discovery = unname(counts["Discovery"]),
      n_Validation = unname(counts["Validation"]),
      n_LowDepth = unname(counts["LowDepth"]),
      n_additional = unname(counts["additional"]),
      n_GDC = unname(counts["GDC"]),
      n_none_unresolved_observed = unname(counts["none/unresolved"]),
      n_conflict_flag = sum(as.logical(sub$conflict_flag), na.rm = TRUE),
      n_not_observed = sum(sub$missingness_class != "observed"),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

endpoint_description <- function(cohort, km_result, followup) {
  list(
    primary_cohort_n = nrow(cohort),
    deaths = sum(cohort$os_event == 1L),
    censored = sum(cohort$os_event == 0L),
    crude_event_percent = round(100 * mean(cohort$os_event == 1L), 2),
    crude_event_percent_note = paste(
      "Crude event percentage is deaths/N, not cumulative mortality risk.",
      "Use Kaplan-Meier for survival probability."
    ),
    observed_os_days_min = min(cohort$os_days),
    observed_os_days_max = max(cohort$os_days),
    observed_os_years_min = min(cohort$os_years),
    observed_os_years_max = max(cohort$os_years),
    reverse_km_followup = followup$statement,
    median_os = km_result$median_os$statement,
    index_date_missing_qa_flag_n = sum(
      grepl(
        "index_date_missing",
        as.character(cohort$qa_flags),
        fixed = TRUE
      )
    )
  )
}

run_stage4_outputs <- function(
  loaded,
  descriptives,
  km_result,
  followup,
  provenance
) {
  remove_stale_stage4_artifacts()

  write_json_artifact(
    loaded$accounting,
    "population_accounting.json"
  )
  write_csv_artifact(
    provenance,
    "baseline_source_provenance.csv"
  )

  endpoint <- endpoint_description(
    loaded$cohort,
    km_result,
    followup
  )
  write_json_artifact(
    endpoint,
    "endpoint_followup_description.json"
  )

  session <- session_info_list()
  write_json_artifact(
    session,
    "r_session_info.json"
  )
  write_json_artifact(
    list(
      km_1_3_5_year = km_result$estimates[
        km_result$estimates$time_years %in% c(1, 3, 5),
      ],
      median_os = km_result$median_os,
      n_risk = km_result$n_risk,
      table1_has_pvalue = isTRUE(
        descriptives$table1_paths$has_pvalue
      )
    ),
    "overall_survival_summary.json"
  )

  list(
    accounting = loaded$accounting,
    endpoint = endpoint,
    session = session
  )
}
