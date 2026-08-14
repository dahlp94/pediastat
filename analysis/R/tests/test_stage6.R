# Stage 6 validation of the frozen inferential execution.

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

spec <- yaml::read_yaml(file.path(root, "config", "model_spec.yaml"))
inf_dir <- file.path(root, "artifacts", "inference")
source(file.path(root, "analysis", "R", "10_model_coding.R"), local = FALSE)
source(file.path(root, "analysis", "R", "11_preflight.R"), local = FALSE)
source(file.path(root, "analysis", "R", "25_nonlinear_sensitivity.R"), local = FALSE)

test_that("frozen cohort accounting is unchanged", {
  spec_text <- paste(readLines(file.path(root, "config", "model_spec.yaml"), warn = FALSE), collapse = "\n")
  expect_match(spec_text, "n: 1978")
  expect_equal(unname(unlist(spec$cohort[["deaths"]])), 695)
  expect_equal(unname(unlist(spec$cohort[["censored"]])), 1283)
})

test_that("age5 and log2_wbc coding remain frozen", {
  expect_equal(age5(10), 2)
  expect_equal(log2_wbc(8), 3)
  expect_true(is.na(log2_wbc(0)))
  expect_true(all(log2_wbc(c(1, 2, 4, 8)) == c(0, 1, 2, 3)))
})

test_that("references remain Female, Low, and No", {
  expect_equal(spec$coding$sex$reference, "Female")
  expect_equal(spec$coding$risk_group$reference, "Low")
  expect_equal(spec$coding$yes_no$reference, "No")
})

test_that("principal formulas are unchanged and contain no interactions", {
  expect_equal(
    spec$primary_model$formula,
    "Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std"
  )
  expect_false(grepl("risk_group", spec$secondary_model$formula, fixed = TRUE))
  expect_false(grepl("\\*|:", spec$primary_model$formula))
  expect_false(grepl("\\*|:", spec$secondary_model$formula))
  expect_length(spec$primary_model$interactions, 0)
  expect_length(spec$secondary_model$interactions, 0)
})

test_that("MI does not impute ID, outcome, age, or sex", {
  forbidden <- unlist(spec$missing_data$do_not_impute, use.names = FALSE)
  expect_true(all(c(
    "analysis_person_id", "os_event", "os_days", "age5", "sex_std"
  ) %in% forbidden))
  expect_equal(spec$missing_data$m, 30)
  expect_equal(spec$missing_data$seed, 20260814)
  expect_equal(spec$missing_data$methods$log2_wbc, "pmm")
  expect_equal(spec$missing_data$methods$risk_group_std, "polyreg")
})

test_that("FDR family is the frozen biological set", {
  family <- unlist(spec$multiplicity$secondary$fdr_family, use.names = FALSE)
  expect_equal(family, c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  ))
  expect_false(any(c("age5", "sex_std", "log2_wbc") %in% family))
})

test_that("restricted cubic spline basis has 3 frozen knots", {
  b <- rcs_basis(c(1.14, 9.48, 16.57), c(1.14, 9.48, 16.57))
  expect_equal(ncol(b), 2)
  expect_equal(unname(as.numeric(b[1, "z2"])), 0, tolerance = 1e-8)
})

test_that("KM policy remains limited to risk group and FLT3", {
  expect_equal(
    unlist(spec$stratified_km$allowed, use.names = FALSE),
    c("risk_group_std", "flt3_itd_std")
  )
  expect_false(isTRUE(spec$stratified_km$log_rank_required))
})

skip_if_no_artifacts <- function() {
  if (!file.exists(file.path(inf_dir, "primary_cox_mi.csv"))) {
    skip("Stage 6 artifacts have not been generated")
  }
}

test_that("pooled primary table has expected terms and HR = exp(beta)", {
  skip_if_no_artifacts()
  tbl <- utils::read.csv(file.path(inf_dir, "primary_cox_mi.csv"), stringsAsFactors = FALSE)
  expect_equal(tbl$term, c(
    "age5", "sex_stdMale", "log2_wbc",
    "risk_group_stdStandard", "risk_group_stdHigh"
  ))
  expect_equal(tbl$hr, exp(tbl$beta), tolerance = 1e-8)
  expect_true(all(is.finite(tbl$hr)))
  expect_true(all(is.finite(tbl$hr_lcl)))
  expect_true(all(is.finite(tbl$hr_ucl)))
  expect_equal(unique(tbl$n_imputations), 30)
  expect_false(any(grepl("flt3|npm|cebpa|cytogenetics", tbl$term)))
})

test_that("pooled secondary table excludes risk group and has BH q-values", {
  skip_if_no_artifacts()
  tbl <- utils::read.csv(file.path(inf_dir, "secondary_cox_mi.csv"), stringsAsFactors = FALSE)
  expect_false(any(grepl("risk_group", tbl$term)))
  expect_true(all(c(
    "flt3_itd_stdYes", "npm_stdYes", "cebpa_stdYes",
    "cytogenetics_t821_stdYes", "cytogenetics_inv16_stdYes",
    "cytogenetics_mll_stdYes", "cytogenetics_monosomy7_stdYes"
  ) %in% tbl$term))
  adj <- tbl$term %in% c("age5", "sex_stdMale", "log2_wbc")
  expect_true(all(is.na(tbl$q_value[adj])))
  expect_true(all(!is.na(tbl$q_value[!adj])))
  expect_true(all(tbl$q_value[!adj] >= tbl$p_value[!adj] - 1e-12))
})

test_that("complete-case tables keep the same terms", {
  skip_if_no_artifacts()
  mi <- utils::read.csv(file.path(inf_dir, "primary_cox_mi.csv"), stringsAsFactors = FALSE)
  cc <- utils::read.csv(file.path(inf_dir, "primary_cox_complete_case.csv"), stringsAsFactors = FALSE)
  expect_equal(cc$term, mi$term)
  expect_true(cc$n[[1]] < 1978)
  expect_true(cc$n[[1]] > 1500)
})

test_that("metadata records frozen execution settings", {
  skip_if_no_artifacts()
  meta <- jsonlite::fromJSON(file.path(inf_dir, "model_metadata.json"))
  expect_equal(as.integer(unlist(meta$cohort_n)[1]), 1978L)
  expect_equal(meta$deaths, 695)
  expect_equal(meta$m, 30)
  expect_equal(meta$seed, 20260814)
  expect_equal(meta$ties, "efron")
  expect_false(isTRUE(meta$patient_level_data_included))
  expect_false(grepl("risk_group", meta$secondary_formula, fixed = TRUE))
})

test_that("committed inference artifacts do not contain patient identifiers", {
  skip_if_no_artifacts()
  files <- list.files(inf_dir, recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("\\.png$", files, ignore.case = TRUE)]
  files <- files[!grepl("\\.rds$", files, ignore.case = TRUE)]
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    expect_false(grepl("analysis_person_id", txt), info = f)
    expect_false(grepl("TARGET-2[01]-[A-Z0-9]{6}", txt), info = f)
  }
})

test_that("only the frozen KM predictors were plotted", {
  skip_if_no_artifacts()
  km <- utils::read.csv(file.path(inf_dir, "stratified_km_estimates.csv"), stringsAsFactors = FALSE)
  expect_true(all(km$variable %in% c("risk_group_std", "flt3_itd_std")))
  notes <- jsonlite::fromJSON(file.path(inf_dir, "analysis_notes.json"))
  expect_false(isTRUE(notes$km$log_rank))
})
