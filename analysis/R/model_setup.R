# Stage 5 analysis-variable coding. Does not fit Cox models or run MI.

load_model_spec_yaml <- function() {
  yaml::read_yaml(file.path(PROJECT_ROOT, "config", "model_spec.yaml"))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

age5 <- function(age_years, divisor = 5) {
  out <- as.numeric(age_years) / divisor
  out[!is.finite(out)] <- NA_real_
  out
}

log2_wbc <- function(wbc) {
  x <- as.numeric(wbc)
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x) & x > 0
  out[ok] <- log2(x[ok])
  out
}

standardize_sex <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  mapping <- unlist(spec$coding$sex$map, use.names = TRUE)
  index <- match(tolower(raw), tolower(names(mapping)))
  out <- rep(NA_character_, length(raw))
  hit <- !is.na(index)
  out[hit] <- unname(mapping[index[hit]])
  missing <- is.na(raw) | !nzchar(raw) | raw %in% spec$coding$sex$missing_tokens
  out[missing] <- NA_character_
  factor(out, levels = c(spec$coding$sex$reference, "Male"))
}

standardize_yes_no <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  out <- rep(NA_character_, length(raw))
  out[raw %in% spec$coding$yes_no$yes_tokens | toupper(raw) == "YES"] <- "Yes"
  out[raw %in% spec$coding$yes_no$no_tokens | toupper(raw) == "NO"] <- "No"
  missing <- is.na(raw) | raw %in% spec$coding$yes_no$missing_tokens | raw %in% c("", "NA")
  out[missing] <- NA_character_
  factor(out, levels = c(spec$coding$yes_no$reference, "Yes"))
}

standardize_risk_group <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  std <- qa <- rep(NA_character_, length(raw))
  action <- rep("missing", length(raw))
  for (i in seq_along(raw)) {
    token <- raw[[i]]
    if (is.na(token) || !nzchar(token) || token == "NA") next
    if (token %in% spec$coding$risk_group$unresolved_tokens) {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unresolved_set_missing"
      next
    }
    if (token %in% spec$coding$risk_group$missing_tokens) {
      action[[i]] <- "source_missing"
      next
    }
    mapped <- spec$coding$risk_group$map[[token]]
    if (is.null(mapped)) {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unrecognized_set_missing"
    } else {
      std[[i]] <- mapped
      action[[i]] <- "mapped"
    }
  }
  list(
    original = ifelse(is.na(raw) | raw == "", NA_character_, raw),
    standardized = factor(
      std, levels = c(spec$coding$risk_group$reference, "Standard", "High")
    ),
    qa_flag = qa,
    mapping_action = action
  )
}

nelson_aalen_cumulative_hazard <- function(time, event) {
  # Retained for Stage 6 compatibility; this is an MI auxiliary, not a model fit.
  fit <- survival::survfit(
    survival::Surv(time, event) ~ 1, type = "fleming-harrington"
  )
  idx <- findInterval(time, fit$time)
  out <- rep(0, length(time))
  out[idx > 0] <- fit$cumhaz[idx[idx > 0]]
  out
}

code_inferential_cohort <- function(cohort, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  out <- cohort
  out$age5 <- age5(out$age_at_diagnosis_years, spec$coding$age5_divisor)

  wbc <- suppressWarnings(as.numeric(out$wbc_at_diagnosis))
  if ("wbc_at_diagnosis_missingness" %in% names(out)) {
    wbc[out$wbc_at_diagnosis_missingness != "observed"] <- NA_real_
  }
  out$wbc_at_diagnosis_num <- wbc
  out$log2_wbc <- log2_wbc(wbc)
  out$sex_std <- standardize_sex(out$sex_at_birth, spec)

  risk <- standardize_risk_group(out$risk_group, spec)
  out$risk_group_original <- risk$original
  out$risk_group_std <- risk$standardized
  out$risk_group_qa_flag <- risk$qa_flag
  out$risk_group_mapping_action <- risk$mapping_action

  yes_no <- c(
    "flt3_itd", "npm", "cebpa", "cytogenetics_t821", "cytogenetics_inv16",
    "cytogenetics_mll", "cytogenetics_monosomy7", "cns_disease"
  )
  for (nm in intersect(yes_no, names(out))) {
    out[[paste0(nm, "_std")]] <- standardize_yes_no(out[[nm]], spec)
  }

  if ("wbc_at_diagnosis_source_workbook" %in% names(out)) {
    workbook <- out$wbc_at_diagnosis_source_workbook
    out$source_family_aml1031 <- as.integer(
      grepl("AML1031", workbook, ignore.case = TRUE) &
        !grepl("additional|sorted", workbook, ignore.case = TRUE)
    )
  }
  out
}
# Stage 5 preflight: validate coding and planned design matrices. No Cox or MI.

