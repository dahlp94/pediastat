# Restricted cubic spline sensitivity for age and log2 WBC.
# Knots are frozen Stage 4 quantiles. They are not moved using AIC or p-values.

rcs_basis <- function(x, knots) {
  k <- as.numeric(knots)
  if (length(k) != 3L) {
    stop("Stage 5 froze exactly 3 knots.", call. = FALSE)
  }
  k1 <- k[[1]]
  k2 <- k[[2]]
  k3 <- k[[3]]
  pos <- function(u) pmax(as.numeric(u), 0)
  z1 <- as.numeric(x)
  z2 <- pos(x - k1)^3 -
    pos(x - k2)^3 * (k3 - k1) / (k3 - k2) +
    pos(x - k3)^3 * (k2 - k1) / (k3 - k2)
  cbind(z1 = z1, z2 = z2)
}

add_age_spline <- function(dat, knots) {
  b <- rcs_basis(dat$age_at_diagnosis_years, knots)
  dat$age_rcs1 <- b[, "z1"]
  dat$age_rcs2 <- b[, "z2"]
  dat
}

add_wbc_spline <- function(dat, knots_log2) {
  b <- rcs_basis(dat$log2_wbc, knots_log2)
  dat$log2_wbc_rcs1 <- b[, "z1"]
  dat$log2_wbc_rcs2 <- b[, "z2"]
  dat
}

AGE_SPLINE_FORMULA <- stats::as.formula(
  "survival::Surv(os_days, os_event) ~ age_rcs1 + age_rcs2 + sex_std + log2_wbc + risk_group_std"
)
WBC_SPLINE_FORMULA <- stats::as.formula(
  "survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc_rcs1 + log2_wbc_rcs2 + risk_group_std"
)

wald_from_fit <- function(fit, terms) {
  cf <- coef(fit)
  V <- stats::vcov(fit)
  b <- cf[terms]
  v <- V[terms, terms, drop = FALSE]
  if (any(!is.finite(b)) || any(!is.finite(v))) {
    return(list(statistic = NA_real_, df = length(terms), p_value = NA_real_))
  }
  stat <- as.numeric(t(b) %*% solve(v) %*% b)
  df <- length(terms)
  p <- stats::pchisq(stat, df = df, lower.tail = FALSE)
  list(statistic = stat, df = df, p_value = p)
}

relative_hazard_curve <- function(fit, newdata, ref_row, coef_names) {
  cf <- coef(fit)
  keep <- intersect(coef_names, names(cf))
  mm_fun <- function(d) {
    mm <- stats::model.matrix(stats::reformulate(keep, intercept = FALSE), data = d)
    mm[, keep, drop = FALSE]
  }
  mm <- mm_fun(newdata)
  mm_ref <- mm_fun(ref_row)
  lp <- as.numeric(mm %*% cf[keep])
  lp_ref <- as.numeric(mm_ref %*% cf[keep])
  log_hr <- lp - lp_ref
  V <- stats::vcov(fit)[keep, keep, drop = FALSE]
  diff_mm <- mm - matrix(mm_ref, nrow = nrow(mm), ncol = length(keep), byrow = TRUE)
  se <- sqrt(pmax(0, rowSums((diff_mm %*% V) * diff_mm)))
  data.frame(
    log_hr = log_hr,
    se = se,
    hr = exp(log_hr),
    hr_lcl = exp(log_hr - 1.96 * se),
    hr_ucl = exp(log_hr + 1.96 * se),
    stringsAsFactors = FALSE
  )
}

plot_relative_hazard <- function(curve, x, xlab, title, subtitle, filename, x_trans = "identity") {
  d <- cbind(x = x, curve)
  p <- ggplot2::ggplot(d, ggplot2::aes(x = x, y = hr)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = hr_lcl, ymax = hr_ucl),
      fill = "#4C78A8",
      alpha = 0.2
    ) +
    ggplot2::geom_line(color = "#2F4B7C", linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "#666666") +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      x = xlab,
      y = "Relative hazard vs reference"
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
  if (identical(x_trans, "log2")) {
    p <- p + ggplot2::scale_x_continuous(trans = "log2")
  }
  save_inference_plot(p, filename, width = 2200, height = 1500)
}

