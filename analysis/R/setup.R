# Stage 4 shared setup. No modeling. No outcome-stratified tables.

EXPECTED_N <- 1978L
EXPECTED_DEATHS <- 695L
EXPECTED_CENSORED <- 1283L
DAYS_PER_YEAR <- 365.25
KM_TIMES_YEARS <- c(0, 1, 3, 5, 10)
SPARSE_N <- 20L

REQUIRED_PACKAGES <- c(
  "DBI", "RPostgres", "dplyr", "tidyr", "ggplot2", "survival",
  "gtsummary", "gt", "broom", "here", "scales", "yaml", "jsonlite",
  "testthat"
)

SUPPLEMENT_CONCEPTS <- c(
  "wbc_at_diagnosis", "risk_group", "flt3_itd", "npm", "cebpa", "fab",
  "cns_disease", "marrow_blasts", "peripheral_blasts",
  "cytogenetics_t821", "cytogenetics_inv16", "cytogenetics_mll",
  "cytogenetics_monosomy7", "primary_cytogenetic_code"
)

CORE_CANDIDATES <- c(
  "age_at_diagnosis_years", "sex_at_birth", "wbc_at_diagnosis",
  "risk_group", "flt3_itd", "npm", "cebpa"
)

YES_NO_CONCEPTS <- c(
  "flt3_itd", "npm", "cebpa", "cns_disease",
  "cytogenetics_t821", "cytogenetics_inv16", "cytogenetics_mll",
  "cytogenetics_monosomy7"
)

find_project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) {
    return(here::here())
  }
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    script <- normalizePath(sub("^--file=", "", file_arg), winslash = "/", mustWork = TRUE)
    return(normalizePath(file.path(dirname(script), "..", ".."), winslash = "/", mustWork = TRUE))
  }
  getwd()
}

PROJECT_ROOT <- find_project_root()
DESCRIPTIVE_DIR <- file.path(PROJECT_ROOT, "artifacts", "descriptive")
FIGURE_DIR <- file.path(DESCRIPTIVE_DIR, "figures")
INTERIM_DIR <- file.path(PROJECT_ROOT, "data", "interim", "stage4")
SQL_VIEW_FILE <- file.path(PROJECT_ROOT, "sql", "08_create_stage4_extract_view.sql")

ensure_output_dirs <- function() {
  dir.create(DESCRIPTIVE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INTERIM_DIR, recursive = TRUE, showWarnings = FALSE)
}

load_stage4_packages <- function() {
  missing <- REQUIRED_PACKAGES[!vapply(
    REQUIRED_PACKAGES,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )]
  if (length(missing)) {
    stop(
      "Missing R packages: ", paste(missing, collapse = ", "),
      ". Install the pediastat-r conda environment or renv restore.",
      call. = FALSE
    )
  }
  invisible(lapply(REQUIRED_PACKAGES, library, character.only = TRUE))
}

connect_pediastat <- function() {
  host <- Sys.getenv("POSTGRES_HOST", "localhost")
  port_env <- Sys.getenv("POSTGRES_PORT", "")
  dbname <- Sys.getenv("POSTGRES_DB", "pediastat")
  user <- Sys.getenv("POSTGRES_USER", "pediastat")
  password <- Sys.getenv("POSTGRES_PASSWORD", "")
  ports <- if (nzchar(port_env)) {
    as.integer(port_env)
  } else {
    c(5433L, 5432L)
  }
  last_error <- NULL
  for (port in unique(ports)) {
    tryCatch(
      {
        con <- DBI::dbConnect(
          RPostgres::Postgres(),
          host = host,
          port = port,
          dbname = dbname,
          user = user,
          password = password
        )
        return(con)
      },
      error = function(e) {
        last_error <<- e
      }
    )
  }
  stop("Could not connect to PostgreSQL: ", conditionMessage(last_error), call. = FALSE)
}

workbook_family <- function(workbook_name) {
  name <- tolower(ifelse(is.na(workbook_name), "", workbook_name))
  dplyr::case_when(
    !nzchar(name) ~ NA_character_,
    grepl("additional|sortedcells", name) ~ "additional",
    grepl("lowdepth", name) ~ "LowDepth",
    grepl("validation", name) ~ "Validation",
    grepl("discovery", name) ~ "Discovery",
    grepl("aml1031", name) ~ "AML1031",
    TRUE ~ NA_character_
  )
}

harmonize_yes_no <- function(x) {
  raw <- trimws(as.character(x))
  out <- raw
  out[toupper(raw) == "YES"] <- "Yes"
  out[toupper(raw) == "NO"] <- "No"
  out[raw == "" | is.na(raw)] <- NA_character_
  out
}

is_unknown_token <- function(x) {
  token <- tolower(trimws(as.character(x)))
  token %in% c("unknown", "unspecified", "not reported", "notreported")
}

categorical_for_table <- function(value, missingness) {
  value_chr <- ifelse(is.na(value), "", trimws(as.character(value)))
  miss <- ifelse(is.na(missingness), "", as.character(missingness))
  dplyr::case_when(
    miss == "structurally_missing" | value_chr == "" ~ "Missing",
    miss == "not_reported" ~ "Not reported",
    miss == "unknown" | is_unknown_token(value_chr) ~ "Unknown",
    TRUE ~ value_chr
  )
}

write_csv_artifact <- function(data, filename) {
  path <- file.path(DESCRIPTIVE_DIR, filename)
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

write_json_artifact <- function(data, filename) {
  path <- file.path(DESCRIPTIVE_DIR, filename)
  jsonlite::write_json(
    data,
    path,
    pretty = TRUE,
    auto_unbox = TRUE,
    na = "null",
    digits = NA
  )
  path
}

quantile_named <- function(x, probs) {
  stats::quantile(x, probs = probs, names = FALSE, na.rm = TRUE, type = 7)
}

surv_quantile <- function(fit, p) {
  q <- stats::quantile(fit, probs = p)
  if (is.list(q)) {
    c(
      est = as.numeric(q$quantile)[1],
      lcl = as.numeric(q$lower)[1],
      ucl = as.numeric(q$upper)[1]
    )
  } else {
    c(est = as.numeric(q)[1], lcl = NA_real_, ucl = NA_real_)
  }
}

session_info_list <- function() {
  info <- utils::sessionInfo()
  pkgs <- vapply(info$otherPkgs, function(p) p$Version, character(1))
  attached <- vapply(info$loadedOnly, function(p) p$Version, character(1))
  list(
    r_version = paste(info$R.version$major, info$R.version$minor, sep = "."),
    platform = info$R.version$platform,
    running = info$running,
    packages = as.list(c(pkgs, attached)[REQUIRED_PACKAGES])
  )
}
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