model_formula <- function(spec, model = c("primary", "secondary")) {
  model <- match.arg(model)
  stats::as.formula(spec[[paste0(model, "_model")]]$formula)
}

model_terms <- function(spec, model = c("primary", "secondary")) {
  attr(stats::terms(model_formula(spec, match.arg(model))), "term.labels")
}

primary_terms <- function(spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  model_terms(spec, "primary")
}

secondary_terms <- function(spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  model_terms(spec, "secondary")
}

model_variables <- function(formula) {
  all.vars(stats::delete.response(stats::terms(formula)))
}

complete_for <- function(cohort, terms) {
  keep <- stats::complete.cases(cohort[, terms, drop = FALSE])
  cohort[keep, terms, drop = FALSE]
}

design_matrix_rank <- function(data, formula) {
  mm <- stats::model.matrix(stats::delete.response(stats::terms(formula)), data = data)
  rank <- qr(mm)$rank
  list(
    n_rows = nrow(mm), n_cols = ncol(mm), rank = rank,
    full_rank = rank == ncol(mm), colnames = colnames(mm)
  )
}

lesion_cooccurrence <- function(cohort) {
  lesions <- c(
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )
  mat <- as.data.frame(
    lapply(lesions, function(nm) as.integer(cohort[[nm]] == "Yes")),
    optional = TRUE
  )
  names(mat) <- lesions
  list(
    n_yes = as.list(colSums(mat, na.rm = TRUE)),
    n_two_or_more_lesions = sum(rowSums(mat, na.rm = TRUE) >= 2)
  )
}

validate_model_structure <- function(spec) {
  primary <- primary_terms(spec)
  secondary <- secondary_terms(spec)
  if (!"risk_group_std" %in% primary ||
      any(grepl("flt3|npm|cebpa|cytogenetics", primary))) {
    stop("Primary model composition does not match the prespecified clinical model.", call. = FALSE)
  }
  if ("risk_group_std" %in% secondary) {
    stop("Secondary molecular model must not include risk_group.", call. = FALSE)
  }
  if (length(spec$primary_model$interactions) || length(spec$secondary_model$interactions)) {
    stop("Stage 5 expects no prespecified interactions.", call. = FALSE)
  }
}