run_nonlinear_sensitivity <- function(imp, coded, spec) {
  age_knots <- unlist(spec$nonlinear_sensitivity$age$knot_locations_years, use.names = FALSE)
  wbc_knots <- unlist(spec$nonlinear_sensitivity$wbc$knot_locations_wbc, use.names = FALSE)
  log2_knots <- log2(wbc_knots)
  age_ref <- age_knots[[2]]
  wbc_ref <- wbc_knots[[2]]

  age_mira <- fit_cox_across_imputations(
    imp,
    coded,
    AGE_SPLINE_FORMULA,
    mutate_fn = function(dat) add_age_spline(dat, age_knots)
  )
  wbc_mira <- fit_cox_across_imputations(
    imp,
    coded,
    WBC_SPLINE_FORMULA,
    mutate_fn = function(dat) add_wbc_spline(dat, log2_knots)
  )

  age_nl <- lapply(age_mira$analyses, function(fit) wald_from_fit(fit, "age_rcs2"))
  age_overall <- lapply(age_mira$analyses, function(fit) wald_from_fit(fit, c("age_rcs1", "age_rcs2")))
  wbc_nl <- lapply(wbc_mira$analyses, function(fit) wald_from_fit(fit, "log2_wbc_rcs2"))
  wbc_overall <- lapply(wbc_mira$analyses, function(fit) wald_from_fit(fit, c("log2_wbc_rcs1", "log2_wbc_rcs2")))

  pool_wald_median <- function(lst) {
    data.frame(
      statistic_median = stats::median(vapply(lst, `[[`, numeric(1), "statistic"), na.rm = TRUE),
      p_median = stats::median(vapply(lst, `[[`, numeric(1), "p_value"), na.rm = TRUE),
      p_min = min(vapply(lst, `[[`, numeric(1), "p_value"), na.rm = TRUE),
      p_max = max(vapply(lst, `[[`, numeric(1), "p_value"), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }

  cc_terms <- primary_terms()
  cc <- coded[stats::complete.cases(coded[, cc_terms, drop = FALSE]), , drop = FALSE]
  cc <- add_age_spline(cc, age_knots)
  cc <- add_wbc_spline(cc, log2_knots)
  age_cc <- fit_cox_one(cc, AGE_SPLINE_FORMULA)
  wbc_cc <- fit_cox_one(cc, WBC_SPLINE_FORMULA)

  age_grid <- data.frame(
    age_at_diagnosis_years = seq(0.2, 17.9, length.out = 80),
    sex_std = factor("Female", levels = levels(coded$sex_std)),
    log2_wbc = log2(wbc_ref),
    risk_group_std = factor("Low", levels = levels(coded$risk_group_std)),
    os_days = 1,
    os_event = 1L
  )
  age_grid <- add_age_spline(age_grid, age_knots)
  age_ref_row <- age_grid[which.min(abs(age_grid$age_at_diagnosis_years - age_ref)), , drop = FALSE]
  age_curve <- relative_hazard_curve(
    age_cc, age_grid, age_ref_row, c("age_rcs1", "age_rcs2")
  )
  plot_relative_hazard(
    age_curve,
    age_grid$age_at_diagnosis_years,
    "Age at diagnosis (years)",
    "Age functional-form sensitivity",
    sprintf(
      "Restricted cubic spline (3 knots). Reference = cohort median (%.2f years). Complete-case Cox; not a replacement for linear age5.",
      age_ref
    ),
    "age_spline_relative_hazard.png"
  )

  wbc_grid_vals <- exp(seq(log(1), log(400), length.out = 80))
  wbc_grid <- data.frame(
    age5 = age_ref / 5,
    sex_std = factor("Female", levels = levels(coded$sex_std)),
    log2_wbc = log2(wbc_grid_vals),
    risk_group_std = factor("Low", levels = levels(coded$risk_group_std)),
    os_days = 1,
    os_event = 1L
  )
  wbc_grid <- add_wbc_spline(wbc_grid, log2_knots)
  wbc_ref_row <- wbc_grid[which.min(abs(wbc_grid_vals - wbc_ref)), , drop = FALSE]
  wbc_curve <- relative_hazard_curve(
    wbc_cc, wbc_grid, wbc_ref_row, c("log2_wbc_rcs1", "log2_wbc_rcs2")
  )
  plot_relative_hazard(
    wbc_curve,
    wbc_grid_vals,
    "WBC at diagnosis (x10^3/mcL)",
    "WBC functional-form sensitivity",
    sprintf(
      "Restricted cubic spline of log2(WBC) (3 knots). Reference = cohort median (%.2f). Complete-case Cox; primary remains log2-linear.",
      wbc_ref
    ),
    "wbc_spline_relative_hazard.png",
    x_trans = "log2"
  )

  age_cc_nl <- wald_from_fit(age_cc, "age_rcs2")
  wbc_cc_nl <- wald_from_fit(wbc_cc, "log2_wbc_rcs2")
  age_cc_ov <- wald_from_fit(age_cc, c("age_rcs1", "age_rcs2"))
  wbc_cc_ov <- wald_from_fit(wbc_cc, c("log2_wbc_rcs1", "log2_wbc_rcs2"))

  summary_tbl <- data.frame(
    predictor = c("age", "age", "log2_wbc", "log2_wbc"),
    test = c("nonlinearity", "overall_spline", "nonlinearity", "overall_spline"),
    complete_case_statistic = c(
      age_cc_nl$statistic, age_cc_ov$statistic,
      wbc_cc_nl$statistic, wbc_cc_ov$statistic
    ),
    complete_case_df = c(
      age_cc_nl$df, age_cc_ov$df,
      wbc_cc_nl$df, wbc_cc_ov$df
    ),
    complete_case_p = c(
      age_cc_nl$p_value, age_cc_ov$p_value,
      wbc_cc_nl$p_value, wbc_cc_ov$p_value
    ),
    mi_median_statistic = c(
      pool_wald_median(age_nl)$statistic_median,
      pool_wald_median(age_overall)$statistic_median,
      pool_wald_median(wbc_nl)$statistic_median,
      pool_wald_median(wbc_overall)$statistic_median
    ),
    mi_median_p = c(
      pool_wald_median(age_nl)$p_median,
      pool_wald_median(age_overall)$p_median,
      pool_wald_median(wbc_nl)$p_median,
      pool_wald_median(wbc_overall)$p_median
    ),
    knots = c(
      paste(round(age_knots, 4), collapse = "; "),
      paste(round(age_knots, 4), collapse = "; "),
      paste(round(wbc_knots, 4), collapse = "; "),
      paste(round(wbc_knots, 4), collapse = "; ")
    ),
    reference = c(
      sprintf("%.4f years (median)", age_ref),
      sprintf("%.4f years (median)", age_ref),
      sprintf("%.2f x10^3/mcL (median)", wbc_ref),
      sprintf("%.2f x10^3/mcL (median)", wbc_ref)
    ),
    replaces_primary = FALSE,
    stringsAsFactors = FALSE
  )
  write_inference_csv(summary_tbl, "nonlinear_sensitivity_summary.csv")
  write_inference_csv(
    cbind(age_years = age_grid$age_at_diagnosis_years, age_curve),
    "age_spline_relative_hazard.csv"
  )
  write_inference_csv(
    cbind(wbc = wbc_grid_vals, wbc_curve),
    "wbc_spline_relative_hazard.csv"
  )
  list(
    table = summary_tbl,
    age_cc_nl = age_cc_nl,
    wbc_cc_nl = wbc_cc_nl,
    age_knots = age_knots,
    wbc_knots = wbc_knots,
    age_ref = age_ref,
    wbc_ref = wbc_ref
  )
}
