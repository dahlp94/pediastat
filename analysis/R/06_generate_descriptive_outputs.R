# Provenance, predictor redundancy without outcome, and analysis-readiness.

source_provenance_table <- function(long_baseline) {
  long_baseline$family <- workbook_family(long_baseline$source_workbook)
  long_baseline$family <- ifelse(
    long_baseline$source_kind == "gdc_cases_api",
    "GDC",
    ifelse(is.na(long_baseline$family), "none/unresolved", long_baseline$family)
  )
  families <- c("AML1031", "Discovery", "Validation", "LowDepth", "additional", "GDC", "none/unresolved")
  concepts <- unique(long_baseline$concept)
  rows <- lapply(concepts, function(concept_name) {
    sub <- long_baseline[long_baseline$concept == concept_name, ]
    observed <- sub[sub$missingness_class == "observed", ]
    counts <- vapply(families, function(fam) sum(observed$family == fam), integer(1))
    n_conflict <- sum(as.logical(sub$conflict_flag), na.rm = TRUE)
    n_unresolved <- sum(sub$missingness_class != "observed")
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
      n_conflict_flag = n_conflict,
      n_not_observed = n_unresolved,
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

crosstab_counts <- function(x, y, x_name, y_name) {
  tab <- as.data.frame(table(x = x, y = y), stringsAsFactors = FALSE)
  names(tab) <- c(x_name, y_name, "n")
  tab$percent_of_row <- NA_real_
  if (nrow(tab)) {
    row_tot <- stats::ave(tab$n, tab[[x_name]], FUN = sum)
    tab$percent_of_row <- round(100 * tab$n / row_tot, 1)
  }
  tab
}

spearman_observed <- function(x, y, x_name, y_name) {
  keep <- !is.na(x) & !is.na(y)
  n <- sum(keep)
  if (n < 10L) {
    return(data.frame(
      x = x_name, y = y_name, n = n, spearman_rho = NA_real_,
      note = "too few paired observations", stringsAsFactors = FALSE
    ))
  }
  rho <- suppressWarnings(stats::cor(x[keep], y[keep], method = "spearman"))
  data.frame(
    x = x_name, y = y_name, n = n, spearman_rho = rho,
    note = "Predictor-to-predictor association only; outcome was not used.",
    stringsAsFactors = FALSE
  )
}

run_redundancy <- function(cohort) {
  risk_flt3 <- crosstab_counts(
    cohort$risk_group_table, cohort$flt3_itd_table, "risk_group", "flt3_itd"
  )
  write_csv_artifact(risk_flt3, "redundancy_risk_group_by_flt3.csv")

  risk_t821 <- crosstab_counts(
    cohort$risk_group_table, cohort$cytogenetics_t821_table, "risk_group", "t821"
  )
  write_csv_artifact(risk_t821, "redundancy_risk_group_by_t821.csv")

  code_t821 <- crosstab_counts(
    cohort$primary_cytogenetic_code_table,
    cohort$cytogenetics_t821_table,
    "primary_cytogenetic_code",
    "t821"
  )
  write_csv_artifact(code_t821, "redundancy_primary_code_by_t821.csv")

  code_inv16 <- crosstab_counts(
    cohort$primary_cytogenetic_code_table,
    cohort$cytogenetics_inv16_table,
    "primary_cytogenetic_code",
    "inv16"
  )
  write_csv_artifact(code_inv16, "redundancy_primary_code_by_inv16.csv")

  code_mll <- crosstab_counts(
    cohort$primary_cytogenetic_code_table,
    cohort$cytogenetics_mll_table,
    "primary_cytogenetic_code",
    "mll"
  )
  write_csv_artifact(code_mll, "redundancy_primary_code_by_mll.csv")

  code_mono7 <- crosstab_counts(
    cohort$primary_cytogenetic_code_table,
    cohort$cytogenetics_monosomy7_table,
    "primary_cytogenetic_code",
    "monosomy7"
  )
  write_csv_artifact(code_mono7, "redundancy_primary_code_by_monosomy7.csv")

  cors <- dplyr::bind_rows(
    spearman_observed(
      cohort$wbc_at_diagnosis_num, cohort$peripheral_blasts_num,
      "wbc_at_diagnosis", "peripheral_blasts"
    ),
    spearman_observed(
      cohort$marrow_blasts_num, cohort$peripheral_blasts_num,
      "marrow_blasts", "peripheral_blasts"
    ),
    spearman_observed(
      cohort$wbc_at_diagnosis_num, cohort$marrow_blasts_num,
      "wbc_at_diagnosis", "marrow_blasts"
    )
  )
  write_csv_artifact(cors, "redundancy_continuous_spearman.csv")

  findings <- data.frame(
    pair = c(
      "risk_group vs FLT3/ITD",
      "risk_group vs cytogenetic lesion flags",
      "primary_cytogenetic_code vs lesion flags",
      "WBC vs peripheral blasts",
      "marrow blasts vs peripheral blasts"
    ),
    status = "POTENTIAL REDUNDANCY — REVIEW BEFORE MODEL SPECIFICATION",
    rationale = c(
      "Risk group is defined from cytogenetics and biomarkers; FLT3/ITD is one input to that construct in pediatric AML protocols.",
      "Favorable lesions such as t(8;21) and inv(16) are used in risk assignment; dual inclusion needs a clinical coding rule.",
      "The summary code is not assumed equivalent to lesion flags; Stage 3 classified it NEEDS REVIEW after source disagreement.",
      "Both are diagnosis burden measures; correlation does not imply dropping either variable.",
      "Both are diagnosis burden measures on different compartments."
    ),
    stringsAsFactors = FALSE
  )
  write_csv_artifact(findings, "redundancy_findings.csv")
  list(findings = findings, correlations = cors)
}

analysis_readiness <- function(cohort, missingness, continuous) {
  wbc <- continuous[continuous$variable == "wbc_at_diagnosis", ]
  n_risk_unexpected <- sum(cohort$risk_group %in% c("10", "30"), na.rm = TRUE)
  n_flt3_case <- sum(cohort$flt3_itd %in% c("YES", "NO"), na.rm = TRUE)
  n_npm_case <- sum(cohort$npm %in% c("YES", "NO"), na.rm = TRUE)
  n_cebpa_case <- sum(cohort$cebpa %in% c("YES", "NO"), na.rm = TRUE)
  miss <- function(concept) {
    row <- missingness$by_variable[missingness$by_variable$concept == concept, ]
    if (!nrow(row)) NA_real_ else row$missing_percent[1]
  }
  data.frame(
    covariate = c(
      "age_at_diagnosis", "sex_at_birth", "wbc_at_diagnosis",
      "risk_group", "flt3_itd", "npm", "cebpa"
    ),
    usable_as_currently_coded = c(
      "Yes",
      "Yes",
      "Yes, with a prespecified continuous structure",
      "Mostly, pending review of unexpected tokens",
      "Yes, after case-harmonizing Yes/NO tokens",
      "Yes, after case-harmonizing Yes/NO tokens",
      "Yes, after case-harmonizing Yes/NO tokens"
    ),
    structure = c(
      "Continuous (years or days)",
      "Binary (male/female); unknown absent in primary cohort",
      "Continuous, strongly right-skewed",
      "Nominal: High / Low / Standard Risk",
      "Binary Yes/No plus Unknown",
      "Binary Yes/No plus Unknown",
      "Binary Yes/No plus Unknown"
    ),
    missing_percent = c(
      0,
      0,
      miss("wbc_at_diagnosis"),
      miss("risk_group"),
      miss("flt3_itd"),
      miss("npm"),
      miss("cebpa")
    ),
    sparse_levels = c(
      "None",
      "None",
      "None (continuous)",
      sprintf("%s rows coded 10 or 30, which are not CDE High/Low/Standard labels", n_risk_unexpected),
      sprintf("Yes is not sparse; mixed-case YES/NO tokens n=%s", n_flt3_case),
      sprintf("Yes is less common than No; mixed-case tokens n=%s", n_npm_case),
      sprintf("Yes is less common than No; mixed-case tokens n=%s", n_cebpa_case)
    ),
    source_reliability = c(
      "GDC; complete in the locked cohort because age is an eligibility variable",
      "GDC demographic.sex_at_birth",
      "Supplement; AML1031 preferred; Stage 2 overlap agreement was complete",
      "Supplement; AML1031 preferred; small LowDepth disagreements flagged in Stage 3",
      "Supplement; AML1031 preferred",
      "Supplement; AML1031 preferred",
      "Supplement; AML1031 preferred"
    ),
    coding_issue = c(
      "None for eligibility or description",
      "Do not substitute CDE Gender",
      sprintf(
        "Min %.2f, median %.1f, max %.1f x10^3/mcL; skewness %.2f",
        wbc$min, wbc$median, wbc$max, wbc$skewness
      ),
      "Unexpected numeric tokens 10 and 30 require clinical review; do not silently recode",
      "Source mixed Yes/YES and No/NO; display harmonization is not clinical collapsing",
      "Same mixed-case source coding as FLT3/ITD",
      "Same mixed-case source coding as FLT3/ITD"
    ),
    likely_modeling_consideration = c(
      "Use continuous age; any grouping must be prespecified, not outcome-driven",
      "Keep male/female; no sparse-level problem",
      "Prespecify log, other transformation, or spline because of skew; do not choose the form by survival association",
      "Review 10/30 tokens and Unknown before model lock; do not drop High Risk for sparsity",
      "Keep Yes/No; decide whether Unknown is a level or handled by the missing-data method",
      "Keep Yes/No; Unknown handling belongs to the missing-data plan",
      "Keep Yes/No; Unknown handling belongs to the missing-data plan"
    ),
    stringsAsFactors = FALSE
  )
}

endpoint_description <- function(cohort, km_result, followup) {
  list(
    primary_cohort_n = nrow(cohort),
    deaths = sum(cohort$os_event == 1L),
    censored = sum(cohort$os_event == 0L),
    crude_event_percent = round(100 * mean(cohort$os_event == 1L), 2),
    crude_event_percent_note = paste(
      "Crude event percentage is deaths/N. It is not a cumulative mortality risk,",
      "because follow-up duration differs across persons. Use Kaplan-Meier for survival probability."
    ),
    observed_os_days_min = min(cohort$os_days),
    observed_os_days_max = max(cohort$os_days),
    observed_os_years_min = min(cohort$os_years),
    observed_os_years_max = max(cohort$os_years),
    reverse_km_followup = followup$statement,
    median_os = km_result$median_os$statement,
    index_date_missing_qa_flag_n = sum(
      grepl("index_date_missing", as.character(cohort$qa_flags), fixed = TRUE)
    )
  )
}

run_stage4_outputs <- function(loaded, descriptives, missingness, km_result, followup, provenance, redundancy) {
  accounting <- loaded$accounting
  write_json_artifact(accounting, "population_accounting.json")
  write_csv_artifact(provenance, "baseline_source_provenance.csv")
  readiness <- analysis_readiness(loaded$cohort, missingness, descriptives$continuous)
  write_csv_artifact(readiness, "core_candidate_readiness.csv")
  endpoint <- endpoint_description(loaded$cohort, km_result, followup)
  write_json_artifact(endpoint, "endpoint_followup_description.json")
  session <- session_info_list()
  write_json_artifact(session, "r_session_info.json")
  write_json_artifact(
    list(
      km_1_3_5_year = km_result$estimates[km_result$estimates$time_years %in% c(1, 3, 5), ],
      median_os = km_result$median_os,
      n_risk = km_result$n_risk,
      table1_has_pvalue = isTRUE(descriptives$table1_paths$has_pvalue)
    ),
    "overall_survival_summary.json"
  )
  list(
    accounting = accounting,
    readiness = readiness,
    endpoint = endpoint,
    session = session
  )
}
