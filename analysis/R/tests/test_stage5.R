# Stage 5 validation. No Cox models. No multiple-imputation runs.

find_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) {
    return(get("PROJECT_ROOT", inherits = TRUE))
  }
  here::here()
}

root <- find_root()
if (!exists("PROJECT_ROOT", inherits = TRUE)) {
  PROJECT_ROOT <- root
}

spec_path <- file.path(root, "config", "model_spec.yaml")
spec <- yaml::read_yaml(spec_path)
plan_dir <- file.path(root, "artifacts", "model_plan")

source(file.path(root, "analysis", "R", "10_model_coding.R"), local = FALSE)
source(file.path(root, "analysis", "R", "11_preflight.R"), local = FALSE)

test_that("age5 divides years by 5", {
  expect_equal(age5(10), 2)
  expect_equal(age5(c(0, 5, 15)), c(0, 1, 3))
})

test_that("log2_wbc is undefined for nonpositive WBC", {
  expect_equal(log2_wbc(8), 3)
  expect_true(is.na(log2_wbc(0)))
  expect_true(is.na(log2_wbc(-4)))
  expect_true(is.na(log2_wbc(NA_real_)))
})

test_that("Yes/No mixed case is harmonized", {
  coded <- standardize_yes_no(c("YES", "NO", "Yes", "Unknown", NA), spec)
  expect_equal(as.character(coded), c("Yes", "No", "Yes", NA, NA))
  expect_equal(levels(coded)[1], "No")
})

test_that("risk-group 10/30 become missing rather than guessed", {
  rg <- standardize_risk_group(c("Low Risk", "10", "30", "Unknown", "High Risk"), spec)
  expect_equal(as.character(rg$standardized), c("Low", NA, NA, NA, "High"))
  expect_equal(rg$qa_flag[2], "unresolved_risk_group_token")
  expect_equal(rg$qa_flag[3], "unresolved_risk_group_token")
  expect_equal(levels(rg$standardized)[1], "Low")
})

test_that("synthetic primary and secondary matrices are full rank", {
  n <- 80
  set.seed(5)
  yn <- function(p) {
    factor(ifelse(rbinom(n, 1, p) == 1, "Yes", "No"), levels = c("No", "Yes"))
  }
  dat <- data.frame(
    age5 = seq(0.2, 3.5, length.out = n),
    sex_std = factor(rep(c("Female", "Male"), length.out = n), levels = c("Female", "Male")),
    log2_wbc = log2(seq(1, 80, length.out = n)),
    risk_group_std = factor(
      rep(c("Low", "Standard", "High"), length.out = n),
      levels = c("Low", "Standard", "High")
    ),
    flt3_itd_std = yn(0.25),
    npm_std = yn(0.12),
    cebpa_std = yn(0.10),
    cytogenetics_t821_std = yn(0.15),
    cytogenetics_inv16_std = yn(0.12),
    cytogenetics_mll_std = yn(0.18),
    cytogenetics_monosomy7_std = yn(0.08)
  )
  primary <- design_matrix_rank(dat, ~ age5 + sex_std + log2_wbc + risk_group_std)
  secondary <- design_matrix_rank(
    dat,
    ~ age5 + sex_std + log2_wbc + flt3_itd_std + npm_std + cebpa_std +
      cytogenetics_t821_std + cytogenetics_inv16_std + cytogenetics_mll_std +
      cytogenetics_monosomy7_std
  )
  expect_true(primary$full_rank)
  expect_true(secondary$full_rank)
  expect_equal(primary$n_cols - 1L, spec$primary_model$df)
  expect_equal(secondary$n_cols - 1L, spec$secondary_model$df)
})

test_that("primary model excludes molecular components and secondary excludes risk group", {
  expect_true(grepl("risk_group_std", spec$primary_model$formula, fixed = TRUE))
  expect_false(grepl("flt3_itd_std", spec$primary_model$formula, fixed = TRUE))
  expect_false(grepl("risk_group", spec$secondary_model$formula, fixed = TRUE))
  expect_length(spec$primary_model$interactions, 0)
  expect_length(spec$secondary_model$interactions, 0)
})

test_that("MI specification does not impute outcome or ID", {
  expect_true("os_event" %in% spec$missing_data$do_not_impute)
  expect_true("os_days" %in% spec$missing_data$do_not_impute)
  expect_true("analysis_person_id" %in% spec$missing_data$do_not_impute)
  expect_false("os_event" %in% names(spec$missing_data$methods))
  expect_equal(spec$missing_data$m, 30)
})

test_that("FDR family is the frozen secondary biological set", {
  family <- unlist(spec$multiplicity$secondary$fdr_family, use.names = FALSE)
  expect_false("age5" %in% family)
  expect_false("sex_std" %in% family)
  expect_false("log2_wbc" %in% family)
  expect_true(all(c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  ) %in% family))
})

test_that("Stage 5 R scripts do not call Cox, mice, or log-rank", {
  scripts <- c(
    file.path(root, "analysis", "R", "10_model_coding.R"),
    file.path(root, "analysis", "R", "11_preflight.R"),
    file.path(root, "analysis", "R", "run_stage5.R"),
    file.path(root, "analysis", "R", "tests", "test_stage5.R")
  )
  for (script in scripts) {
    txt <- paste(readLines(script, warn = FALSE), collapse = "\n")
    expect_false(grepl("coxph\\s*\\(", txt), info = script)
    expect_false(grepl("mice\\s*\\(", txt), info = script)
    expect_false(grepl("survdiff\\s*\\(", txt), info = script)
    expect_false(grepl("cox\\.zph\\s*\\(", txt), info = script)
  }
})

test_that("model spec stores no results", {
  dumped <- paste(deparse(spec), collapse = " ")
  expect_false(grepl("hazard_ratio", dumped, ignore.case = TRUE))
})
