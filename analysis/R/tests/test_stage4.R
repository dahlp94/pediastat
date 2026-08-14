# Stage 4 validation. These tests inspect artifacts and analysis objects.
# They do not fit Cox models or compare predictors to survival.

EXPECTED_N <- 1978L
EXPECTED_DEATHS <- 695L
EXPECTED_CENSORED <- 1283L

find_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) {
    return(get("PROJECT_ROOT", inherits = TRUE))
  }
  here::here()
}

root <- find_root()
desc_dir <- file.path(root, "artifacts", "descriptive")

test_that("population accounting matches frozen Stage 3 identity counts", {
  acc <- jsonlite::fromJSON(file.path(desc_dir, "population_accounting.json"))
  expect_equal(acc$original_gdc_cases, 2492)
  expect_equal(acc$gdc_cases_valid_identity, 2354)
  expect_equal(acc$unique_valid_analysis_persons, 2315)
  expect_equal(acc$gdc_cases_ineligible_identity, 138)
  expect_equal(acc$cohort_eligibility_rows, 2453)
  expect_equal(acc$cohort_eligibility_valid_persons, 2315)
  expect_equal(acc$cohort_eligibility_ineligible_identity_records, 138)
  expect_match(acc$interpretation, "not valid analysis persons")
})

test_that("endpoint description matches frozen OS cohort", {
  endpoint <- jsonlite::fromJSON(file.path(desc_dir, "endpoint_followup_description.json"))
  expect_equal(endpoint$primary_cohort_n, EXPECTED_N)
  expect_equal(endpoint$deaths, EXPECTED_DEATHS)
  expect_equal(endpoint$censored, EXPECTED_CENSORED)
  expect_equal(endpoint$crude_event_percent, 35.14)
})

test_that("KM estimates are probabilities and requested times exist", {
  est <- utils::read.csv(file.path(desc_dir, "overall_survival_estimates.csv"))
  expect_true(all(est$survival >= 0 & est$survival <= 1))
  expect_true(all(c(1, 3, 5) %in% est$time_years))
  km_tidy_path <- file.path(desc_dir, "overall_survival_summary.json")
  expect_true(file.exists(km_tidy_path))
})

test_that("number at risk is present at 0, 1, 3, and 5 years", {
  nr <- utils::read.csv(file.path(desc_dir, "number_at_risk.csv"))
  expect_true(all(c(0, 1, 3, 5) %in% nr$time_years))
  expect_equal(nr$n_risk[nr$time_years == 0], EXPECTED_N)
})

test_that("Table 1 has no p-value column", {
  tbl <- utils::read.csv(file.path(desc_dir, "table1_primary_cohort.csv"), check.names = FALSE)
  expect_false(any(grepl("^p", names(tbl), ignore.case = TRUE)))
  expect_false(any(grepl("p.value|p-value|pvalue", names(tbl), ignore.case = TRUE)))
})

test_that("only an overall KM figure is produced", {
  figs <- list.files(file.path(desc_dir, "figures"), pattern = "\\.png$")
  expect_true("overall_kaplan_meier.png" %in% figs)
  stratified <- grepl(
    "by_risk|by_flt3|by_sex|by_age|by_wbc|by_fab|stratified|logrank",
    figs,
    ignore.case = TRUE
  )
  expect_false(any(stratified))
})

test_that("Stage 4 R scripts do not call Cox or log-rank", {
  r_dir <- file.path(root, "analysis", "R")
  scripts <- list.files(r_dir, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  for (script in scripts) {
    txt <- paste(readLines(script, warn = FALSE), collapse = "\n")
    expect_false(grepl("coxph\\s*\\(", txt), info = script)
    expect_false(grepl("survdiff\\s*\\(", txt), info = script)
  }
})
