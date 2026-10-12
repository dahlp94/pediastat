#!/usr/bin/env Rscript
# Execute the frozen Cox + multiple-imputation analysis.
# Does not rebuild eligibility. Does not redesign models from results.

inference_scripts <- c(
  "setup.R",
  "model_setup.R",
  "imputation.R",
  "models.R",
  "diagnostics.R"
)

locate_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)))
  }
  file.path(getwd(), "analysis", "R")
}

script_dir <- locate_script_dir()
for (script in inference_scripts) {
  source(file.path(script_dir, script), local = FALSE)
}

load_inference_packages()
init_inference_paths()

con <- connect_pediastat()
on.exit(DBI::dbDisconnect(con), add = TRUE)

message("Loading the frozen primary cohort and applying model-preflight coding")
loaded <- load_primary_cohort(con)
prepared <- prepare_inferential_cohort(loaded)
coded <- prepared$coded
spec <- prepared$spec
preflight <- prepared$preflight
write_inference_json(preflight, "coded_cohort_preflight.json")
saveRDS(coded, file.path(INTERIM_INFERENCE, "coded_primary_cohort.rds"))

message("Unresolved risk-group tokens (10/30) set to missing: ", preflight$n_unresolved_risk_tokens)

message("Building the MICE specification")
mi_frame <- build_mice_frame(coded)
meth <- build_mice_methods(mi_frame, spec)
pred <- build_mice_predictor_matrix(mi_frame, meth)
assert_mice_spec(meth, spec)

mids_path <- file.path(INTERIM_INFERENCE, "mice_mids.rds")
legacy_reuse <- Sys.getenv("STAGE6_REUSE_MIDS", unset = "")
reuse_flag <- Sys.getenv("INFERENCE_REUSE_MIDS", unset = "")
if (nzchar(legacy_reuse) && !nzchar(reuse_flag)) {
  stop(
    "STAGE6_REUSE_MIDS is set, but INFERENCE_REUSE_MIDS is not. ",
    "Refusing to start mice(). Set INFERENCE_REUSE_MIDS=1 to reuse ",
    mids_path,
    ", or unset STAGE6_REUSE_MIDS before a new imputation.",
    call. = FALSE
  )
}
if (identical(reuse_flag, "1")) {
  if (!file.exists(mids_path)) {
    stop(
      "INFERENCE_REUSE_MIDS=1 but the saved mids object is missing: ",
      mids_path,
      ". Refusing to start a new imputation.",
      call. = FALSE
    )
  }
  message("Reusing saved mids object from ", mids_path)
  imp <- readRDS(mids_path)
  assert_saved_mids_compatible(imp, mi_frame, meth, pred, spec, coded)
} else {
  message("Running multiple imputation (m = 30)")
  imp <- run_multiple_imputation(mi_frame, meth, pred, spec)
  attr(imp, "pediastat_cache_settings") <- mice_cache_settings(meth, pred, spec, coded)
  saveRDS(imp, mids_path)
}
mi_diag <- write_mi_diagnostics(imp, mi_frame, spec)
if (length(mi_diag$issues)) {
  stop(
    "MI plausibility issues; analysis stopped before Cox fitting.\n",
    paste(mi_diag$issues, collapse = "\n"),
    call. = FALSE
  )
}

message("Fitting pooled primary and secondary Cox models")
# Use the shared Cox fitting helper so principal MI fits retain their
# warnings and estimability metadata (like diagnostic/sensitivity fits).
primary_mira <- fit_cox_across_imputations(imp, coded, PRIMARY_FORMULA)
secondary_mira <- fit_cox_across_imputations(imp, coded, SECONDARY_FORMULA)
if ("risk_group_std" %in% names(coef(secondary_mira$analyses[[1]]))) {
  stop("Risk group leaked into the secondary molecular model.", call. = FALSE)
}
lesion_in_primary <- grepl("flt3|npm|cebpa|cytogenetics", paste(names(coef(primary_mira$analyses[[1]])), collapse = " "))
if (isTRUE(lesion_in_primary)) {
  stop("Molecular/lesion terms leaked into the primary clinical model.", call. = FALSE)
}

# Write warning diagnostics before validating or pooling; a failed run
# retains the evidence needed to investigate the affected imputation.
primary_warn <- cox_warning_summary(primary_mira, "primary_clinical")
secondary_warn <- cox_warning_summary(secondary_mira, "secondary_molecular")
cox_warnings <- dplyr::bind_rows(primary_warn, secondary_warn)
write_inference_csv(cox_warnings, "cox_fit_warnings.csv")

# Complete counts are necessary but insufficient: also require finite,
# estimable, warning-free coefficients and covariance matrices.
assert_mi_cox_counts(primary_mira, "primary_clinical")
assert_mi_cox_counts(secondary_mira, "secondary_molecular")
assert_mi_cox_estimable(primary_mira, "primary_clinical", PRIMARY_TERM_ORDER)
assert_mi_cox_estimable(secondary_mira, "secondary_molecular", SECONDARY_TERM_ORDER)

