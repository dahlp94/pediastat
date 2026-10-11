# Validation of the frozen inferential execution.

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
source(file.path(root, "analysis", "R", "model_setup.R"), local = FALSE)
source(file.path(root, "analysis", "R", "imputation.R"), local = FALSE)
source(file.path(root, "analysis", "R", "models.R"), local = FALSE)
source(file.path(root, "analysis", "R", "diagnostics.R"), local = FALSE)

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

test_that("saved MICE reuse requires identical data and planned settings", {
  dat <- data.frame(
    os_days = c(12, 8, 19),
    os_event = c(1L, 0L, 1L),
    log2_wbc = c(1, NA_real_, 3)
  )
  coded <- data.frame(analysis_person_id = c("case-a", "case-b", "case-c"))
  meth <- c(os_days = "", os_event = "", log2_wbc = "pmm")
  pred <- matrix(0L, nrow = 3L, ncol = 3L,
                 dimnames = list(names(dat), names(dat)))
  pred["log2_wbc", "os_event"] <- 1L
  fake <- structure(
    list(data = dat, m = 30L, iteration = 20L, seed = 20260814L),
    class = "mids"
  )
  attr(fake, "pediastat_cache_settings") <- mice_cache_settings(meth, pred, spec, coded)
  expect_silent(assert_saved_mids_compatible(fake, dat, meth, pred, spec, coded))

  # The provenance attribute must survive persistence to disk.
  path <- tempfile(fileext = ".rds")
  saveRDS(fake, path)
  reloaded <- readRDS(path)
  unlink(path)
  expect_silent(assert_saved_mids_compatible(reloaded, dat, meth, pred, spec, coded))

  changed_data <- dat
  changed_data$log2_wbc[1] <- 2
  expect_error(
    assert_saved_mids_compatible(fake, changed_data, meth, pred, spec, coded),
    "data differ"
  )
  expect_error(
    assert_saved_mids_compatible(fake, dat[3:1, ], meth, pred, spec, coded),
    "data differ"
  )

  reordered_people <- coded[3:1, , drop = FALSE]
  expect_error(
    assert_saved_mids_compatible(fake, dat, meth, pred, spec, reordered_people),
    "settings or patient identities differ"
  )
  changed_people <- coded
  changed_people$analysis_person_id[1] <- "another-case"
  expect_error(
    assert_saved_mids_compatible(fake, dat, meth, pred, spec, changed_people),
    "settings or patient identities differ"
  )

  changed_method <- meth
  changed_method["log2_wbc"] <- "norm"
  expect_error(
    assert_saved_mids_compatible(fake, dat, changed_method, pred, spec, coded),
    "settings or patient identities differ"
  )
  changed_pred <- pred
  changed_pred["log2_wbc", "os_event"] <- 0L
  expect_error(
    assert_saved_mids_compatible(fake, dat, meth, changed_pred, spec, coded),
    "settings or patient identities differ"
  )
  changed_spec <- spec
  changed_spec$missing_data$seed <- 1L
  expect_error(
    assert_saved_mids_compatible(fake, dat, meth, pred, changed_spec, coded),
    "settings or patient identities differ"
  )

  old_cache <- fake
  attr(old_cache, "pediastat_cache_settings") <- NULL
  expect_error(
    assert_saved_mids_compatible(old_cache, dat, meth, pred, spec, coded),
    "settings or patient identities differ"
  )
  wrong_iteration <- fake
  wrong_iteration$iteration <- 10L
  expect_error(
    assert_saved_mids_compatible(wrong_iteration, dat, meth, pred, spec, coded),
    "execution settings"
  )
  wrong_count <- fake
  wrong_count$m <- 29L
  expect_error(
    assert_saved_mids_compatible(wrong_count, dat, meth, pred, spec, coded),
    "execution settings"
  )
  expect_error(
    assert_saved_mids_compatible(list(data = dat), dat, meth, pred, spec, coded),
    "not a mids object"
  )
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

test_that("MI vs complete-case labels require comparable point estimates", {
  terms <- c(
    "age5", "sex_stdMale", "log2_wbc",
    "risk_group_stdStandard", "risk_group_stdHigh"
  )
  mi <- data.frame(
    term = terms,
    predictor_label = terms,
    hr = c(0.50, 1.30, 0.99, 1.20, 1.40),
    hr_lcl = c(0.20, 1.10, 0.80, 1.00, 1.10),
    hr_ucl = c(1.20, 1.60, 1.20, 1.40, 2.00),
    p_value = rep(0.3, length(terms))
  )
  cc <- data.frame(
    term = terms,
    hr = c(2.00, 1.38, 1.01, 1.42, 2.00),
    hr_lcl = c(0.80, 1.15, 0.80, 1.00, 1.20),
    hr_ucl = c(5.00, 1.65, 1.30, 1.70, 2.80),
    p_value = rep(0.3, length(terms)),
    n = rep(1861L, length(terms)),
    deaths = rep(650L, length(terms))
  )
  comparison <- mi_cc_comparison(mi, cc)
  expect_equal(comparison$term, terms)
  expect_equal(comparison$qualitative, c(
    "meaningfully different", # Both CIs include 1, but HRs reverse direction
    "similar",               # Same direction and under 15% apart
    "uncertain",             # Near-null direction flip, estimates close
    "uncertain",             # Same direction, between 15% and 25% apart
    "meaningfully different"  # At least 25% apart
  ))
  expect_false(comparison$direction_same[[1]])
  expect_equal(comparison$hr_ratio_cc_over_mi[[1]], 4)
})

test_that("Cox influence threshold applies to DFBETAS, while retaining DFBETA", {
  set.seed(27)
  n <- 120L
  age5_values <- stats::runif(n, 0.1, 3.5)
  sex_values <- factor(
    sample(c("Female", "Male"), n, replace = TRUE),
    levels = c("Female", "Male")
  )
  event_time <- stats::rexp(n, rate = exp(0.25 * age5_values) / 110)
  censor_time <- stats::rexp(n, rate = 1 / 140)
  dat <- data.frame(
    analysis_person_id = sprintf("synthetic_%03d", seq_len(n)),
    os_days = pmin(event_time, censor_time),
    os_event = as.integer(event_time <= censor_time),
    age5 = age5_values,
    sex_std = sex_values
  )
  fit <- survival::coxph(
    survival::Surv(os_days, os_event) ~ age5 + sex_std,
    data = dat, ties = "efron", x = TRUE, y = TRUE, model = TRUE
  )
  result <- influence_summary_from_fit(fit, dat, "synthetic")
  raw <- as.matrix(stats::residuals(fit, type = "dfbeta"))
  scaled <- as.matrix(stats::residuals(fit, type = "dfbetas"))
  threshold <- 2 / sqrt(n)

  expect_equal(result$summary$max_abs_dfbeta, unname(apply(abs(raw), 2, max)))
  expect_equal(result$summary$max_abs_dfbetas, unname(apply(abs(scaled), 2, max)))
  expect_equal(result$summary$dfbetas_threshold_2_over_sqrt_n,
               rep(threshold, ncol(scaled)))
  expect_equal(result$summary$n_exceeding_threshold,
               as.integer(colSums(abs(scaled) > threshold)))
  expect_equal(result$person$max_abs_dfbeta, unname(apply(abs(raw), 1, max)))
  expect_equal(result$person$max_abs_dfbetas, unname(apply(abs(scaled), 1, max)))
  expect_identical(result$person$analysis_person_id, dat$analysis_person_id)
  expect_equal(nrow(result$person), n)
})

test_that("every principal MI Cox fit must keep all patients and deaths", {
  set.seed(42)
  n <- 80L
  dat <- data.frame(
    os_days = seq_len(n),
    os_event = rep(c(1L, 0L, 1L, 1L, 0L), length.out = n),
    age5 = stats::runif(n, 0.5, 3.5)
  )
  form <- survival::Surv(os_days, os_event) ~ age5
  fit_full <- survival::coxph(form, data = dat, ties = "efron")
  deaths <- sum(dat$os_event)
  expect_equal(fit_full$n, n)
  expect_equal(fit_full$nevent, deaths)

  mira <- list(analyses = rep(list(fit_full), 30L))
  expect_silent(assert_mi_cox_counts(mira, "synthetic", n, deaths))

  # One omitted censored patient must still stop pooling.
  dropped <- dat
  dropped$age5[n] <- NA_real_
  with_missing <- mira
  with_missing$analyses[[17L]] <- survival::coxph(form, data = dropped, ties = "efron")
  expect_error(
    assert_mi_cox_counts(with_missing, "synthetic", n, deaths),
    "synthetic imputation 17: fitted n=79, deaths=48"
  )

  # Changing an observed death without changing N must also stop pooling.
  changed_event <- dat
  changed_event$os_event[[1]] <- 0L
  with_event_change <- mira
  with_event_change$analyses[[4L]] <- survival::coxph(
    form, data = changed_event, ties = "efron"
  )
  expect_error(
    assert_mi_cox_counts(with_event_change, "synthetic", n, deaths),
    "synthetic imputation 4: fitted n=80, deaths=47"
  )

  # The declared m must match the number of fitted analyses.
  expect_error(
    assert_mi_cox_counts(list(analyses = mira$analyses[-1L]), "synthetic", n, deaths),
    "expected 30 imputed Cox fits; found 29"
  )
})

test_that("principal MI Cox fits require estimable coefficients and record warnings", {
  set.seed(170)
  n <- 100L
  dat <- data.frame(
    os_days = stats::rexp(n, rate = 0.02) + 1,
    os_event = rep(c(1L, 0L, 1L, 1L), length.out = n),
    age5 = stats::runif(n, 0.2, 3.5),
    sex_std = factor(rep(c("Female", "Male"), length.out = n),
                     levels = c("Female", "Male"))
  )
  fit <- fit_cox_one(dat, survival::Surv(os_days, os_event) ~ age5 + sex_std)
  terms <- c("age5", "sex_stdMale")
  expect_identical(names(stats::coef(fit)), terms)
  expect_true(isTRUE(attr(fit, "estimable", exact = TRUE)))
  expect_identical(attr(fit, "warnings", exact = TRUE), character())

  fits <- list(analyses = rep(list(fit), 3L))
  expect_silent(assert_mi_cox_estimable(fits, "synthetic", terms))
  empty <- cox_warning_summary(fits, "synthetic")
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty), c("model", "imputation", "warning"))

  bad_coef <- fits
  bad_coef$analyses[[2]]$coefficients[[1]] <- NA_real_
  expect_error(assert_mi_cox_estimable(bad_coef, "synthetic", terms),
               "synthetic imputation 2: non-finite Cox coefficient")

  bad_var <- fits
  bad_var$analyses[[3]]$var[1, 1] <- Inf
  expect_error(assert_mi_cox_estimable(bad_var, "synthetic", terms),
               "synthetic imputation 3: invalid Cox coefficient covariance")

  bad_terms <- fits
  expect_error(assert_mi_cox_estimable(bad_terms, "synthetic", rev(terms)),
               "unexpected coefficient terms")

  warned <- fits
  attr(warned$analyses[[2]], "warnings") <- "synthetic convergence warning"
  log <- cox_warning_summary(warned, "synthetic")
  expect_equal(nrow(log), 1L)
  expect_equal(log$model, "synthetic")
  expect_equal(log$imputation, 2L)
  expect_match(log$warning, "synthetic convergence warning")
  expect_error(assert_mi_cox_estimable(warned, "synthetic", terms),
               "synthetic imputation 2: Cox fitting warning")
})

