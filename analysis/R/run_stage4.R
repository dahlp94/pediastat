#!/usr/bin/env Rscript
# Stage 4 descriptive workflow. Reads the frozen cohort. Does not fit Cox models.

stage4_scripts <- c(
  "00_setup.R",
  "01_load_primary_cohort.R",
  "02_baseline_descriptives.R",
  "03_missingness.R",
  "04_overall_survival.R",
  "05_followup.R",
  "06_generate_descriptive_outputs.R"
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
for (script in stage4_scripts) {
  source(file.path(script_dir, script), local = FALSE)
}

load_stage4_packages()
ensure_output_dirs()

con <- connect_pediastat()
on.exit(DBI::dbDisconnect(con), add = TRUE)

loaded <- load_primary_cohort(con)
extract_paths <- write_interim_extract(loaded$cohort)
message(
  "Loaded frozen primary cohort N=", nrow(loaded$cohort),
  " deaths=", loaded$checks$deaths,
  " censored=", loaded$checks$censored
)
message(loaded$accounting$interpretation)

descriptives <- run_baseline_descriptives(loaded$cohort)
missingness <- run_missingness(loaded$cohort, loaded$long_baseline)
km_result <- run_overall_survival(loaded$cohort)
followup <- run_followup(loaded$cohort, km_result)
provenance <- source_provenance_table(loaded$long_baseline)
redundancy <- run_redundancy(loaded$cohort)
outputs <- run_stage4_outputs(
  loaded, descriptives, missingness, km_result, followup, provenance, redundancy
)

test_file <- file.path(script_dir, "tests", "test_stage4.R")
if (file.exists(test_file)) {
  results <- as.data.frame(testthat::test_file(test_file, reporter = "progress"))
  n_failed <- sum(results$failed, na.rm = TRUE) + sum(results$error, na.rm = TRUE)
  if (n_failed > 0) {
    stop("Stage 4 R tests failed.", call. = FALSE)
  }
}

message("Stage 4 descriptive artifacts written to ", DESCRIPTIVE_DIR)
message("Person-level extract (gitignored): ", extract_paths$rds)