primary_mi <- pool_cox_mira(primary_mira, "primary_clinical", PRIMARY_TERM_ORDER)
secondary_mi <- pool_cox_mira(secondary_mira, "secondary_molecular", SECONDARY_TERM_ORDER)
secondary_mi <- apply_bh_qvalues(secondary_mi, spec)
primary_conc <- concordance_from_mira(primary_mira)
secondary_conc <- concordance_from_mira(secondary_mira)

risk_global <- tryCatch(
  global_risk_group_test(imp, coded),
  error = function(e) {
    list(
      method = "mice::D1 failed; individual Standard vs Low and High vs Low contrasts are reported",
      statistic = NA_real_,
      df1 = 2,
      df2 = NA_real_,
      p_value = NA_real_,
      error = conditionMessage(e)
    )
  }
)
write_inference_json(risk_global, "primary_risk_group_global_test.json")

message("Complete-case sensitivity")
primary_cc <- fit_complete_case(coded, PRIMARY_FORMULA, primary_terms(), "primary_clinical", PRIMARY_TERM_ORDER)
secondary_cc <- fit_complete_case(coded, SECONDARY_FORMULA, secondary_terms(), "secondary_molecular", SECONDARY_TERM_ORDER)

message("Nonlinear sensitivity")
nonlinear <- run_nonlinear_sensitivity(imp, coded, spec)

message("PH diagnostics")
ph <- run_ph_diagnostics(imp, coded, primary_cc, secondary_cc)

message("Influence diagnostics")
influence <- run_influence_diagnostics(primary_cc, secondary_cc)

message("Prespecified KM displays")
km <- run_stratified_km(coded)

message("Writing aggregate outputs")
outputs <- write_inference_outputs(
  spec, primary_mi, secondary_mi, primary_cc, secondary_cc,
  primary_conc, secondary_conc, ph, influence, km, mi_diag
)
write_inference_json(
  list(
    primary_concordance = primary_conc,
    secondary_concordance = secondary_conc,
    risk_group_global = risk_global,
    ph_remediation_notes = ph$remediation$notes,
    km = list(
      risk_group = km$risk_group_plot,
      flt3 = km$flt3_plot,
      log_rank = km$log_rank
    )
  ),
  "analysis_notes.json"
)

test_file <- file.path(script_dir, "tests", "test_inference.R")
if (file.exists(test_file)) {
  results <- as.data.frame(testthat::test_file(test_file, reporter = "progress"))
  n_failed <- sum(results$failed, na.rm = TRUE) + sum(results$error, na.rm = TRUE)
  if (n_failed > 0) {
    stop("Inference R tests failed.", call. = FALSE)
  }
}

# make inference sets this so Quarto runs once, in the Makefile, after this script.
if (identical(Sys.getenv("INFERENCE_DEFER_REPORT_RENDER", unset = ""), "1")) {
  message(
    "Skipping Quarto in run_inference.R (INFERENCE_DEFER_REPORT_RENDER=1) ",
    "so the caller can render the inferential report once."
  )
} else {
  if (!nzchar(Sys.getenv("QUARTO_R", unset = ""))) {
    r_bin <- file.path(R.home("bin"), "R")
    if (file.exists(r_bin)) {
      Sys.setenv(QUARTO_R = r_bin)
    }
  }
  if (!nzchar(Sys.getenv("QUARTO", unset = ""))) {
    found_quarto <- Sys.which("quarto")
    if (nzchar(found_quarto)) {
      Sys.setenv(QUARTO = found_quarto)
    }
  }
  if (!nzchar(Sys.getenv("RSCRIPT", unset = ""))) {
    rscript_bin <- file.path(R.home("bin"), "Rscript")
    if (file.exists(rscript_bin)) {
      Sys.setenv(RSCRIPT = rscript_bin)
    }
  }
  qmd <- file.path(PROJECT_ROOT, "reports", "inferential_analysis.qmd")
  html <- file.path(PROJECT_ROOT, "reports", "inferential_analysis.html")
  status <- system2(
    "sh",
    c(
      file.path(script_dir, "render_quarto_or_fallback.sh"),
      qmd,
      file.path(script_dir, "render_inference_report.R"),
      "inferential analysis",
      html
    )
  )
  if (!identical(as.integer(status), 0L)) {
    stop(
      "Inferential report rendering failed. Quarto and the abbreviated R fallback did not produce ",
      html,
      ".",
      call. = FALSE
    )
  }
}

message("Inference complete. Aggregate artifacts: ", INFERENCE_DIR)
message("Person-level MI object (gitignored): ", file.path(INTERIM_INFERENCE, "mice_mids.rds"))
