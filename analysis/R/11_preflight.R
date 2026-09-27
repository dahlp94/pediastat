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
