# Focused checks for the optional 20-versus-100 iteration comparison.
# These tests use synthetic inputs and do not run MICE.

find_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) {
    return(get("PROJECT_ROOT", inherits = TRUE))
  }
  here::here()
}

root <- find_root()
source(
  file.path(root, "analysis", "R", "run_mice_iteration_sensitivity.R"),
  local = FALSE
)

pooled_table <- function(model, terms, beta, hr_lcl, hr_ucl, q, hr = NULL) {
  if (is.null(hr)) {
    hr <- exp(beta)
  }
  data.frame(
    model = model,
    term = terms,
    predictor_label = terms,
    beta = beta,
    se = rep(0.1, length(terms)),
    hr = hr,
    hr_lcl = hr_lcl,
    hr_ucl = hr_ucl,
    p_value = rep(0.01, length(terms)),
    q_value = q,
    fmi = rep(0.05, length(terms)),
    stringsAsFactors = FALSE
  )
}

baseline_comparison <- function() {
  primary_beta <- c(0.10, -0.20, 0.30, 0.40, 0.50)
  secondary_beta <- c(0.10, -0.20, 0.30, 0.05, -0.40, -0.50, -0.60, -0.70, 0.02, 0.80)
  primary20 <- pooled_table(
    "primary_clinical",
    PRIMARY_TERM_ORDER,
    primary_beta,
    hr_lcl = c(1.05, 0.70, 1.10, 1.20, 1.30),
    hr_ucl = c(1.20, 0.95, 1.60, 1.80, 2.00),
    q = rep(NA_real_, 5)
  )
  secondary_q <- rep(NA_real_, 10)
  secondary_q[4:10] <- c(0.90, 0.01, 0.04, 0.05, 0.20, 0.80, 0.001)
  secondary20 <- pooled_table(
    "secondary_molecular",
    SECONDARY_TERM_ORDER,
    secondary_beta,
    hr_lcl = c(1.02, 0.60, 1.05, 0.80, 0.50, 0.40, 0.30, 0.20, 0.70, 1.10),
    hr_ucl = c(1.30, 0.90, 1.50, 1.20, 0.80, 0.70, 0.60, 0.50, 1.10, 2.00),
    q = secondary_q
  )
  primary100 <- primary20
  primary100$beta[1] <- 0.12
  primary100$hr <- exp(primary100$beta)
  secondary100 <- secondary20
  secondary100$beta[2] <- 0.05
  secondary100$hr <- exp(secondary100$beta)
  secondary100$hr_lcl[4] <- 1.05
  secondary100$hr_ucl[4] <- 1.40
  secondary100$q_value[6] <- 0.06
  build_iteration_comparison(primary20, secondary20, primary100, secondary100)
}

fake_chain <- function(iterations, fill = 0) {
  array(
    fill,
    dim = c(2L, iterations, 2L),
    dimnames = list(
      c("log2_wbc", "risk_group_std"),
      as.character(seq_len(iterations)),
      c("1", "2")
    )
  )
}

fake_mids <- function(iteration, chain_mean, chain_var, data, where,
                      seed = 20260814L, call = NULL) {
  if (is.null(call)) {
    call <- if (iteration == 100L) {
      quote(mice::mice.mids(obj = imp20, maxit = 80L, printFlag = FALSE))
    } else {
      quote(mice::mice(
        data = mi_frame, m = 30L, maxit = 20L, seed = 20260814L, printFlag = FALSE
      ))
    }
  }
  structure(
    list(
      data = data,
      m = 30L,
      iteration = iteration,
      seed = seed,
      where = where,
      method = c(log2_wbc = "pmm", risk_group_std = "polyreg"),
      predictorMatrix = matrix(
        c(0, 1, 0, 0),
        nrow = 2,
        dimnames = list(c("log2_wbc", "risk_group_std"), c("log2_wbc", "risk_group_std"))
      ),
      visitSequence = c("log2_wbc", "risk_group_std"),
      call = call,
      chainMean = chain_mean,
      chainVar = chain_var
    ),
    class = "mids"
  )
}