preflight_coded_cohort <- function(cohort, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  if (nrow(cohort) != EXPECTED_N) {
    stop("Preflight cohort N is not the frozen primary cohort.", call. = FALSE)
  }
  if (any(!is.finite(cohort$age5))) {
    stop("age5 has non-finite values.", call. = FALSE)
  }

  observed_wbc <- !is.na(cohort$wbc_at_diagnosis_num)
  if (any(cohort$wbc_at_diagnosis_num[observed_wbc] <= 0, na.rm = TRUE)) {
    stop("Nonpositive observed WBC cannot be log2-transformed.", call. = FALSE)
  }
  if (any(!is.finite(cohort$log2_wbc[observed_wbc]))) {
    stop("log2_wbc is not finite for observed positive WBC.", call. = FALSE)
  }
  if (any(cohort$sex_std == "Unknown", na.rm = TRUE)) {
    stop("Unknown sex should not remain as an inferential level.", call. = FALSE)
  }
  if (any(as.character(cohort$risk_group_std) %in% c("10", "30", "Unknown"))) {
    stop("Unresolved risk-group tokens leaked into the standardized factor.", call. = FALSE)
  }

  validate_model_structure(spec)
  primary_formula <- model_formula(spec, "primary")
  secondary_formula <- model_formula(spec, "secondary")
  primary_cc <- complete_for(cohort, model_variables(primary_formula))
  secondary_cc <- complete_for(cohort, model_variables(secondary_formula))
  primary_mm <- design_matrix_rank(primary_cc, primary_formula)
  secondary_mm <- design_matrix_rank(secondary_cc, secondary_formula)

  if (!primary_mm$full_rank || !secondary_mm$full_rank) {
    stop("A prespecified complete-case design matrix is rank-deficient.", call. = FALSE)
  }
  primary_df <- primary_mm$n_cols - 1L
  secondary_df <- secondary_mm$n_cols - 1L
  if (primary_df != spec$primary_model$df || secondary_df != spec$secondary_model$df) {
    stop("Design-matrix df does not match model_spec.yaml.", call. = FALSE)
  }

  n_unresolved <- sum(
    cohort$risk_group_mapping_action == "unresolved_set_missing", na.rm = TRUE
  )
  if (n_unresolved != 3L) {
    stop("Expected 3 unresolved risk-group tokens (10/30).", call. = FALSE)
  }

  list(
    n = nrow(cohort),
    n_unresolved_risk_tokens = n_unresolved,
    n_risk_group_missing_for_model = sum(is.na(cohort$risk_group_std)),
    n_log2_wbc_missing = sum(is.na(cohort$log2_wbc)),
    n_sex_missing = sum(is.na(cohort$sex_std)),
    n_age5_missing = sum(is.na(cohort$age5)),
    primary_complete_case_n = nrow(primary_cc),
    secondary_complete_case_n = nrow(secondary_cc),
    primary_design_matrix = primary_mm[c("n_rows", "n_cols", "rank", "full_rank")],
    secondary_design_matrix = secondary_mm[c("n_rows", "n_cols", "rank", "full_rank")],
    primary_colnames = primary_mm$colnames,
    secondary_colnames = secondary_mm$colnames,
    lesion_cooccurrence = lesion_cooccurrence(cohort),
    expected_primary_df = spec$primary_model$df,
    expected_secondary_df = spec$secondary_model$df,
    primary_mm_nonintercept_cols = primary_df,
    secondary_mm_nonintercept_cols = secondary_df
  )
}

write_json_artifact_to <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    data, path, pretty = TRUE, auto_unbox = TRUE, na = "null", digits = NA
  )
  path
}

write_model_plan_json <- function(data, filename) {
  write_json_artifact_to(data, file.path(MODEL_PLAN_DIR, filename))
}

write_preflight_artifact <- function(preflight) {
  write_model_plan_json(preflight, "preflight_validation.json")
}

write_risk_token_resolution <- function(cohort) {
  unresolved <- cohort[
    cohort$risk_group_mapping_action == "unresolved_set_missing",
  ]
  payload <- list(
    decision = "set_inferential_value_missing",
    guessed_mapping = FALSE,
    cde_permissible_values = c("High Risk", "Low Risk", "Standard Risk"),
    rationale = paste(
      "TARGET AML CDE Data Elements list only High Risk, Low Risk, and Standard Risk.",
      "Tokens 10 and 30 have no documented mapping, so numeric order was not guessed."
    ),
    n_primary_cohort = nrow(unresolved),
    original_values = as.character(unresolved$risk_group_original),
    source_workbook = if ("risk_group_source_workbook" %in% names(unresolved)) {
      as.character(unresolved$risk_group_source_workbook)
    } else {
      NA_character_
    },
    standardized_value = NA_character_,
    qa_flag = "unresolved_risk_group_token"
  )
  write_model_plan_json(payload, "risk_group_token_resolution.json")
}

