# Load the frozen Stage 3 cohort. Stop if accounting does not match.

apply_extract_view <- function(con) {
  lines <- readLines(SQL_VIEW_FILE, warn = FALSE)
  lines <- lines[!grepl("^\\s*--", lines)]
  sql_text <- paste(lines, collapse = "\n")
  statements <- trimws(unlist(strsplit(sql_text, ";", fixed = TRUE)))
  statements <- statements[nzchar(statements)]
  for (statement in statements) {
    DBI::dbExecute(con, statement)
  }
}

validate_frozen_cohort <- function(cohort) {
  n <- nrow(cohort)
  n_id <- dplyr::n_distinct(cohort$analysis_person_id)
  n_event <- sum(cohort$os_event == 1L, na.rm = TRUE)
  n_censored <- sum(cohort$os_event == 0L, na.rm = TRUE)
  n_missing_event <- sum(is.na(cohort$os_event))
  n_missing_time <- sum(is.na(cohort$os_days))
  n_neg_time <- sum(cohort$os_days < 0, na.rm = TRUE)
  n_age_ge18 <- sum(cohort$age_at_diagnosis_years >= 18, na.rm = TRUE)
  n_dup <- sum(duplicated(cohort$analysis_person_id))

  checks <- list(
    n = n,
    unique_ids = n_id,
    deaths = n_event,
    censored = n_censored,
    missing_os_event = n_missing_event,
    missing_os_days = n_missing_time,
    negative_os_days = n_neg_time,
    age_ge_18 = n_age_ge18,
    duplicate_ids = n_dup
  )
  failures <- character()
  if (n != EXPECTED_N) {
    failures <- c(failures, sprintf("N is %s, expected %s", n, EXPECTED_N))
  }
  if (n_id != EXPECTED_N) {
    failures <- c(failures, sprintf("unique analysis_person_id is %s", n_id))
  }
  if (n_event != EXPECTED_DEATHS) {
    failures <- c(failures, sprintf("deaths are %s, expected %s", n_event, EXPECTED_DEATHS))
  }
  if (n_censored != EXPECTED_CENSORED) {
    failures <- c(failures, sprintf("censored are %s, expected %s", n_censored, EXPECTED_CENSORED))
  }
  if (n_missing_event != 0L) failures <- c(failures, "missing os_event")
  if (n_missing_time != 0L) failures <- c(failures, "missing os_days")
  if (n_neg_time != 0L) failures <- c(failures, "negative os_days")
  if (n_age_ge18 != 0L) failures <- c(failures, "age >= 18 in primary cohort")
  if (n_dup != 0L) failures <- c(failures, "duplicate analysis_person_id")
  if (length(failures)) {
    stop(
      "Frozen Stage 3 cohort checks failed; analysis stopped.\n- ",
      paste(failures, collapse = "\n- "),
      call. = FALSE
    )
  }
  checks
}

load_identity_accounting <- function(con) {
  crosswalk <- DBI::dbGetQuery(con, "SELECT * FROM analytics.patient_identity_crosswalk")
  eligibility <- DBI::dbGetQuery(con, "SELECT * FROM analytics.cohort_eligibility")
  list(crosswalk = crosswalk, eligibility = eligibility)
}

reconcile_population_accounting <- function(identity) {
  crosswalk <- identity$crosswalk
  eligibility <- identity$eligibility
  n_cases <- nrow(crosswalk)
  n_valid_cases <- sum(crosswalk$eligible_for_person_level_analysis)
  n_invalid_cases <- sum(!crosswalk$eligible_for_person_level_analysis)
  n_valid_persons <- dplyr::n_distinct(
    crosswalk$analysis_person_id[crosswalk$eligible_for_person_level_analysis]
  )
  n_eligibility <- nrow(eligibility)
  n_elig_valid <- sum(eligibility$has_valid_identity)
  n_elig_invalid <- sum(!eligibility$has_valid_identity)
  reason_counts <- as.list(table(crosswalk$exclusion_reason[!crosswalk$eligible_for_person_level_analysis]))
  interpretation <- paste(
    "analytics.cohort_eligibility has", n_eligibility, "rows because it stores",
    n_elig_valid, "valid analysis persons plus", n_elig_invalid,
    "deliberately retained ineligible identity records.",
    "Those", n_elig_invalid, "rows are not valid analysis persons."
  )
  if (!(n_cases == 2492L && n_valid_cases == 2354L && n_invalid_cases == 138L &&
        n_valid_persons == 2315L && n_eligibility == 2453L &&
        n_elig_valid == 2315L && n_elig_invalid == 138L)) {
    stop("Identity accounting does not match the frozen Stage 3 counts.", call. = FALSE)
  }
  list(
    original_gdc_cases = n_cases,
    gdc_cases_valid_identity = n_valid_cases,
    unique_valid_analysis_persons = n_valid_persons,
    gdc_cases_ineligible_identity = n_invalid_cases,
    ineligible_identity_reasons = reason_counts,
    cohort_eligibility_rows = n_eligibility,
    cohort_eligibility_valid_persons = n_elig_valid,
    cohort_eligibility_ineligible_identity_records = n_elig_invalid,
    interpretation = interpretation,
    primary_os_cohort_n = EXPECTED_N
  )
}