continuation_pair <- function(alter = identity) {
  data <- data.frame(log2_wbc = c(1, NA_real_), risk_group_std = c(NA, "Low"))
  where <- is.na(data)
  mean20 <- fake_chain(20L, 1)
  var20 <- fake_chain(20L, 2)
  mean100 <- fake_chain(100L, 0)
  var100 <- fake_chain(100L, 0)
  mean100[, seq_len(20L), ] <- mean20
  var100[, seq_len(20L), ] <- var20
  mean100[, 21L, ] <- 9
  pair <- list(
    imp20 = fake_mids(20L, mean20, var20, data, where),
    imp100 = fake_mids(100L, mean100, var100, data, where)
  )
  alter(pair)
}

test_that("relative HR change and log-HR shift use the recorded definitions", {
  fit20 <- pooled_table(
    "secondary_molecular",
    "cebpa_stdYes",
    beta = -1.64083573953726,
    hr = 0.193817993224949,
    hr_lcl = 0.11540152785636,
    hr_ucl = 0.325519212748239,
    q = 2.16321022960875e-09
  )
  fit100 <- pooled_table(
    "secondary_molecular",
    "cebpa_stdYes",
    beta = -1.66492529994414,
    hr = 0.189204791062567,
    hr_lcl = 0.11,
    hr_ucl = 0.32,
    q = 1.57204580984859e-09
  )
  comparison <- join_iteration_cox(fit20, fit100)
  expect_equal(comparison$hr_change_pct, -2.38017228721789, tolerance = 1e-9)
  expect_equal(comparison$abs_log_hr_shift, 0.0240895604068805, tolerance = 1e-9)
  expect_false(comparison$direction_changed)
  expect_false(comparison$ci_null_status_changed)
  expect_false(comparison$bh_decision_changed)
})

test_that("direction, CI null status, and BH decisions are explicit", {
  fit20 <- pooled_table(
    "secondary_molecular",
    c("age5", "flt3_itd_stdYes"),
    beta = c(-0.2, 0.1),
    hr_lcl = c(0.70, 0.80),
    hr_ucl = c(0.90, 1.20),
    q = c(NA_real_, 0.04)
  )
  fit100 <- fit20
  fit100$beta <- c(0.1, 0.1)
  fit100$hr <- exp(fit100$beta)
  fit100$hr_lcl <- c(0.70, 1.05)
  fit100$hr_ucl <- c(0.90, 1.40)
  fit100$q_value <- c(NA_real_, 0.05)
  comparison <- join_iteration_cox(fit20, fit100)

  expect_true(comparison$direction_changed[1])
  expect_false(comparison$direction_changed[2])
  expect_false(comparison$ci_null_status_changed[1])
  expect_true(comparison$ci_excludes_1_100[2])
  expect_true(comparison$ci_null_status_changed[2])
  expect_true(is.na(comparison$bh_decision_changed[1]))
  expect_false(comparison$bh_decision_changed[2])
  expect_true(comparison$bh_rejects_0.05_20[2])
  expect_true(comparison$bh_rejects_0.05_100[2])

  fit100$q_value[2] <- 0.0500001
  crossed <- join_iteration_cox(fit20, fit100)
  expect_true(crossed$bh_decision_changed[2])
})

test_that("comparison validation requires 15 finite terms and seven BH tests", {
  comparison <- baseline_comparison()
  expect_silent(validate_iteration_comparison(comparison))
  expect_false(any(FORBIDDEN_COMPARISON_COLUMNS %in% names(comparison)))

  short <- comparison[-1, , drop = FALSE]
  expect_error(validate_iteration_comparison(short), "15 unique")

  nonfinite <- comparison
  nonfinite$hr_100[1] <- NA_real_
  expect_error(validate_iteration_comparison(nonfinite), "non-finite")

  missing_test <- comparison
  missing_test$q_value_20[comparison$term == "cebpa_stdYes"] <- NA_real_
  expect_error(validate_iteration_comparison(missing_test), "Biological BH")

  extra_q <- comparison
  extra_q$q_value_20[comparison$term == "age5" & comparison$model == "primary_clinical"] <- 0.01
  extra_q$bh_rejects_0.05_20 <- bh_rejects(extra_q$q_value_20)
  extra_q$bh_decision_changed <- ifelse(
    is.na(extra_q$bh_rejects_0.05_20) | is.na(extra_q$bh_rejects_0.05_100),
    NA,
    extra_q$bh_rejects_0.05_20 != extra_q$bh_rejects_0.05_100
  )
  expect_error(validate_iteration_comparison(extra_q), "outside the seven")
})

