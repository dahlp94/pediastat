#!/usr/bin/env Rscript
# Stage 5 model-plan preflight. Reads the frozen cohort; fits no Cox model or MI.

stage5_scripts <- c(
  "setup.R",
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
for (script in stage5_scripts) source(file.path(script_dir, script), local = FALSE)

load_stage4_packages()
ensure_output_dirs()
MODEL_PLAN_DIR <- file.path(PROJECT_ROOT, "artifacts", "model_plan")
INTERIM_STAGE5 <- file.path(PROJECT_ROOT, "data", "interim", "stage5")
dir.create(MODEL_PLAN_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(INTERIM_STAGE5, recursive = TRUE, showWarnings = FALSE)

con <- connect_pediastat()
on.exit(DBI::dbDisconnect(con), add = TRUE)

loaded <- load_primary_cohort(con)
spec <- load_model_spec_yaml()
coded <- code_inferential_cohort(loaded$cohort, spec)
preflight <- preflight_coded_cohort(coded, spec)

# Retained for Stage 6 compatibility. This is an MI auxiliary, not a model fit.
coded$nelson_aalen <- nelson_aalen_cumulative_hazard(coded$os_days, coded$os_event)
if (any(!is.finite(coded$nelson_aalen))) {
  stop("Nelson-Aalen auxiliary has non-finite values.", call. = FALSE)
}
preflight$nelson_aalen_n_finite <- sum(is.finite(coded$nelson_aalen))
preflight$nelson_aalen_min <- min(coded$nelson_aalen)
preflight$nelson_aalen_max <- max(coded$nelson_aalen)
preflight$note <- paste(
  "Model coding and design matrices were validated.",
  "Nelson-Aalen is retained only as the planned MI auxiliary.",
  "No Cox model or multiple imputation was run."
)

write_preflight_artifact(preflight)
write_risk_token_resolution(coded)
write_lesion_verification(preflight)

coded_path <- file.path(INTERIM_STAGE5, "coded_primary_cohort.rds")
saveRDS(coded, coded_path)

test_file <- file.path(script_dir, "tests", "test_stage5.R")
if (file.exists(test_file)) {
  results <- as.data.frame(testthat::test_file(test_file, reporter = "progress"))
  n_failed <- sum(results$failed, na.rm = TRUE) + sum(results$error, na.rm = TRUE)
  if (n_failed > 0) stop("Stage 5 R tests failed.", call. = FALSE)
}

message("Stage 5 model-plan preflight written to ", MODEL_PLAN_DIR)
message("Person-level coded extract (gitignored): ", coded_path)
