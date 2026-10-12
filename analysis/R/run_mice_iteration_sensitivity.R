#!/usr/bin/env Rscript
# Optional 20-versus-100 iteration MICE sensitivity.
# The frozen 20-iteration analysis stays primary. This script is not part of
# make inference. It does not rewrite mice_mids.rds or the primary Cox tables.

sensitivity_dependencies <- c(
  "setup.R",
  "model_setup.R",
  "imputation.R",
  "models.R"
)

resolve_runner_path <- function() {
  if (sys.nframe() > 0L) {
    hits <- character()
    for (i in seq_len(sys.nframe())) {
      env <- sys.frame(i)
      if (exists("ofile", envir = env, inherits = FALSE)) {
        hits <- c(hits, get("ofile", envir = env, inherits = FALSE))
      }
    }
    if (length(hits)) {
      return(normalizePath(hits[[length(hits)]], mustWork = TRUE))
    }
  }
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    return(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE))
  }
  normalizePath(
    file.path(getwd(), "analysis", "R", "run_mice_iteration_sensitivity.R"),
    mustWork = TRUE
  )
}

runner_path <- resolve_runner_path()
script_dir <- dirname(runner_path)
for (script in sensitivity_dependencies) {
  source(file.path(script_dir, script), local = FALSE)
}

PRIMARY_MIDS_NAME <- "mice_mids.rds"
EXTENDED_MIDS_NAME <- "mice_mids_100iter_diagnostic.rds"
COMPARISON_NAME <- "mi_20_vs_100_cox_comparison.csv"
FROZEN_IMPUTATIONS <- 30L
FROZEN_ITERATIONS <- 20L
EXTENDED_ITERATIONS <- 100L
CONTINUATION_ITERATIONS <- 80L
FROZEN_SEED <- 20260814L
BH_ALPHA <- 0.05
PUBLISHED_ABS_TOL <- 1e-6
PUBLISHED_REL_TOL <- 1e-5
LOCAL_SUBSTANTIVE_HR_PCT <- 0.01
LOCAL_SUBSTANTIVE_LOG_HR <- 1e-5

COMPARISON_COLUMNS <- c(
  "model", "term", "predictor_label",
  "beta_20", "se_20", "hr_20", "hr_lcl_20", "hr_ucl_20", "p_value_20",
  "q_value_20", "fmi_20",
  "beta_100", "se_100", "hr_100", "hr_lcl_100", "hr_ucl_100", "p_value_100",
  "q_value_100", "fmi_100",
  "hr_change_pct", "abs_log_hr_shift",
  "ci_excludes_1_20", "ci_excludes_1_100",
  "direction_changed", "ci_null_status_changed",
  "bh_rejects_0.05_20", "bh_rejects_0.05_100", "bh_decision_changed"
)

FORBIDDEN_COMPARISON_COLUMNS <- c(
  "analysis_person_id", "os_days", "os_event", "dfbeta", "dfbetas", "residual"
)

PUBLISHED_ESTIMATE_COLUMNS <- c(
  "beta", "se", "hr", "hr_lcl", "hr_ucl", "p_value", "q_value", "fmi"
)

is_direct_invocation <- function(path) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) != 1L) {
    return(FALSE)
  }
  identical(
    normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE),
    normalizePath(path, mustWork = TRUE)
  )
}

parse_sensitivity_args <- function(args) {
  known <- c("--continue-missing", "--overwrite-extended", "--help")
  unknown <- setdiff(args, known)
  if (length(unknown)) {
    stop(
      "Unknown argument: ", paste(unknown, collapse = ", "), ". ",
      "Supported arguments are --continue-missing and --overwrite-extended.",
      call. = FALSE
    )
  }
  list(
    help = "--help" %in% args,
    continue_missing = "--continue-missing" %in% args,
    overwrite_extended = "--overwrite-extended" %in% args
  )
}

plan_extended_mids <- function(extended_exists, continue_missing, overwrite_extended) {
  if (isTRUE(extended_exists) && isTRUE(overwrite_extended)) {
    return("overwrite")
  }
  if (isTRUE(extended_exists)) {
    return("load")
  }
  if (isTRUE(continue_missing)) {
    return("create")
  }
  stop(
    "Extended MICE object is missing. ",
    "Refusing to start mice::mice.mids(). ",
    "Re-run with --continue-missing to continue the validated 20-iteration ",
    "object for 80 iterations.",
    call. = FALSE
  )
}

