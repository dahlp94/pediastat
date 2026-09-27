# Stage 5 validation. No Cox models or multiple-imputation runs.

find_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) return(get("PROJECT_ROOT", inherits = TRUE))
  here::here()
}

root <- find_root()
if (!exists("PROJECT_ROOT", inherits = TRUE)) PROJECT_ROOT <- root
spec <- yaml::read_yaml(file.path(root, "config", "model_spec.yaml"))

source(file.path(root, "analysis", "R", "10_model_coding.R"), local = FALSE)
source(file.path(root, "analysis", "R", "11_preflight.R"), local = FALSE)

test_that("continuous coding is prespecified", {
  expect_equal(age5(c(0, 5, 10, 15)), c(0, 1, 2, 3))
  expect_equal(log2_wbc(8), 3)
  expect_true(all(is.na(log2_wbc(c(0, -4, NA_real_)))))
})

test_that("categorical coding preserves explicit missingness", {
  yn <- standardize_yes_no(c("YES", "NO", "Yes", "Unknown", NA), spec)
  expect_equal(as.character(yn), c("Yes", "No", "Yes", NA, NA))
  expect_equal(levels(yn)[1], "No")

  risk <- standardize_risk_group(
    c("Low Risk", "10", "30", "Unknown", "High Risk"), spec
  )
  expect_equal(as.character(risk$standardized), c("Low", NA, NA, NA, "High"))
  expect_equal(risk$qa_flag[2:3], rep("unresolved_risk_group_token", 2))
  expect_equal(levels(risk$standardized)[1], "Low")
})

test_that("model terms come from model_spec.yaml", {
  primary <- primary_terms(spec)
  secondary <- secondary_terms(spec)
  expect_true("risk_group_std" %in% primary)
  expect_false(any(grepl("flt3|npm|cebpa|cytogenetics", primary)))
  expect_false("risk_group_std" %in% secondary)
  expect_length(spec$primary_model$interactions, 0)
  expect_length(spec$secondary_model$interactions, 0)
})

test_that("synthetic planned design matrices are full rank", {
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
    flt3_itd_std = yn(0.25), npm_std = yn(0.12), cebpa_std = yn(0.10),
    cytogenetics_t821_std = yn(0.15), cytogenetics_inv16_std = yn(0.12),
    cytogenetics_mll_std = yn(0.18), cytogenetics_monosomy7_std = yn(0.08)
  )
  primary <- design_matrix_rank(dat, model_formula(spec, "primary"))
  secondary <- design_matrix_rank(dat, model_formula(spec, "secondary"))
  expect_true(primary$full_rank)
  expect_true(secondary$full_rank)
  expect_equal(primary$n_cols - 1L, spec$primary_model$df)
  expect_equal(secondary$n_cols - 1L, spec$secondary_model$df)
})

test_that("MI and multiplicity decisions remain frozen in the spec", {
  expect_true(all(
    c("os_event", "os_days", "analysis_person_id") %in% spec$missing_data$do_not_impute
  ))
  expect_false("os_event" %in% names(spec$missing_data$methods))
  expect_equal(spec$missing_data$m, 30)

  family <- unlist(spec$multiplicity$secondary$fdr_family, use.names = FALSE)
  expect_false(any(c("age5", "sex_std", "log2_wbc") %in% family))
  expect_true(all(c(
    "flt3_itd_std", "npm_std", "cebpa_std", "cytogenetics_t821_std",
    "cytogenetics_inv16_std", "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  ) %in% family))
})

test_that("Stage 5 remains preflight rather than inference", {
  scripts <- c(
    file.path(root, "analysis", "R", "10_model_coding.R"),
    file.path(root, "analysis", "R", "11_preflight.R"),
    file.path(root, "analysis", "R", "run_stage5.R"),
    file.path(root, "analysis", "R", "tests", "test_stage5.R")
  )
  banned <- c("coxph\\s*\\(", "mice\\s*\\(", "survdiff\\s*\\(", "cox\\.zph\\s*\\(")
  for (script in scripts) {
    txt <- paste(readLines(script, warn = FALSE), collapse = "\n")
    for (pattern in banned) expect_false(grepl(pattern, txt), info = script)
  }
})

test_that("model spec contains design decisions, not results", {
  expect_false(grepl("hazard_ratio", paste(deparse(spec), collapse = " "), ignore.case = TRUE))
})
