# Stage 5 preflight: coding and design-matrix checks. No Cox fit. No MI run.

primary_terms <- function() {
  c("age5", "sex_std", "log2_wbc", "risk_group_std")
}

secondary_terms <- function() {
  c(
    "age5", "sex_std", "log2_wbc",
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )
}

complete_for <- function(cohort, terms) {
  keep <- stats::complete.cases(cohort[, terms, drop = FALSE])
  cohort[keep, terms, drop = FALSE]
}

design_matrix_rank <- function(data, formula) {
  mm <- stats::model.matrix(formula, data = data)
  list(
    n_rows = nrow(mm),
    n_cols = ncol(mm),
    rank = qr(mm)$rank,
    full_rank = qr(mm)$rank == ncol(mm),
    colnames = colnames(mm)
  )
}

lesion_cooccurrence <- function(cohort) {
  lesions <- c(
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )
  yes <- lapply(lesions, function(nm) as.integer(cohort[[nm]] == "Yes"))
  mat <- as.data.frame(yes, optional = TRUE)
  names(mat) <- lesions
  n_yes <- colSums(mat, na.rm = TRUE)
  n_multi <- sum(rowSums(mat, na.rm = TRUE) >= 2)
  list(n_yes = as.list(n_yes), n_two_or_more_lesions = n_multi)
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
    stop("Unresolved or unknown risk-group tokens leaked into the standardized factor.", call. = FALSE)
  }

  primary_cc <- complete_for(cohort, primary_terms())
  secondary_cc <- complete_for(cohort, secondary_terms())
  primary_mm <- design_matrix_rank(primary_cc, ~ age5 + sex_std + log2_wbc + risk_group_std)
  secondary_mm <- design_matrix_rank(
    secondary_cc,
    ~ age5 + sex_std + log2_wbc + flt3_itd_std + npm_std + cebpa_std +
      cytogenetics_t821_std + cytogenetics_inv16_std + cytogenetics_mll_std +
      cytogenetics_monosomy7_std
  )
  if (!primary_mm$full_rank) {
    stop("Primary complete-case design matrix is rank-deficient.", call. = FALSE)
  }
  if (!secondary_mm$full_rank) {
    stop("Secondary complete-case design matrix is rank-deficient.", call. = FALSE)
  }

  primary_has_risk <- "risk_group_std" %in% primary_terms()
  primary_has_lesion <- any(grepl("flt3|npm|cebpa|cytogenetics", primary_terms()))
  secondary_has_risk <- "risk_group_std" %in% secondary_terms()
  if (!primary_has_risk || primary_has_lesion) {
    stop("Primary terms must include risk group and exclude molecular/lesion components.", call. = FALSE)
  }
  if (secondary_has_risk) {
    stop("Secondary molecular model must not include risk_group.", call. = FALSE)
  }

  n_unresolved <- sum(cohort$risk_group_mapping_action == "unresolved_set_missing", na.rm = TRUE)
  if (n_unresolved != 3L) {
    stop("Expected 3 unresolved risk-group tokens (10/30) in the primary cohort.", call. = FALSE)
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
    primary_mm_nonintercept_cols = primary_mm$n_cols - 1L,
    secondary_mm_nonintercept_cols = secondary_mm$n_cols - 1L
  )
}

write_risk_token_resolution <- function(cohort) {
  unresolved <- cohort[cohort$risk_group_mapping_action == "unresolved_set_missing", ]
  payload <- list(
    decision = "set_inferential_value_missing",
    guessed_mapping = FALSE,
    cde_permissible_values = c("High Risk", "Low Risk", "Standard Risk"),
    rationale = paste(
      "TARGET AML CDE Data Elements row for Risk group lists only High Risk,",
      "Low Risk, and Standard Risk. Tokens 10 and 30 appear only in the",
      "Validation clinical-data workbook, have no overlapping alternative",
      "source, and have no documented mapping. Numeric order was not used."
    ),
    n_primary_cohort = 3L,
    original_values = as.character(unresolved$risk_group_original),
    source_workbook = if ("risk_group_source_workbook" %in% names(unresolved)) {
      as.character(unresolved$risk_group_source_workbook)
    } else {
      NA_character_
    },
    standardized_value = NA_character_,
    qa_flag = "unresolved_risk_group_token"
  )
  write_json_artifact_to(
    payload,
    file.path(MODEL_PLAN_DIR, "risk_group_token_resolution.json")
  )
}

write_json_artifact_to <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
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

write_preflight_artifact <- function(preflight) {
  write_json_artifact_to(preflight, file.path(MODEL_PLAN_DIR, "preflight_validation.json"))
}

write_lesion_verification <- function(preflight) {
  payload <- list(
    included = c(
      "flt3_itd",
      "npm",
      "cebpa",
      "cytogenetics_t821",
      "cytogenetics_inv16",
      "cytogenetics_mll",
      "cytogenetics_monosomy7"
    ),
    omitted = list(),
    primary_cytogenetic_code = "NOT INCLUDED IN PRESPECIFIED MODELS",
    baseline_status = "CDE-defined diagnostic/baseline lesion and mutation indicators.",
    coding = "Yes/No after mixed-case harmonization; Unknown/Not Reported/Not Done/Not Applicable/structural missing become missing.",
    cooccurrence = preflight$lesion_cooccurrence,
    note = paste(
      "Rare co-occurrence of distinct lesion flags does not create a structurally",
      "singular dummy design. Primary cytogenetic code is not substituted for flags."
    )
  )
  write_json_artifact_to(payload, file.path(MODEL_PLAN_DIR, "lesion_verification.json"))
}
