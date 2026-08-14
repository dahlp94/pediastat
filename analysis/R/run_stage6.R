#!/usr/bin/env Rscript
# Stage 6: execute the frozen Stage 5 Cox + multiple-imputation analysis.
# Does not rebuild eligibility. Does not redesign models from results.

stage6_scripts <- c(
  "00_setup.R",
  "01_load_primary_cohort.R",
  "10_model_coding.R",
  "11_preflight.R",
  "20_prepare_inferential_data.R",
  "21_mi_specification.R",
  "22_run_multiple_imputation.R",
  "23_fit_cox_models.R",
  "25_nonlinear_sensitivity.R",
  "26_ph_diagnostics.R",
  "27_influence_diagnostics.R",
  "28_stratified_km.R",
  "29_generate_model_outputs.R"
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
for (script in stage6_scripts) {
  source(file.path(script_dir, script), local = FALSE)
}

load_stage6_packages()
init_stage6_paths()

con <- connect_pediastat()
on.exit(DBI::dbDisconnect(con), add = TRUE)

message("Stage 6: loading frozen primary cohort and applying Stage 5 coding")
loaded <- load_primary_cohort(con)
prepared <- prepare_inferential_cohort(loaded)
coded <- prepared$coded
spec <- prepared$spec
preflight <- prepared$preflight
write_inference_json(preflight, "stage6_preflight.json")
saveRDS(coded, file.path(INTERIM_STAGE6, "coded_primary_cohort.rds"))

message("Unresolved risk-group tokens (10/30) set to missing: ", preflight$n_unresolved_risk_tokens)

message("Stage 6: building MICE specification")
mi_frame <- build_mice_frame(coded)
meth <- build_mice_methods(mi_frame, spec)
pred <- build_mice_predictor_matrix(mi_frame, meth)
assert_mice_spec(meth, spec)

message("Stage 6: running multiple imputation (m = 30)")
mids_path <- file.path(INTERIM_STAGE6, "mice_mids.rds")
reuse_mids <- identical(Sys.getenv("STAGE6_REUSE_MIDS"), "1") && file.exists(mids_path)
if (reuse_mids) {
  message("Reusing saved mids object from ", mids_path)
  imp <- readRDS(mids_path)
  if (!identical(imp$m, 30L) && !identical(as.integer(imp$m), 30L)) {
    stop("Saved mids object does not have m = 30.", call. = FALSE)
  }
} else {
  imp <- run_multiple_imputation(mi_frame, meth, pred, spec)
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

message("Stage 6: fitting pooled primary and secondary Cox models")
primary_mira <- with(
  imp,
  survival::coxph(
    survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std,
    ties = "efron",
    model = TRUE,
    x = TRUE,
    y = TRUE
  )
)
secondary_mira <- with(
  imp,
  survival::coxph(
    survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc +
      flt3_itd_std + npm_std + cebpa_std +
      cytogenetics_t821_std + cytogenetics_inv16_std +
      cytogenetics_mll_std + cytogenetics_monosomy7_std,
    ties = "efron",
    model = TRUE,
    x = TRUE,
    y = TRUE
  )
)
if ("risk_group_std" %in% names(coef(secondary_mira$analyses[[1]]))) {
  stop("Risk group leaked into the secondary molecular model.", call. = FALSE)
}
lesion_in_primary <- grepl("flt3|npm|cebpa|cytogenetics", paste(names(coef(primary_mira$analyses[[1]])), collapse = " "))
if (isTRUE(lesion_in_primary)) {
  stop("Molecular/lesion terms leaked into the primary clinical model.", call. = FALSE)
}

primary_mi <- pool_cox_mira(primary_mira, "primary_clinical", PRIMARY_TERM_ORDER)
secondary_mi <- pool_cox_mira(secondary_mira, "secondary_molecular", SECONDARY_TERM_ORDER)
secondary_mi <- apply_bh_qvalues(secondary_mi, spec)
primary_conc <- concordance_from_mira(primary_mira)
secondary_conc <- concordance_from_mira(secondary_mira)
primary_warn <- cox_warning_summary(primary_mira, "primary_clinical")
secondary_warn <- cox_warning_summary(secondary_mira, "secondary_molecular")
cox_warnings <- dplyr::bind_rows(primary_warn, secondary_warn)
if (nrow(cox_warnings)) {
  write_inference_csv(cox_warnings, "cox_fit_warnings.csv")
}

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

message("Stage 6: complete-case sensitivity")
primary_cc <- fit_complete_case(coded, PRIMARY_FORMULA, primary_terms(), "primary_clinical", PRIMARY_TERM_ORDER)
secondary_cc <- fit_complete_case(coded, SECONDARY_FORMULA, secondary_terms(), "secondary_molecular", SECONDARY_TERM_ORDER)

message("Stage 6: nonlinear sensitivity")
nonlinear <- run_nonlinear_sensitivity(imp, coded, spec)

message("Stage 6: PH diagnostics")
ph <- run_ph_diagnostics(imp, coded, primary_cc, secondary_cc)

message("Stage 6: influence diagnostics")
influence <- run_influence_diagnostics(primary_cc, secondary_cc)

message("Stage 6: prespecified KM displays")
km <- run_stratified_km(coded)

message("Stage 6: writing aggregate outputs")
outputs <- write_stage6_outputs(
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

test_file <- file.path(script_dir, "tests", "test_stage6.R")
if (file.exists(test_file)) {
  results <- as.data.frame(testthat::test_file(test_file, reporter = "progress"))
  n_failed <- sum(results$failed, na.rm = TRUE) + sum(results$error, na.rm = TRUE)
  if (n_failed > 0) {
    stop("Stage 6 R tests failed.", call. = FALSE)
  }
}

quarto_bin <- Sys.getenv("QUARTO", unset = "")
if (!nzchar(quarto_bin)) {
  conda_q <- file.path(Sys.getenv("HOME"), "miniconda3", "envs", "pediastat-r", "bin", "quarto")
  if (file.exists(conda_q)) quarto_bin <- conda_q
}
qmd <- file.path(PROJECT_ROOT, "reports", "stage6_inferential_analysis.qmd")
rendered <- FALSE
if (nzchar(quarto_bin) && file.exists(quarto_bin) && file.exists(qmd)) {
  deno <- file.path(dirname(quarto_bin), "tools", "x86_64", "deno")
  if (file.exists(deno) || nzchar(Sys.which("deno"))) {
    status <- system2(
      quarto_bin,
      c("render", qmd, "--to", "html", "--output-dir", file.path(PROJECT_ROOT, "reports"))
    )
    rendered <- identical(as.integer(status), 0L)
  }
}
if (!rendered) {
  message("Quarto CLI not used; writing HTML from Stage 6 artifacts with R.")
  source(file.path(script_dir, "30_render_stage6_report.R"), local = FALSE)
}

message("Stage 6 complete. Aggregate artifacts: ", INFERENCE_DIR)
message("Person-level MI object (gitignored): ", file.path(INTERIM_STAGE6, "mice_mids.rds"))