write_lesion_verification <- function(preflight) {
  payload <- list(
    included = c(
      "flt3_itd", "npm", "cebpa", "cytogenetics_t821",
      "cytogenetics_inv16", "cytogenetics_mll", "cytogenetics_monosomy7"
    ),
    omitted = list(),
    primary_cytogenetic_code = "NOT INCLUDED IN PRESPECIFIED MODELS",
    baseline_status = "CDE-defined diagnostic/baseline lesion and mutation indicators.",
    coding = "Yes/No after mixed-case harmonization; source-missing values remain missing.",
    cooccurrence = preflight$lesion_cooccurrence,
    note = paste(
      "Rare lesion co-occurrence does not create a singular design.",
      "Primary cytogenetic code is not substituted for lesion flags."
    )
  )
  write_model_plan_json(payload, "lesion_verification.json")
}
# Stage 6: load frozen cohort, apply Stage 5 coding, preflight.
# Does not rebuild eligibility. Does not fit Cox models.

init_stage6_paths <- function() {
  INFERENCE_DIR <<- file.path(PROJECT_ROOT, "artifacts", "inference")
  INFERENCE_MI_DIR <<- file.path(INFERENCE_DIR, "mi")
  INFERENCE_PH_DIR <<- file.path(INFERENCE_DIR, "ph")
  INFERENCE_FIG_DIR <<- file.path(INFERENCE_DIR, "figures")
  INTERIM_STAGE6 <<- file.path(PROJECT_ROOT, "data", "interim", "stage6")
  dir.create(INFERENCE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_MI_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_PH_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_FIG_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INTERIM_STAGE6, recursive = TRUE, showWarnings = FALSE)
  invisible(INFERENCE_DIR)
}

