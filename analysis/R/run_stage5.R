#!/usr/bin/env Rscript
# Stage 5 inferential-plan preflight. Reads the frozen cohort.
# Does not fit Cox models and does not run multiple imputation.

stage5_scripts <- c(
  "00_setup.R",
  "01_load_primary_cohort.R",
  "10_model_coding.R",
  "11_preflight.R"
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
for (script in stage5_scripts) {
  source(file.path(script_dir, script), local = FALSE)
}

load_stage4_packages()
ensure_output_dirs()
MODEL_PLAN_DIR <- file.path(PROJECT_ROOT, "artifacts", "model_plan")
dir.create(MODEL_PLAN_DIR, recursive = TRUE, showWarnings = FALSE)
INTERIM_STAGE5 <- file.path(PROJECT_ROOT, "data", "interim", "stage5")
dir.create(INTERIM_STAGE5, recursive = TRUE, showWarnings = FALSE)

con <- connect_pediastat()
on.exit(DBI::dbDisconnect(con), add = TRUE)

loaded <- load_primary_cohort(con)
spec <- load_model_spec_yaml()
coded <- code_inferential_cohort(loaded$cohort, spec)
preflight <- preflight_coded_cohort(coded, spec)

# Optional Nelson-Aalen auxiliary construction check. Not a prognostic Cox model.
coded$nelson_aalen <- nelson_aalen_cumulative_hazard(coded$os_days, coded$os_event)
if (any(!is.finite(coded$nelson_aalen))) {
  stop("Nelson-Aalen auxiliary has non-finite values.", call. = FALSE)
}
preflight$nelson_aalen_n_finite <- sum(is.finite(coded$nelson_aalen))
preflight$nelson_aalen_min <- min(coded$nelson_aalen)
preflight$nelson_aalen_max <- max(coded$nelson_aalen)
preflight$note <- paste(
  "Nelson-Aalen is a planned MI auxiliary. Person-level values are not committed.",
  "No Cox prognostic model was fit. No multiply imputed datasets were created."
)

write_preflight_artifact(preflight)
write_risk_token_resolution(coded)
write_lesion_verification(preflight)

saveRDS(coded, file.path(INTERIM_STAGE5, "coded_primary_cohort.rds"))

test_file <- file.path(script_dir, "tests", "test_stage5.R")
if (file.exists(test_file)) {
  results <- as.data.frame(testthat::test_file(test_file, reporter = "progress"))
  n_failed <- sum(results$failed, na.rm = TRUE) + sum(results$error, na.rm = TRUE)
  if (n_failed > 0) {
    stop("Stage 5 R tests failed.", call. = FALSE)
  }
}

message("Stage 5 model-plan preflight written to ", MODEL_PLAN_DIR)
message("Person-level coded extract (gitignored): ", file.path(INTERIM_STAGE5, "coded_primary_cohort.rds"))