assert_extended_save_path <- function(path, primary_path) {
  if (identical(basename(path), basename(primary_path)) ||
      identical(basename(path), PRIMARY_MIDS_NAME)) {
    stop("Refusing to overwrite the primary MICE object ", PRIMARY_MIDS_NAME, ".",
         call. = FALSE)
  }
  if (!identical(basename(path), EXTENDED_MIDS_NAME)) {
    stop("Refusing to write an unexpected MICE file: ", basename(path), ".",
         call. = FALSE)
  }
  invisible(TRUE)
}

assert_mids_field <- function(imp, field) {
  if (!field %in% names(imp)) {
    stop("MICE object is missing ", field, ".", call. = FALSE)
  }
  imp[[field]]
}

assert_chain_history_prefix <- function(extended, original, label) {
  if (is.null(extended) || is.null(original)) {
    stop(label, " chain history is missing.", call. = FALSE)
  }
  if (length(dim(extended)) != 3L || length(dim(original)) != 3L) {
    stop(label, " chain history must be a variable x iteration x chain array.",
         call. = FALSE)
  }
  if (!identical(as.integer(dim(original)[2]), FROZEN_ITERATIONS) ||
      !identical(as.integer(dim(extended)[2]), EXTENDED_ITERATIONS)) {
    stop(
      label, " chain history has iterations ",
      dim(original)[2], " and ", dim(extended)[2],
      "; expected ", FROZEN_ITERATIONS, " and ", EXTENDED_ITERATIONS, ".",
      call. = FALSE
    )
  }
  if (!identical(dim(original)[c(1L, 3L)], dim(extended)[c(1L, 3L)]) ||
      !identical(dimnames(original)[[1]], dimnames(extended)[[1]]) ||
      !identical(dimnames(original)[[3]], dimnames(extended)[[3]])) {
    stop(label, " chain history variables or chains differ.", call. = FALSE)
  }
  prefix <- extended[, seq_len(FROZEN_ITERATIONS), , drop = FALSE]
  if (!identical(prefix, original)) {
    stop(
      label, " chain history for iterations 1-20 does not match the ",
      "20-iteration object.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

assert_extended_mids_is_continuation <- function(imp20, imp100) {
  if (!inherits(imp20, "mids") || !inherits(imp100, "mids")) {
    stop("Both MICE objects must have class mids.", call. = FALSE)
  }
  if (!identical(as.integer(imp20$m), FROZEN_IMPUTATIONS) ||
      !identical(as.integer(imp20$iteration), FROZEN_ITERATIONS) ||
      !identical(as.integer(imp20$seed), FROZEN_SEED)) {
    stop(
      "Primary MICE object must have m = 30, iteration = 20, and seed 20260814.",
      call. = FALSE
    )
  }
  if (!identical(as.integer(imp100$m), FROZEN_IMPUTATIONS)) {
    stop("Extended MICE imputations differ from the 20-iteration object.",
         call. = FALSE)
  }
  if (!identical(as.integer(imp100$iteration), EXTENDED_ITERATIONS)) {
    stop(
      "Extended MICE object has ", imp100$iteration,
      " iterations; expected 100.",
      call. = FALSE
    )
  }
  if (!identical(as.integer(imp100$seed), FROZEN_SEED)) {
    stop("Extended MICE seed differs from 20260814.", call. = FALSE)
  }
  if (!identical(assert_mids_field(imp20, "data"), assert_mids_field(imp100, "data"))) {
    stop("Extended MICE imputation data differ from the 20-iteration object.",
         call. = FALSE)
  }
  if (!identical(assert_mids_field(imp20, "where"), assert_mids_field(imp100, "where"))) {
    stop("Extended MICE missingness pattern differs from the 20-iteration object.",
         call. = FALSE)
  }
  if (!identical(as.logical(imp20$where), as.logical(is.na(imp20$data)))) {
    stop("Primary MICE missingness pattern does not match its input data.",
         call. = FALSE)
  }
  if (!identical(assert_mids_field(imp20, "method"), assert_mids_field(imp100, "method"))) {
    stop("Extended MICE methods differ from the 20-iteration object.",
         call. = FALSE)
  }
  if (!identical(
    assert_mids_field(imp20, "predictorMatrix"),
    assert_mids_field(imp100, "predictorMatrix")
  )) {
    stop("Extended MICE predictor matrix differs from the 20-iteration object.",
         call. = FALSE)
  }
  if (!identical(
    assert_mids_field(imp20, "visitSequence"),
    assert_mids_field(imp100, "visitSequence")
  )) {
    stop("Extended MICE visit sequence differs from the 20-iteration object.",
         call. = FALSE)
  }
  call_text <- paste(deparse(imp100$call), collapse = " ")
  if (!grepl("mice.mids", call_text, fixed = TRUE) ||
      !grepl("maxit", call_text, fixed = TRUE) ||
      !grepl("80", call_text, fixed = TRUE)) {
    stop(
      "Extended MICE object was not produced by mice::mice.mids(..., maxit = 80).",
      call. = FALSE
    )
  }
  assert_chain_history_prefix(imp100$chainMean, imp20$chainMean, "Mean")
  assert_chain_history_prefix(imp100$chainVar, imp20$chainVar, "Variance")
  invisible(TRUE)
}

assert_primary_mids_matches_cohort <- function(imp20, coded, spec) {
  validate_frozen_cohort(coded)
  mi_frame <- build_mice_frame(coded)
  meth <- build_mice_methods(mi_frame, spec)
  pred <- build_mice_predictor_matrix(mi_frame, meth)
  assert_mice_spec(meth, spec)
  assert_saved_mids_compatible(imp20, mi_frame, meth, pred, spec, coded)
  if (!identical(imp20$data, mi_frame)) {
    stop("Primary MICE data differ from the coded-cohort imputation frame.",
         call. = FALSE)
  }
  invisible(mi_frame)
}

continue_mids_eighty_iterations <- function(imp20) {
  if (!identical(as.integer(imp20$iteration), FROZEN_ITERATIONS)) {
    stop("Refusing to continue an object that is not at iteration 20.",
         call. = FALSE)
  }
  message(
    "Continuing the validated 20-iteration MICE object for ",
    CONTINUATION_ITERATIONS, " iterations."
  )
  extended <- mice::mice.mids(
    imp20,
    maxit = CONTINUATION_ITERATIONS,
    printFlag = FALSE
  )
  if (!identical(as.integer(imp20$iteration), FROZEN_ITERATIONS)) {
    stop(
      "Continuation altered the in-memory 20-iteration object. ",
      "The primary file was not overwritten.",
      call. = FALSE
    )
  }
  extended
}

values_disagree <- function(reproduced, published,
                            abs_tol = PUBLISHED_ABS_TOL,
                            rel_tol = PUBLISHED_REL_TOL) {
  if (is.na(reproduced) && is.na(published)) {
    return(FALSE)
  }
  if (is.na(reproduced) || is.na(published)) {
    return(TRUE)
  }
  difference <- abs(reproduced - published)
  scale <- max(abs(reproduced), abs(published))
  difference > abs_tol || (scale > 0 && difference > rel_tol * scale)
}

assert_published_cox_agreement <- function(reproduced, published_path, model_name,
                                           abs_tol = PUBLISHED_ABS_TOL,
                                           rel_tol = PUBLISHED_REL_TOL) {
  if (!file.exists(published_path)) {
    stop("Published Cox table is missing: ", published_path, call. = FALSE)
  }
  published <- utils::read.csv(
    published_path,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (!identical(reproduced$model, rep(model_name, nrow(reproduced)))) {
    stop(model_name, " reproduced table has an unexpected model name.", call. = FALSE)
  }
  if (!identical(reproduced$term, published$term) ||
      !identical(published$model, reproduced$model)) {
    stop(
      model_name, " reproduced terms differ from ", published_path, ".",
      call. = FALSE
    )
  }
  mismatches <- character()
  for (column in PUBLISHED_ESTIMATE_COLUMNS) {
    for (i in seq_len(nrow(reproduced))) {
      if (values_disagree(reproduced[[column]][i], published[[column]][i],
                          abs_tol, rel_tol)) {
        mismatches <- c(mismatches, sprintf(
          "%s %s %s: reproduced %s, published %s",
          model_name, reproduced$term[i], column,
          format(reproduced[[column]][i], digits = 16),
          format(published[[column]][i], digits = 16)
        ))
      }
    }
  }
  if (length(mismatches)) {
    stop(
      "Reproduced 20-iteration estimates differ from ", published_path, ".\n",
      paste(utils::head(mismatches, 12), collapse = "\n"),
      if (length(mismatches) > 12) {
        sprintf("\n... %d additional mismatches.", length(mismatches) - 12L)
      } else {
        ""
      },
      "\nThe primary Cox tables were not overwritten.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

coefficient_sign <- function(beta) {
  ifelse(beta > 0, 1L, ifelse(beta < 0, -1L, 0L))
}

ci_excludes_one <- function(lcl, ucl) {
  (is.finite(lcl) & lcl > 1) | (is.finite(ucl) & ucl < 1)
}

bh_rejects <- function(q, alpha = BH_ALPHA) {
  ifelse(is.na(q), NA, q <= alpha)
}

join_iteration_cox <- function(fit20, fit100) {
  required <- c(
    "model", "term", "predictor_label", "beta", "se", "hr",
    "hr_lcl", "hr_ucl", "p_value", "q_value", "fmi"
  )
  missing <- setdiff(required, names(fit20))
  if (length(missing) || length(setdiff(required, names(fit100)))) {
    stop("Pooled Cox table is missing columns required for the comparison.",
         call. = FALSE)
  }
  if (!identical(fit20$model, fit100$model) || !identical(fit20$term, fit100$term)) {
    stop("20- and 100-iteration Cox tables do not share model terms.", call. = FALSE)
  }
  if (any(fit20$hr <= 0 | fit100$hr <= 0, na.rm = TRUE)) {
    stop("Hazard ratios must be positive before relative change is calculated.",
         call. = FALSE)
  }
  data.frame(
    model = fit20$model,
    term = fit20$term,
    predictor_label = fit20$predictor_label,
    beta_20 = fit20$beta,
    se_20 = fit20$se,
    hr_20 = fit20$hr,
    hr_lcl_20 = fit20$hr_lcl,
    hr_ucl_20 = fit20$hr_ucl,
    p_value_20 = fit20$p_value,
    q_value_20 = fit20$q_value,
    fmi_20 = fit20$fmi,
    beta_100 = fit100$beta,
    se_100 = fit100$se,
    hr_100 = fit100$hr,
    hr_lcl_100 = fit100$hr_lcl,
    hr_ucl_100 = fit100$hr_ucl,
    p_value_100 = fit100$p_value,
    q_value_100 = fit100$q_value,
    fmi_100 = fit100$fmi,
    hr_change_pct = 100 * (fit100$hr - fit20$hr) / fit20$hr,
    abs_log_hr_shift = abs(fit100$beta - fit20$beta),
    ci_excludes_1_20 = ci_excludes_one(fit20$hr_lcl, fit20$hr_ucl),
    ci_excludes_1_100 = ci_excludes_one(fit100$hr_lcl, fit100$hr_ucl),
    direction_changed = coefficient_sign(fit20$beta) != coefficient_sign(fit100$beta),
    ci_null_status_changed = ci_excludes_one(fit20$hr_lcl, fit20$hr_ucl) !=
      ci_excludes_one(fit100$hr_lcl, fit100$hr_ucl),
    bh_rejects_0.05_20 = bh_rejects(fit20$q_value),
    bh_rejects_0.05_100 = bh_rejects(fit100$q_value),
    bh_decision_changed = {
      left <- bh_rejects(fit20$q_value)
      right <- bh_rejects(fit100$q_value)
      ifelse(is.na(left) | is.na(right), NA, left != right)
    },
    stringsAsFactors = FALSE
  )
}

build_iteration_comparison <- function(primary20, secondary20, primary100, secondary100) {
  comparison <- rbind(
    join_iteration_cox(primary20, primary100),
    join_iteration_cox(secondary20, secondary100)
  )
  rownames(comparison) <- NULL
  comparison
}

validate_iteration_comparison <- function(comparison) {
  if (!identical(names(comparison), COMPARISON_COLUMNS)) {
    stop("Comparison table columns differ from the aggregate specification.",
         call. = FALSE)
  }
  if (any(FORBIDDEN_COMPARISON_COLUMNS %in% names(comparison))) {
    stop("Comparison table contains patient-level or residual columns.",
         call. = FALSE)
  }
  keys <- paste(comparison$model, comparison$term, sep = "\t")
  if (nrow(comparison) != 15L || anyDuplicated(keys)) {
    stop(
      "Comparison table must contain exactly 15 unique model-term combinations; found ",
      length(unique(keys)), ".",
      call. = FALSE
    )
  }
  expected_keys <- c(
    paste("primary_clinical", PRIMARY_TERM_ORDER, sep = "\t"),
    paste("secondary_molecular", SECONDARY_TERM_ORDER, sep = "\t")
  )
  if (!identical(keys, expected_keys)) {
    stop("Comparison table model terms differ from the frozen Cox formulas.",
         call. = FALSE)
  }
  finite_columns <- c(
    "beta_20", "se_20", "hr_20", "hr_lcl_20", "hr_ucl_20", "p_value_20", "fmi_20",
    "beta_100", "se_100", "hr_100", "hr_lcl_100", "hr_ucl_100", "p_value_100",
    "fmi_100", "hr_change_pct", "abs_log_hr_shift"
  )
  for (column in finite_columns) {
    if (any(!is.finite(comparison[[column]]))) {
      stop("Comparison column ", column, " has a non-finite estimate.", call. = FALSE)
    }
  }
  biological <- unname(FDR_TERM_MAP)
  if (length(biological) != 7L || anyDuplicated(biological)) {
    stop("Expected seven prespecified biological hypothesis tests.", call. = FALSE)
  }
  bio_rows <- comparison$model == "secondary_molecular" & comparison$term %in% biological
  if (sum(bio_rows) != 7L) {
    stop("Expected seven secondary biological coefficients.", call. = FALSE)
  }
  if (any(!is.finite(comparison$q_value_20[bio_rows])) ||
      any(!is.finite(comparison$q_value_100[bio_rows])) ||
      any(is.na(comparison$bh_decision_changed[bio_rows]))) {
    stop("Biological BH tests are incomplete.", call. = FALSE)
  }
  if (any(!is.na(comparison$q_value_20[!bio_rows])) ||
      any(!is.na(comparison$q_value_100[!bio_rows])) ||
      any(!is.na(comparison$bh_rejects_0.05_20[!bio_rows])) ||
      any(!is.na(comparison$bh_rejects_0.05_100[!bio_rows])) ||
      any(!is.na(comparison$bh_decision_changed[!bio_rows]))) {
    stop("BH decisions were applied outside the seven biological terms.", call. = FALSE)
  }
  logical_columns <- c(
    "ci_excludes_1_20", "ci_excludes_1_100",
    "direction_changed", "ci_null_status_changed"
  )
  for (column in logical_columns) {
    if (any(is.na(comparison[[column]]))) {
      stop("Comparison column ", column, " has a missing decision.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

local_comparison_differences <- function(comparison, reference,
                                         hr_pct_tol = LOCAL_SUBSTANTIVE_HR_PCT,
                                         log_hr_tol = LOCAL_SUBSTANTIVE_LOG_HR) {
  if (is.null(reference) || !nrow(reference)) {
    return(comparison[0, c("model", "term"), drop = FALSE])
  }
  reference$key <- paste(reference$model, reference$term, sep = "\t")
  comparison$key <- paste(comparison$model, comparison$term, sep = "\t")
  shared <- intersect(comparison$key, reference$key)
  rows <- list()
  numeric_columns <- intersect(
    c(
      "beta_20", "beta_100", "hr_20", "hr_100", "hr_change_pct",
      "abs_log_hr_shift", "p_value_20", "p_value_100", "q_value_20", "q_value_100"
    ),
    intersect(names(comparison), names(reference))
  )
  logical_columns <- intersect(
    c(
      "direction_changed", "ci_null_status_changed",
      "ci_excludes_1_20", "ci_excludes_1_100"
    ),
    intersect(names(comparison), names(reference))
  )
  for (key in shared) {
    new_row <- comparison[match(key, comparison$key), , drop = FALSE]
    old_row <- reference[match(key, reference$key), , drop = FALSE]
    for (column in numeric_columns) {
      new_value <- suppressWarnings(as.numeric(new_row[[column]]))
      old_value <- suppressWarnings(as.numeric(old_row[[column]]))
      if (length(new_value) != 1L || length(old_value) != 1L) {
        next
      }
      if (is.na(new_value) && is.na(old_value)) {
        next
      }
      difference <- abs(new_value - old_value)
      substantive <- FALSE
      if (identical(column, "hr_change_pct")) {
        substantive <- isTRUE(difference > hr_pct_tol)
      } else if (identical(column, "abs_log_hr_shift")) {
        substantive <- isTRUE(difference > log_hr_tol)
      } else if (isTRUE(values_disagree(new_value, old_value))) {
        substantive <- TRUE
      }
      if (isTRUE(substantive) || isTRUE(difference > 1e-8)) {
        rows[[length(rows) + 1L]] <- data.frame(
          model = new_row$model,
          term = new_row$term,
          column = column,
          new_value = new_value,
          reference_value = old_value,
          absolute_difference = difference,
          substantive = substantive,
          stringsAsFactors = FALSE
        )
      }
    }
    for (column in logical_columns) {
      new_value <- as.logical(new_row[[column]])
      old_value <- as.logical(old_row[[column]])
      if (!identical(new_value, old_value)) {
        rows[[length(rows) + 1L]] <- data.frame(
          model = new_row$model,
          term = new_row$term,
          column = column,
          new_value = new_value,
          reference_value = old_value,
          absolute_difference = NA_real_,
          substantive = TRUE,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(
      model = character(),
      term = character(),
      column = character(),
      new_value = numeric(),
      reference_value = numeric(),
      absolute_difference = numeric(),
      substantive = logical(),
      stringsAsFactors = FALSE
    ))
  }
  dplyr::bind_rows(rows)
}

report_local_comparison <- function(comparison, reference_path) {
  if (!file.exists(reference_path)) {
    message("No local comparison CSV at ", reference_path, ".")
    return(invisible(comparison[0, , drop = FALSE]))
  }
  reference <- utils::read.csv(
    reference_path,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  differences <- local_comparison_differences(comparison, reference)
  substantive <- if (nrow(differences)) differences[differences$substantive, , drop = FALSE] else differences
  if (nrow(substantive)) {
    message(
      "Substantive differences from ", reference_path, ". ",
      "The new table keeps the current calculation."
    )
    print(substantive, row.names = FALSE)
  } else if (nrow(differences)) {
    message(
      "Local comparison agrees on substantive estimates. ",
      "Largest recorded numeric difference: ",
      max(differences$absolute_difference, na.rm = TRUE), "."
    )
  } else {
    message("Local comparison agrees with ", reference_path, ".")
  }
  invisible(differences)
}

fit_pooled_models <- function(imp, coded, spec) {
  primary_mira <- fit_cox_across_imputations(imp, coded, PRIMARY_FORMULA)
  secondary_mira <- fit_cox_across_imputations(imp, coded, SECONDARY_FORMULA)
  assert_mi_cox_counts(primary_mira, "primary_clinical")
  assert_mi_cox_counts(secondary_mira, "secondary_molecular")
  assert_mi_cox_estimable(primary_mira, "primary_clinical", PRIMARY_TERM_ORDER)
  assert_mi_cox_estimable(secondary_mira, "secondary_molecular", SECONDARY_TERM_ORDER)
  primary <- pool_cox_mira(primary_mira, "primary_clinical", PRIMARY_TERM_ORDER)
  secondary <- apply_bh_qvalues(
    pool_cox_mira(secondary_mira, "secondary_molecular", SECONDARY_TERM_ORDER),
    spec
  )
  list(primary = primary, secondary = secondary)
}

load_or_continue_extended_mids <- function(imp20, extended_path, primary_path, action) {
  if (identical(action, "load")) {
    message("Loading extended MICE object from ", extended_path)
    return(readRDS(extended_path))
  }
  if (!identical(action, "create") && !identical(action, "overwrite")) {
    stop("Unexpected extended-object action: ", action, call. = FALSE)
  }
  assert_extended_save_path(extended_path, primary_path)
  if (identical(action, "create") && file.exists(extended_path)) {
    stop("Refusing to overwrite an existing extended MICE object.", call. = FALSE)
  }
  extended <- continue_mids_eighty_iterations(imp20)
  saveRDS(extended, extended_path)
  message("Wrote extended MICE object to ", extended_path)
  readRDS(extended_path)
}

run_mice_iteration_sensitivity <- function(args = commandArgs(trailingOnly = TRUE)) {
  flags <- parse_sensitivity_args(args)
  if (isTRUE(flags$help)) {
    message(
      "Usage: Rscript analysis/R/run_mice_iteration_sensitivity.R ",
      "[--continue-missing] [--overwrite-extended]"
    )
    return(invisible(NULL))
  }
  load_inference_packages()
  init_inference_paths()
  primary_path <- file.path(INTERIM_INFERENCE, PRIMARY_MIDS_NAME)
  extended_path <- file.path(INTERIM_INFERENCE, EXTENDED_MIDS_NAME)
  coded_path <- file.path(INTERIM_INFERENCE, "coded_primary_cohort.rds")
  output_path <- file.path(INFERENCE_DIR, COMPARISON_NAME)
  reference_path <- file.path(INTERIM_INFERENCE, COMPARISON_NAME)
  if (!file.exists(primary_path)) {
    stop("Primary MICE object is missing: ", primary_path, call. = FALSE)
  }
  if (!file.exists(coded_path)) {
    stop("Coded cohort is missing: ", coded_path, call. = FALSE)
  }
  action <- plan_extended_mids(
    file.exists(extended_path),
    flags$continue_missing,
    flags$overwrite_extended
  )
  if (identical(action, "load") && isTRUE(flags$continue_missing)) {
    message(
      "Extended MICE object already exists. ",
      "Not rerunning mice::mice.mids(). Use --overwrite-extended to replace it."
    )
  }
  imp20 <- readRDS(primary_path)
  coded <- readRDS(coded_path)
  spec <- load_model_spec_yaml()
  assert_primary_mids_matches_cohort(imp20, coded, spec)
  imp100 <- load_or_continue_extended_mids(imp20, extended_path, primary_path, action)
  if (!identical(as.integer(imp20$iteration), FROZEN_ITERATIONS)) {
    stop("Primary MICE iteration changed. The primary file was not rewritten.",
         call. = FALSE)
  }
  assert_extended_mids_is_continuation(imp20, imp100)
  if (!identical(imp100$data, imp20$data)) {
    stop("Extended MICE data differ from the validated primary imputation frame.",
         call. = FALSE)
  }

  message("Fitting 20-iteration Cox models")
  fit20 <- fit_pooled_models(imp20, coded, spec)
  assert_published_cox_agreement(
    fit20$primary,
    file.path(INFERENCE_DIR, "primary_cox_mi.csv"),
    "primary_clinical"
  )
  assert_published_cox_agreement(
    fit20$secondary,
    file.path(INFERENCE_DIR, "secondary_cox_mi.csv"),
    "secondary_molecular"
  )
  message("Fitting 100-iteration Cox models")
  fit100 <- fit_pooled_models(imp100, coded, spec)
  comparison <- build_iteration_comparison(
    fit20$primary, fit20$secondary, fit100$primary, fit100$secondary
  )
  validate_iteration_comparison(comparison)
  report_local_comparison(comparison, reference_path)
  utils::write.csv(comparison, output_path, row.names = FALSE, na = "")
  worst <- comparison[which.max(abs(comparison$hr_change_pct)), , drop = FALSE]
  message(
    "Wrote ", output_path, ". Maximum absolute relative HR change: ",
    format(abs(worst$hr_change_pct), digits = 6), "% (",
    worst$model, " ", worst$term, ")."
  )
  message("Primary 20-iteration MICE object and Cox tables were left unchanged.")
  invisible(output_path)
}

if (is_direct_invocation(runner_path)) {
  run_mice_iteration_sensitivity()
}