test_that("extended MICE object must continue the 20-iteration chains", {
  pair <- continuation_pair()
  expect_silent(assert_extended_mids_is_continuation(pair$imp20, pair$imp100))

  wrong_iteration <- pair
  wrong_iteration$imp100$iteration <- 80L
  expect_error(
    assert_extended_mids_is_continuation(wrong_iteration$imp20, wrong_iteration$imp100),
    "iterations"
  )

  wrong_seed <- pair
  wrong_seed$imp100$seed <- 1L
  expect_error(
    assert_extended_mids_is_continuation(wrong_seed$imp20, wrong_seed$imp100),
    "seed"
  )

  different_data <- pair
  different_data$imp100$data$log2_wbc[1] <- 2
  different_data$imp100$where <- is.na(different_data$imp100$data)
  expect_error(
    assert_extended_mids_is_continuation(different_data$imp20, different_data$imp100),
    "imputation data"
  )

  different_method <- pair
  different_method$imp100$method["log2_wbc"] <- "norm"
  expect_error(
    assert_extended_mids_is_continuation(different_method$imp20, different_method$imp100),
    "methods"
  )

  broken_history <- pair
  broken_history$imp100$chainMean[, 5, 1] <- 99
  expect_error(
    assert_extended_mids_is_continuation(broken_history$imp20, broken_history$imp100),
    "chain history"
  )

  not_a_continuation <- pair
  not_a_continuation$imp100$call <- quote(mice::mice(data = mi_frame, maxit = 100L))
  expect_error(
    assert_extended_mids_is_continuation(
      not_a_continuation$imp20, not_a_continuation$imp100
    ),
    "mice.mids"
  )
})

test_that("reproduced 20-iteration estimates must match the published Cox table", {
  published <- pooled_table(
    "primary_clinical",
    "age5",
    beta = 0.112820751085854,
    hr_lcl = 1.0454231936934,
    hr_ucl = 1.19867853442486,
    q = NA_real_
  )
  published$hr <- 1.11943125812627
  path <- tempfile(fileext = ".csv")
  utils::write.csv(published, path, row.names = FALSE, na = "")
  on.exit(unlink(path), add = TRUE)

  expect_silent(assert_published_cox_agreement(published, path, "primary_clinical"))

  shifted <- published
  shifted$beta <- shifted$beta + 0.01
  shifted$hr <- exp(shifted$beta)
  expect_error(
    assert_published_cox_agreement(shifted, path, "primary_clinical"),
    "differ from"
  )
})

test_that("local comparison differences are reported without rewriting estimates", {
  comparison <- baseline_comparison()
  original <- comparison
  reference <- comparison
  reference$hr_change_pct[1] <- reference$hr_change_pct[1] + 0.02
  reference$direction_changed[2] <- !reference$direction_changed[2]
  differences <- local_comparison_differences(comparison, reference)

  expect_true(any(differences$substantive & differences$column == "hr_change_pct"))
  expect_true(any(differences$substantive & differences$column == "direction_changed"))
  expect_equal(comparison$hr_change_pct, original$hr_change_pct)
  expect_equal(comparison$direction_changed, original$direction_changed)

  dust <- comparison
  dust$hr_change_pct[1] <- dust$hr_change_pct[1] + 1e-6
  dust_differences <- local_comparison_differences(comparison, dust)
  expect_gte(nrow(dust_differences), 1L)
  expect_false(any(dust_differences$substantive))
})

test_that("extended-object actions never target the primary MICE file", {
  expect_error(
    plan_extended_mids(FALSE, FALSE, FALSE),
    "Refusing to start mice::mice.mids"
  )
  expect_identical(plan_extended_mids(FALSE, TRUE, FALSE), "create")
  expect_identical(plan_extended_mids(TRUE, TRUE, FALSE), "load")
  expect_identical(plan_extended_mids(TRUE, FALSE, TRUE), "overwrite")

  primary <- file.path(tempdir(), PRIMARY_MIDS_NAME)
  extended <- file.path(tempdir(), EXTENDED_MIDS_NAME)
  expect_error(assert_extended_save_path(primary, primary), "primary MICE")
  expect_silent(assert_extended_save_path(extended, primary))
})