load_stage6_packages <- function() {
  load_stage4_packages()
  extra <- c("mice")
  missing <- extra[!vapply(extra, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop(
      "Missing Stage 6 R packages: ", paste(missing, collapse = ", "),
      ". Install r-mice in the pediastat-r conda environment.",
      call. = FALSE
    )
  }
  if (!requireNamespace("nnet", quietly = TRUE)) {
    stop("Package nnet is required for mice polyreg.", call. = FALSE)
  }
  invisible(lapply(extra, library, character.only = TRUE))
}

write_inference_csv <- function(data, filename, subdir = NULL) {
  base <- if (is.null(subdir)) INFERENCE_DIR else file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

write_inference_json <- function(data, filename, subdir = NULL) {
  base <- if (is.null(subdir)) INFERENCE_DIR else file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
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

save_inference_plot <- function(plot, filename, subdir = "figures",
                                width = 2400, height = 1600, res = 220) {
  base <- file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
  ggplot2::ggsave(
    path,
    plot,
    width = width / res,
    height = height / res,
    dpi = res,
    units = "in"
  )
  path
}

FORBIDDEN_POST_BASELINE <- c(
  "sct_in_first_cr", "mrd_end_course_1", "gemtuzumab",
  "treatment_response", "first_event", "days_to_first_event"
)

standardize_race_aux <- function(x) {
  # Auxiliary-only collapse. Race is not a principal-model predictor.
  # Sparse OMB cells are grouped as Other so polyreg is estimable.
  raw <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(raw))
  out[raw == "white"] <- "White"
  out[raw == "black or african american"] <- "Black or African American"
  out[raw == "asian"] <- "Asian"
  out[raw %in% c(
    "american indian or alaska native",
    "native hawaiian or other pacific islander",
    "other"
  )] <- "Other"
  out[raw %in% c("unknown", "not reported", "notreported", "", "na")] <- NA_character_
  out[is.na(raw) | !nzchar(raw)] <- NA_character_
  leftover <- !is.na(raw) & nzchar(raw) & is.na(out) &
    !(raw %in% c("unknown", "not reported", "notreported", "na"))
  out[leftover] <- "Other"
  factor(
    out,
    levels = c("White", "Black or African American", "Asian", "Other")
  )
}

standardize_ethnicity_aux <- function(x) {
  raw <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(raw))
  out[grepl("not hispanic", raw)] <- "Not Hispanic or Latino"
  hispanic <- grepl("hispanic", raw) & !grepl("not hispanic", raw)
  out[hispanic] <- "Hispanic or Latino"
  out[raw %in% c("unknown", "not reported", "notreported", "", "na")] <- NA_character_
  factor(out, levels = c("Not Hispanic or Latino", "Hispanic or Latino"))
}

assert_no_post_baseline <- function(names_in_use) {
  hit <- intersect(FORBIDDEN_POST_BASELINE, names_in_use)
  if (length(hit)) {
    stop(
      "Post-baseline variables entered the inferential dataset: ",
      paste(hit, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

stage6_preflight_invariants <- function(coded, spec) {
  checks <- validate_frozen_cohort(coded)
  preflight <- preflight_coded_cohort(coded, spec)
  if (anyNA(coded$os_event)) {
    stop("Missing os_event in coded inferential cohort.", call. = FALSE)
  }
  if (anyNA(coded$os_days) || any(coded$os_days < 0, na.rm = TRUE)) {
    stop("Missing or negative os_days in coded inferential cohort.", call. = FALSE)
  }
  if (any(coded$os_days == 0, na.rm = TRUE)) {
    stop("Zero os_days found; Stage 3 frozen cohort had none.", call. = FALSE)
  }
  needed <- unique(c(primary_terms(), secondary_terms(), "os_days", "os_event", "age5"))
  missing_vars <- setdiff(needed, names(coded))
  if (length(missing_vars)) {
    stop("Missing expected model variables: ", paste(missing_vars, collapse = ", "), call. = FALSE)
  }
  if (!identical(levels(coded$sex_std), c("Female", "Male"))) {
    stop("Sex reference/levels are not Female, Male.", call. = FALSE)
  }
  if (!identical(levels(coded$risk_group_std), c("Low", "Standard", "High"))) {
    stop("Risk-group reference/levels are not Low, Standard, High.", call. = FALSE)
  }
  for (nm in c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )) {
    if (!identical(levels(coded[[nm]]), c("No", "Yes"))) {
      stop(nm, " reference/levels are not No, Yes.", call. = FALSE)
    }
  }
  assert_no_post_baseline(names(coded))
  if (grepl("risk_group", spec$secondary_model$formula, fixed = TRUE)) {
    stop("Secondary formula unexpectedly contains risk_group.", call. = FALSE)
  }
  if (length(spec$primary_model$interactions) || length(spec$secondary_model$interactions)) {
    stop("Principal models must have no interactions.", call. = FALSE)
  }
  preflight$cohort_checks <- checks
  preflight$n_unresolved_risk_tokens_recorded <- sum(
    coded$risk_group_mapping_action == "unresolved_set_missing",
    na.rm = TRUE
  )
  preflight
}

prepare_inferential_cohort <- function(loaded, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  coded <- code_inferential_cohort(loaded$cohort, spec)
  coded$nelson_aalen <- nelson_aalen_cumulative_hazard(coded$os_days, coded$os_event)
  if (any(!is.finite(coded$nelson_aalen))) {
    stop("Nelson-Aalen auxiliary has non-finite values.", call. = FALSE)
  }
  coded$race_aux <- standardize_race_aux(coded$race)
  coded$ethnicity_aux <- standardize_ethnicity_aux(coded$ethnicity)
  if (!("source_family_aml1031" %in% names(coded))) {
    coded$source_family_aml1031 <- 0L
  }
  coded$source_family_aml1031[is.na(coded$source_family_aml1031)] <- 0L
  preflight <- stage6_preflight_invariants(coded, spec)
  list(coded = coded, spec = spec, preflight = preflight, loaded = loaded)
}