test_that("PH figure contains panels for every term in one PNG", {
  set.seed(814)
  n <- 250L
  dat <- data.frame(
    os_days = stats::rexp(n, rate = 0.015) + 1,
    os_event = rep(c(1L, 1L, 0L, 1L), length.out = n),
    age5 = stats::runif(n, 0.2, 3.5),
    sex_std = factor(sample(c("Female", "Male"), n, replace = TRUE),
                     levels = c("Female", "Male")),
    log2_wbc = stats::runif(n, 1, 8),
    risk_group_std = factor(sample(c("Low", "Standard", "High"), n, replace = TRUE),
                            levels = c("Low", "Standard", "High"))
  )
  for (nm in c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )) {
    dat[[nm]] <- factor(sample(c("No", "Yes"), n, replace = TRUE),
                        levels = c("No", "Yes"))
  }

  output_dir <- tempfile("zph_panels_")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)
  png_dimensions <- function(path) {
    header <- readBin(path, what = "raw", n = 24L)
    expect_identical(as.integer(header[1:8]), c(137L, 80L, 78L, 71L, 13L, 10L, 26L, 10L))
    get_dim <- function(start) sum(as.integer(header[start:(start + 3L)]) * 256^(3:0))
    c(width = get_dim(17L), height = get_dim(21L))
  }

  for (case in list(
    list(formula = PRIMARY_FORMULA, terms = 4L, width = 2400L, height = 1950L),
    list(formula = SECONDARY_FORMULA, terms = 10L, width = 3600L, height = 3750L)
  )) {
    fit <- survival::coxph(case$formula, data = dat, ties = "efron", x = TRUE)
    expect_equal(ncol(survival::cox.zph(fit)$y), case$terms)
    filename <- sprintf("test_%s_terms.png", case$terms)
    path <- save_zph_plot(fit, filename, "Synthetic PH panel test", output_dir = output_dir)
    expect_true(file.exists(path))
    expect_gt(file.info(path)$size, 1000)
    expect_equal(unname(png_dimensions(path)), c(case$width, case$height))
  }
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
    skip("Inference artifacts have not been generated")
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