prepare_analysis_cohort <- function(cohort) {
  out <- cohort
  numeric_cols <- c(
    "age_at_diagnosis_days", "age_at_diagnosis_years", "os_event", "os_days",
    "os_years"
  )
  for (col in intersect(numeric_cols, names(out))) {
    out[[col]] <- as.numeric(out[[col]])
  }
  out$os_event <- as.integer(out$os_event)
  for (col in intersect(YES_NO_CONCEPTS, names(out))) {
    out[[paste0(col, "_display")]] <- harmonize_yes_no(out[[col]])
  }
  out$sex_at_birth_table <- categorical_for_table(out$sex_at_birth, out$sex_at_birth_missingness)
  out$race_table <- categorical_for_table(out$race, out$race_missingness)
  out$ethnicity_table <- categorical_for_table(out$ethnicity, out$ethnicity_missingness)
  out$risk_group_table <- categorical_for_table(out$risk_group, out$risk_group_missingness)
  out$flt3_itd_table <- categorical_for_table(out$flt3_itd_display, out$flt3_itd_missingness)
  out$npm_table <- categorical_for_table(out$npm_display, out$npm_missingness)
  out$cebpa_table <- categorical_for_table(out$cebpa_display, out$cebpa_missingness)
  out$fab_table <- categorical_for_table(out$fab, out$fab_missingness)
  out$cns_disease_table <- categorical_for_table(out$cns_disease_display, out$cns_disease_missingness)
  out$cytogenetics_t821_table <- categorical_for_table(out$cytogenetics_t821_display, out$cytogenetics_t821_missingness)
  out$cytogenetics_inv16_table <- categorical_for_table(out$cytogenetics_inv16_display, out$cytogenetics_inv16_missingness)
  out$cytogenetics_mll_table <- categorical_for_table(out$cytogenetics_mll_display, out$cytogenetics_mll_missingness)
  out$cytogenetics_monosomy7_table <- categorical_for_table(out$cytogenetics_monosomy7_display, out$cytogenetics_monosomy7_missingness)
  out$primary_cytogenetic_code_table <- categorical_for_table(
    out$primary_cytogenetic_code,
    out$primary_cytogenetic_code_missingness
  )
  out$wbc_at_diagnosis_num <- suppressWarnings(as.numeric(out$wbc_at_diagnosis))
  out$wbc_at_diagnosis_num[out$wbc_at_diagnosis_missingness != "observed"] <- NA_real_
  out$marrow_blasts_num <- suppressWarnings(as.numeric(out$marrow_blasts))
  out$marrow_blasts_num[out$marrow_blasts_missingness != "observed"] <- NA_real_
  out$peripheral_blasts_num <- suppressWarnings(as.numeric(out$peripheral_blasts))
  out$peripheral_blasts_num[out$peripheral_blasts_missingness != "observed"] <- NA_real_
  out
}

load_primary_cohort <- function(con) {
  apply_extract_view(con)
  cohort <- DBI::dbGetQuery(
    con,
    "SELECT * FROM analytics.stage4_primary_cohort_extract ORDER BY analysis_person_id"
  )
  checks <- validate_frozen_cohort(cohort)
  identity <- load_identity_accounting(con)
  accounting <- reconcile_population_accounting(identity)
  long_baseline <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT b.analysis_person_id, b.concept, b.value, b.source_workbook,",
      "b.source_column, b.source_kind, b.conflict_flag, b.alternative_source_count,",
      "b.missingness_class, b.units",
      "FROM analytics.baseline_covariates_reconciled b",
      "INNER JOIN analytics.primary_os_cohort c USING (analysis_person_id)"
    )
  )
  prepared <- prepare_analysis_cohort(cohort)
  list(
    cohort = prepared,
    checks = checks,
    accounting = accounting,
    long_baseline = long_baseline
  )
}

write_interim_extract <- function(cohort) {
  ensure_output_dirs()
  rds_path <- file.path(INTERIM_DIR, "primary_cohort_extract.rds")
  csv_path <- file.path(INTERIM_DIR, "primary_cohort_extract.csv")
  saveRDS(cohort, rds_path)
  utils::write.csv(cohort, csv_path, row.names = FALSE)
  list(rds = rds_path, csv = csv_path)
}
