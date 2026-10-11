# Restricted cubic spline sensitivity for age and log2 WBC.
# Knots are frozen descriptive-analysis quantiles. They are not moved using AIC or p-values.

rcs_basis <- function(x, knots) {
  k <- as.numeric(knots)
  if (length(k) != 3L) {
    stop("The model specification froze exactly 3 knots.", call. = FALSE)
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


# Proportional-hazards diagnostics and prespecified remediation.

PH_ROLES_PRIMARY <- c(
  age5 = "nuisance",
  sex_std = "nuisance",
  log2_wbc = "important",
  risk_group_std = "important"
)

PH_ROLES_SECONDARY <- c(
  age5 = "nuisance",
  sex_std = "nuisance",
  log2_wbc = "nuisance",
  flt3_itd_std = "important",
  npm_std = "important",
  cebpa_std = "important",
  cytogenetics_t821_std = "important",
  cytogenetics_inv16_std = "important",
  cytogenetics_mll_std = "important",
  cytogenetics_monosomy7_std = "important"
)

# Frozen before inspecting results: combine test, |rho|, and scientific role.
# A p-value alone is not treated as proof of a material violation.
classify_ph <- function(p, rho, role) {
  p <- suppressWarnings(as.numeric(p)[1])
  rho <- suppressWarnings(as.numeric(rho)[1])
  if (isTRUE(is.na(p))) {
    return("UNCERTAIN")
  }
  if (isTRUE(is.na(rho))) {
    if (p >= 0.05) {
      return("NO MATERIAL EVIDENCE OF VIOLATION")
    }
    return("UNCERTAIN")
  }
  abs_rho <- abs(rho)
  if (p >= 0.05 && abs_rho < 0.10) {
    return("NO MATERIAL EVIDENCE OF VIOLATION")
  }
  if (p >= 0.05 && abs_rho >= 0.10) {
    return("UNCERTAIN")
  }
  if (p < 0.05 && abs_rho < 0.10) {
    return("MINOR DEPARTURE")
  }
  if (p < 0.05 && abs_rho < 0.20) {
    if (identical(role, "nuisance")) {
      return("MINOR DEPARTURE")
    }
    return("MATERIAL VIOLATION")
  }
  "MATERIAL VIOLATION"
}

normalize_zph_term <- function(term) {
  term <- gsub("TRUE$", "", term)
  term <- gsub("Male$", "", term)
  term <- gsub("Female$", "", term)
  term <- gsub("Standard$", "", term)
  term <- gsub("High$", "", term)
  term <- gsub("Low$", "", term)
  term <- gsub("Yes$", "", term)
  term <- gsub("No$", "", term)
  term
}

zph_table <- function(fit, model_name, source, roles) {
  z <- survival::cox.zph(fit)
  tbl <- as.data.frame(z$table)
  tbl$term <- rownames(z$table)
  rownames(tbl) <- NULL
  if (!("rho" %in% names(tbl))) {
    tbl$rho <- NA_real_
  }
  if (!is.null(z$y) && !is.null(z$x) && ncol(as.matrix(z$y)) > 0) {
    ymat <- as.matrix(z$y)
    for (nm in colnames(ymat)) {
      idx <- which(tbl$term == nm)
      if (length(idx) == 1L && isTRUE(is.na(tbl$rho[idx]))) {
        tbl$rho[idx] <- suppressWarnings(
          stats::cor(z$x, ymat[, nm], use = "complete.obs")
        )
      }
    }
  }
  if (!("p" %in% names(tbl)) && "p" %in% names(z$table)) {
    tbl$p <- z$table[, "p"]
  }
  pcol <- intersect(c("p", "Pr(>|z|)", "P"), names(tbl))
  if (length(pcol) && !("p" %in% names(tbl))) {
    tbl$p <- tbl[[pcol[[1]]]]
  }
  tbl$model <- model_name
  tbl$source <- source
  tbl$base_term <- vapply(tbl$term, function(nm) {
    if (identical(nm, "GLOBAL")) return("GLOBAL")
    normalize_zph_term(nm)
  }, character(1))
  tbl$role <- unname(roles[tbl$base_term])
  tbl$role[tbl$term == "GLOBAL"] <- "global"
  tbl$classification <- NA_character_
  for (i in seq_len(nrow(tbl))) {
    if (identical(tbl$term[[i]], "GLOBAL")) {
      tbl$classification[[i]] <- NA_character_
    } else {
      tbl$classification[[i]] <- classify_ph(
        tbl$p[[i]],
        tbl$rho[[i]],
        tbl$role[[i]]
      )
    }
  }
  keep <- intersect(
    c(
      "model", "source", "term", "base_term", "role",
      "rho", "chisq", "df", "p", "classification"
    ),
    names(tbl)
  )
  tbl[, keep]
}

save_zph_plot <- function(fit, filename, title, output_dir = INFERENCE_PH_DIR) {
  z <- survival::cox.zph(fit)
  terms <- colnames(z$y)  # The GLOBAL test is not a plotted term.
  if (!length(terms)) {
    stop("No Schoenfeld term plots to save.", call. = FALSE)
  }
  # plot.cox.zph draws one new plot per term; lay them out on one PNG.
  ncols <- if (length(terms) <= 4L) 2L else 3L
  nrows <- ceiling(length(terms) / ncols)
  path <- file.path(output_dir, filename)
  grDevices::png(path, width = 1200L * ncols, height = 900L * nrows + 150L, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(nrows, ncols), mar = c(3.7, 4.6, 1, 0.8),
                oma = c(0, 0, 3, 0))
  for (term in terms) {
    graphics::plot(z, var = term, col = "#2F4B7C", cex = 0.6)
  }
  graphics::mtext(title, side = 3, outer = TRUE, line = 1, cex = 1.2)
  path
}

median_zph_across_mi <- function(imp, coded, formula, model_name, roles, mutate_fn = NULL) {
  rows <- lapply(seq_len(imp$m), function(i) {
    dat <- completed_imputation(imp, i, coded)
    if (!is.null(mutate_fn)) dat <- mutate_fn(dat)
    fit <- fit_cox_one(dat, formula)
    zph_table(fit, model_name, paste0("imputation_", i), roles)
  })
  all_tbl <- dplyr::bind_rows(rows)
  dplyr::bind_rows(lapply(split(all_tbl, all_tbl$term), function(d) {
    data.frame(
      model = model_name,
      source = "mi_median",
      term = d$term[[1]],
      base_term = d$base_term[[1]],
      role = d$role[[1]],
      rho = stats::median(d$rho, na.rm = TRUE),
      chisq = stats::median(d$chisq, na.rm = TRUE),
      df = d$df[[1]],
      p = stats::median(d$p, na.rm = TRUE),
      p_min = min(d$p, na.rm = TRUE),
      p_max = max(d$p, na.rm = TRUE),
      n_p_lt_05 = sum(d$p < 0.05, na.rm = TRUE),
      classification = if (identical(d$term[[1]], "GLOBAL")) {
        NA_character_
      } else {
        classify_ph(
          stats::median(d$p, na.rm = TRUE),
          stats::median(d$rho, na.rm = TRUE),
          d$role[[1]]
        )
      },
      stringsAsFactors = FALSE
    )
  }))
}

fit_stratified_sensitivity <- function(data, formula, strata_var) {
  rhs <- paste(deparse(formula[[3]]), collapse = " ")
  rhs <- gsub(paste0("\\b", strata_var, "\\b\\s*\\+\\s*"), "", rhs)
  rhs <- gsub(paste0("\\+\\s*\\b", strata_var, "\\b"), "", rhs)
  new_f <- stats::as.formula(
    sprintf("survival::Surv(os_days, os_event) ~ %s + strata(%s)", rhs, strata_var)
  )
  fit_cox_one(data, new_f)
}

fit_logtime_sensitivity <- function(data, formula, tv_vars) {
  rhs <- paste(deparse(formula[[3]]), collapse = " ")
  tt_terms <- paste(sprintf("tt(%s)", tv_vars), collapse = " + ")
  new_f <- stats::as.formula(
    sprintf("survival::Surv(os_days, os_event) ~ %s + %s", rhs, tt_terms)
  )
  warnings <- character()
  fit <- withCallingHandlers(
    survival::coxph(
      new_f,
      data = data,
      ties = "efron",
      tt = function(x, t, ...) {
        x * log(pmax(as.numeric(t), 1))
      },
      model = TRUE
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  attr(fit, "warnings") <- warnings
  attr(fit, "estimable") <- !any(!is.finite(coef(fit)))
  fit
}

run_ph_diagnostics <- function(imp, coded, primary_cc, secondary_cc) {
  primary_cc_z <- zph_table(primary_cc$fit, "primary_clinical", "complete_case", PH_ROLES_PRIMARY)
  secondary_cc_z <- zph_table(secondary_cc$fit, "secondary_molecular", "complete_case", PH_ROLES_SECONDARY)
  primary_mi_z <- median_zph_across_mi(imp, coded, PRIMARY_FORMULA, "primary_clinical", PH_ROLES_PRIMARY)
  secondary_mi_z <- median_zph_across_mi(imp, coded, SECONDARY_FORMULA, "secondary_molecular", PH_ROLES_SECONDARY)

  save_zph_plot(
    primary_cc$fit,
    "primary_cox_zph_complete_case.png",
    "Primary clinical model, scaled Schoenfeld residuals (complete case)"
  )
  save_zph_plot(
    secondary_cc$fit,
    "secondary_cox_zph_complete_case.png",
    "Secondary molecular model, scaled Schoenfeld residuals (complete case)"
  )

  mid <- completed_imputation(imp, 15L, coded)
  save_zph_plot(
    fit_cox_one(mid, PRIMARY_FORMULA),
    "primary_cox_zph_imputation15.png",
    "Primary clinical model, scaled Schoenfeld residuals (imputation 15)"
  )
  save_zph_plot(
    fit_cox_one(mid, SECONDARY_FORMULA),
    "secondary_cox_zph_imputation15.png",
    "Secondary molecular model, scaled Schoenfeld residuals (imputation 15)"
  )

  combined <- dplyr::bind_rows(primary_cc_z, secondary_cc_z)
  write_inference_csv(combined, "ph_diagnostics_complete_case.csv", subdir = "ph")
  write_inference_csv(
    dplyr::bind_rows(primary_mi_z, secondary_mi_z),
    "ph_diagnostics_mi_median.csv",
    subdir = "ph"
  )

  # Decision uses complete-case zph plus MI-median classification.
  # Material violation is declared only if complete-case classification is
  # MATERIAL and MI-median classification is not NO MATERIAL EVIDENCE.
  decision_rows <- lapply(seq_len(nrow(combined)), function(i) {
    row <- combined[i, ]
    if (identical(row$term, "GLOBAL")) {
      row$decision <- NA_character_
      return(row)
    }
    mi_match <- dplyr::bind_rows(primary_mi_z, secondary_mi_z)
    mi_match <- mi_match[mi_match$model == row$model & mi_match$term == row$term, ]
    mi_class <- if (nrow(mi_match)) mi_match$classification[[1]] else NA_character_
    if (identical(row$classification, "MATERIAL VIOLATION") &&
        !identical(mi_class, "NO MATERIAL EVIDENCE OF VIOLATION")) {
      row$decision <- "MATERIAL VIOLATION"
    } else if (identical(row$classification, "MINOR DEPARTURE") ||
               identical(mi_class, "MINOR DEPARTURE")) {
      row$decision <- "MINOR DEPARTURE"
    } else {
      row$decision <- row$classification
    }
    row$mi_median_classification <- mi_class
    row
  })
  decisions <- dplyr::bind_rows(decision_rows)
  write_inference_csv(decisions, "ph_diagnostics_summary.csv")

  remediation <- run_ph_remediation(imp, coded, primary_cc, decisions)
  list(
    complete_case = combined,
    mi_median = dplyr::bind_rows(primary_mi_z, secondary_mi_z),
    decisions = decisions,
    remediation = remediation
  )
}

run_ph_remediation <- function(imp, coded, primary_cc, decisions) {
  primary_dec <- decisions[decisions$model == "primary_clinical" & !is.na(decisions$decision), ]
  material <- primary_dec[primary_dec$decision == "MATERIAL VIOLATION", ]
  notes <- list()
  tables <- list()
  if (!nrow(material)) {
    notes$primary <- "No material PH violation was classified for the primary clinical model. No remediation model was fit."
    return(list(notes = notes, tables = tables, performed = FALSE))
  }
  for (i in seq_len(nrow(material))) {
    term <- material$base_term[[i]]
    role <- material$role[[i]]
    if (identical(role, "nuisance")) {
      notes[[paste0("strata_", term)]] <- sprintf(
        "Material PH departure classified for nuisance factor %s. Fitted stratified Cox sensitivity; no HR is reported for the stratified factor. Primary unstratified Cox remains primary.",
        term
      )
      cc_fit <- fit_stratified_sensitivity(primary_cc$data, PRIMARY_FORMULA, term)
      sm <- broom::tidy(cc_fit, conf.int = TRUE, exponentiate = FALSE)
      sm$model <- "primary_stratified_sensitivity"
      sm$strata_variable <- term
      tables[[paste0("strata_", term)]] <- sm
      write_inference_csv(sm, sprintf("ph_remediation_strata_%s.csv", term), subdir = "ph")
    } else if (identical(role, "important")) {
      notes[[paste0("tt_", term)]] <- sprintf(
        "Material PH departure classified for scientifically important predictor %s. Fitted prespecified log(time) interaction sensitivity. The original Cox model remains primary.",
        term
      )
      tv <- if (identical(term, "risk_group_std")) {
        "risk_group_std"
      } else {
        term
      }
      cc_fit <- fit_logtime_sensitivity(primary_cc$data, PRIMARY_FORMULA, tv)
      sm <- broom::tidy(cc_fit, conf.int = TRUE, exponentiate = FALSE)
      sm$model <- "primary_logtime_sensitivity"
      sm$time_varying_variable <- tv
      tables[[paste0("tt_", term)]] <- sm
      write_inference_csv(sm, sprintf("ph_remediation_logtime_%s.csv", term), subdir = "ph")
    }
  }
  list(notes = notes, tables = tables, performed = TRUE)
}


# Influence diagnostics on complete-case principal models.
# Patient-level files stay under data/interim/stage6 (gitignored).
# Valid observations are not deleted for influence alone.

influence_summary_from_fit <- function(fit, data, model_name) {
  n <- nrow(data)
  # Preserve unscaled DFBETA from the frozen SAP, but apply the
  # 2/sqrt(n) influence screening threshold only to standardized DFBETAS.
  dfb <- as.matrix(stats::residuals(fit, type = "dfbeta"))
  dfbs <- as.matrix(stats::residuals(fit, type = "dfbetas"))
  coef_names <- names(stats::coef(fit))
  if (!identical(dim(dfb), dim(dfbs)) ||
      nrow(dfb) != n || ncol(dfb) != length(coef_names)) {
    stop("Influence residuals do not align with the complete-case Cox data.", call. = FALSE)
  }
  colnames(dfb) <- coef_names
  colnames(dfbs) <- coef_names
  deviance_res <- as.numeric(stats::residuals(fit, type = "deviance"))
  martingale_res <- as.numeric(stats::residuals(fit, type = "martingale"))
  thresh <- 2 / sqrt(n)
  max_abs_dfbeta <- apply(abs(dfb), 2, max, na.rm = TRUE)
  max_abs_dfbetas <- apply(abs(dfbs), 2, max, na.rm = TRUE)
  n_over <- colSums(abs(dfbs) > thresh, na.rm = TRUE)
  summary_tbl <- data.frame(
    model = model_name,
    term = colnames(dfb),
    n = n,
    dfbetas_threshold_2_over_sqrt_n = thresh,
    max_abs_dfbeta = as.numeric(max_abs_dfbeta),
    max_abs_dfbetas = as.numeric(max_abs_dfbetas),
    n_exceeding_threshold = as.integer(n_over),
    deviance_min = min(deviance_res, na.rm = TRUE),
    deviance_max = max(deviance_res, na.rm = TRUE),
    martingale_min = min(martingale_res, na.rm = TRUE),
    martingale_max = max(martingale_res, na.rm = TRUE),
    n_abs_deviance_gt_3 = sum(abs(deviance_res) > 3, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  person_tbl <- data.frame(
    analysis_person_id = data$analysis_person_id,
    os_event = data$os_event,
    os_days = data$os_days,
    deviance_residual = as.numeric(deviance_res),
    martingale_residual = as.numeric(martingale_res),
    max_abs_dfbeta = apply(abs(dfb), 1, max, na.rm = TRUE),
    max_abs_dfbetas = apply(abs(dfbs), 1, max, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  list(summary = summary_tbl, person = person_tbl, n = n, threshold = thresh)
}

plot_influence <- function(person, model_name, filename) {
  p <- ggplot2::ggplot(person, ggplot2::aes(x = seq_len(nrow(person)), y = deviance_residual)) +
    ggplot2::geom_hline(yintercept = c(-3, 3), linetype = "dashed", color = "#999999") +
    ggplot2::geom_point(alpha = 0.35, size = 0.9, color = "#2F4B7C") +
    ggplot2::labs(
      title = sprintf("Deviance residuals: %s", model_name),
      subtitle = "Complete-case Cox. Points are unlabeled. Influential valid observations are retained.",
      x = "Observation index (arbitrary)",
      y = "Deviance residual"
    ) +
    ggplot2::theme_bw(base_size = 12)
  save_inference_plot(p, filename, width = 2200, height = 1400)
}

run_influence_diagnostics <- function(primary_cc, secondary_cc) {
  primary <- influence_summary_from_fit(primary_cc$fit, primary_cc$data, "primary_clinical")
  secondary <- influence_summary_from_fit(secondary_cc$fit, secondary_cc$data, "secondary_molecular")
  summary_tbl <- dplyr::bind_rows(primary$summary, secondary$summary)
  write_inference_csv(summary_tbl, "influence_summary.csv")
  saveRDS(primary$person, file.path(INTERIM_STAGE6, "primary_influence_person.rds"))
  saveRDS(secondary$person, file.path(INTERIM_STAGE6, "secondary_influence_person.rds"))
  plot_influence(primary$person, "primary clinical model", "primary_deviance_residuals.png")
  plot_influence(secondary$person, "secondary molecular model", "secondary_deviance_residuals.png")
  list(
    summary = summary_tbl,
    primary_n_deviance_gt_3 = primary$summary$n_abs_deviance_gt_3[[1]],
    secondary_n_deviance_gt_3 = secondary$summary$n_abs_deviance_gt_3[[1]],
    primary_max_dfbeta = max(primary$summary$max_abs_dfbeta),
    secondary_max_dfbeta = max(secondary$summary$max_abs_dfbeta),
    primary_max_dfbetas = max(primary$summary$max_abs_dfbetas),
    secondary_max_dfbetas = max(secondary$summary$max_abs_dfbetas)
  )
}


# Prespecified unadjusted KM curves: risk group and FLT3/ITD only.
# Descriptive. Not used for variable selection. No log-rank test.

km_by_factor <- function(data, varname, levels_keep, title, subtitle, filename) {
  d <- data[!is.na(data[[varname]]) & data[[varname]] %in% levels_keep, , drop = FALSE]
  d[[varname]] <- droplevels(factor(d[[varname]], levels = levels_keep))
  form <- stats::as.formula(sprintf("survival::Surv(os_years, os_event) ~ %s", varname))
  fit <- survival::survfit(form, data = d, conf.type = "log-log")
  tidy <- broom::tidy(fit)
  tidy$strata_label <- sub(paste0("^", varname), "", tidy$strata)
  tidy$strata_label <- gsub("^=", "", tidy$strata_label)
  palette <- c("#2F4B7C", "#E07A3D", "#3A7D44")
  names(palette) <- levels_keep[seq_len(min(length(levels_keep), length(palette)))]
  p <- ggplot2::ggplot(tidy, ggplot2::aes(x = time, y = estimate, color = strata_label, fill = strata_label)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = conf.low, ymax = conf.high),
      alpha = 0.12,
      color = NA,
      na.rm = TRUE
    ) +
    ggplot2::geom_step(linewidth = 0.9, na.rm = TRUE) +
    ggplot2::coord_cartesian(xlim = c(0, max(c(tidy$time, 10), na.rm = TRUE)), ylim = c(0, 1)) +
    ggplot2::scale_x_continuous(breaks = c(0, 1, 3, 5, 10)) +
    ggplot2::scale_y_continuous(
      breaks = seq(0, 1, 0.2),
      labels = scales::label_percent(accuracy = 1)
    ) +
    ggplot2::scale_color_manual(values = palette, drop = FALSE) +
    ggplot2::scale_fill_manual(values = palette, drop = FALSE) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      x = "Years from initial pathologic diagnosis",
      y = "Overall survival probability",
      color = NULL,
      fill = NULL
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "bottom"
    )
  save_inference_plot(p, filename, width = 2400, height = 1700)
  times <- c(1, 3, 5)
  summarized <- summary(fit, times = times, extend = TRUE)
  est <- data.frame(
    variable = varname,
    strata = as.character(summarized$strata),
    time_years = summarized$time,
    n_risk = summarized$n.risk,
    n_event = summarized$n.event,
    survival = summarized$surv,
    surv_lcl = summarized$lower,
    surv_ucl = summarized$upper,
    n_in_figure = nrow(d),
    stringsAsFactors = FALSE
  )
  list(n = nrow(d), estimates = est, path = file.path(INFERENCE_FIG_DIR, filename))
}

run_stratified_km <- function(coded) {
  if (!("os_years" %in% names(coded))) {
    coded$os_years <- coded$os_days / DAYS_PER_YEAR
  }
  rg <- km_by_factor(
    coded,
    "risk_group_std",
    c("Low", "Standard", "High"),
    "Overall survival by protocol risk group",
    "Unadjusted Kaplan-Meier. Missing and unresolved risk-group tokens excluded. Descriptive only; not used for model selection. No log-rank test.",
    "km_risk_group.png"
  )
  flt3 <- km_by_factor(
    coded,
    "flt3_itd_std",
    c("No", "Yes"),
    "Overall survival by FLT3/ITD",
    "Unadjusted Kaplan-Meier. Missing FLT3/ITD excluded. Descriptive only; not used for model selection. No log-rank test.",
    "km_flt3_itd.png"
  )
  estimates <- dplyr::bind_rows(rg$estimates, flt3$estimates)
  write_inference_csv(estimates, "stratified_km_estimates.csv")
  list(
    risk_group_n = rg$n,
    flt3_n = flt3$n,
    estimates = estimates,
    risk_group_plot = TRUE,
    flt3_plot = TRUE,
    log_rank = FALSE
  )
}


# Aggregate inference tables, forest plots, metadata, and MI vs complete-case comparison.

mi_cc_comparison <- function(mi_tbl, cc_tbl) {
  merged <- merge(
    mi_tbl[, c("term", "predictor_label", "hr", "hr_lcl", "hr_ucl", "p_value")],
    cc_tbl[, c("term", "hr", "hr_lcl", "hr_ucl", "p_value", "n", "deaths")],
    by = "term",
    suffixes = c("_mi", "_cc")
  )
  merged$direction_same <- sign(log(merged$hr_mi)) == sign(log(merged$hr_cc))
  merged$hr_ratio_cc_over_mi <- merged$hr_cc / merged$hr_mi
  # Descriptive heuristic only: overlapping confidence intervals do not imply
  # similar point estimates, and these labels are not tests of equivalence.
  merged$qualitative <- vapply(seq_len(nrow(merged)), function(i) {
    mi_hr <- merged$hr_mi[[i]]
    cc_hr <- merged$hr_cc[[i]]
    if (!all(is.finite(c(mi_hr, cc_hr))) || any(c(mi_hr, cc_hr) <= 0)) {
      return("uncertain")
    }
    rel <- abs(log(cc_hr / mi_hr))
    if (rel >= log(1.25)) {
      "meaningfully different"
    } else if (rel < log(1.15) && isTRUE(merged$direction_same[[i]])) {
      "similar"
    } else {
      "uncertain"
    }
  }, character(1))
  merged[order(match(merged$term, c(PRIMARY_TERM_ORDER, SECONDARY_TERM_ORDER))), ]
}

model_fit_summary <- function(spec, primary_mi, secondary_mi, primary_cc, secondary_cc,
                              primary_conc, secondary_conc, ph, influence, km, mi_diag) {
  one <- function(x) {
    if (is.null(x) || length(x) < 1) {
      return(NA_character_)
    }
    as.character(x[[1]])
  }
  vals <- list(
    primary_n = EXPECTED_N,
    primary_deaths = EXPECTED_DEATHS,
    primary_censored = EXPECTED_CENSORED,
    primary_df = spec$primary_model$df,
    primary_events_per_df = EXPECTED_DEATHS / spec$primary_model$df,
    secondary_df = spec$secondary_model$df,
    secondary_events_per_df = EXPECTED_DEATHS / spec$secondary_model$df,
    mi_m = mi_diag$m,
    mi_seed = mi_diag$seed,
    mi_maxit = mi_diag$maxit,
    primary_cc_n = primary_cc$n,
    primary_cc_deaths = primary_cc$deaths,
    primary_cc_percent = round(100 * primary_cc$n / EXPECTED_N, 2),
    secondary_cc_n = secondary_cc$n,
    secondary_cc_deaths = secondary_cc$deaths,
    secondary_cc_percent = round(100 * secondary_cc$n / EXPECTED_N, 2),
    primary_concordance_mi_mean = sprintf("%.3f", primary_conc$mean),
    secondary_concordance_mi_mean = sprintf("%.3f", secondary_conc$mean),
    primary_concordance_cc = sprintf("%.3f", primary_cc$concordance),
    secondary_concordance_cc = sprintf("%.3f", secondary_cc$concordance),
    ties = "efron",
    ph_method = "cox.zph scaled Schoenfeld",
    ph_remediation_performed = isTRUE(ph$remediation$performed),
    km_risk_group = "yes",
    km_flt3 = "yes",
    km_log_rank = "no",
    influence_auto_deleted = "false",
    mi_plausibility_issues = length(mi_diag$issues)
  )
  data.frame(
    item = names(vals),
    value = vapply(vals, one, character(1)),
    stringsAsFactors = FALSE
  )
}

write_model_metadata <- function(spec, primary_cc, secondary_cc, primary_conc,
                                 secondary_conc, ph, mi_diag, session) {
  payload <- list(
    cohort_n = as.integer(EXPECTED_N),
    deaths = as.integer(EXPECTED_DEATHS),
    censored = as.integer(EXPECTED_CENSORED),
    primary_formula = spec$primary_model$formula,
    secondary_formula = spec$secondary_model$formula,
    m = mi_diag$m,
    seed = mi_diag$seed,
    mice_maxit = mi_diag$maxit,
    ties = "efron",
    software = session,
    run_timestamp = format(Sys.time(), tz = "UTC", usetz = TRUE),
    fdr_family = spec$multiplicity$secondary$fdr_family,
    fdr_method = spec$multiplicity$secondary$fdr_method,
    ph_method = "cox.zph",
    complete_case_primary_n = primary_cc$n,
    complete_case_primary_deaths = primary_cc$deaths,
    complete_case_secondary_n = secondary_cc$n,
    complete_case_secondary_deaths = secondary_cc$deaths,
    primary_concordance_mi_mean = primary_conc$mean,
    secondary_concordance_mi_mean = secondary_conc$mean,
    ph_remediation_performed = isTRUE(ph$remediation$performed),
    patient_level_data_included = FALSE
  )
  write_inference_json(payload, "model_metadata.json")
}

inference_session_info <- function() {
  info <- utils::sessionInfo()
  pkgs <- c("survival", "mice", "ggplot2", "broom", "yaml", "jsonlite", "dplyr")
  versions <- lapply(pkgs, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NA_character_
  })
  names(versions) <- pkgs
  list(
    r_version = paste(info$R.version$major, info$R.version$minor, sep = "."),
    platform = info$R.version$platform,
    running = info$running,
    packages = versions
  )
}

write_inference_outputs <- function(spec, primary_mi, secondary_mi, primary_cc, secondary_cc,
                                 primary_conc, secondary_conc, ph, influence, km, mi_diag) {
  write_inference_csv(primary_mi, "primary_cox_mi.csv")
  write_inference_csv(secondary_mi, "secondary_cox_mi.csv")
  write_inference_csv(primary_cc$table, "primary_cox_complete_case.csv")
  write_inference_csv(secondary_cc$table, "secondary_cox_complete_case.csv")
  primary_cmp <- mi_cc_comparison(primary_mi, primary_cc$table)
  secondary_cmp <- mi_cc_comparison(secondary_mi, secondary_cc$table)
  primary_cmp$model <- "primary_clinical"
  secondary_cmp$model <- "secondary_molecular"
  write_inference_csv(dplyr::bind_rows(primary_cmp, secondary_cmp), "mi_vs_complete_case.csv")
  forest_plot(
    primary_mi,
    "Primary clinical Cox model",
    "Multiply imputed (m = 30), Rubin pooling on the log-hazard-ratio scale. Adjusted associations, not causal effects.",
    "forest_primary_clinical.png"
  )
  forest_plot(
    secondary_mi,
    "Secondary molecular/cytogenetic Cox model",
    "Multiply imputed (m = 30). Risk group is absent. q-values are in the results table, not this plot.",
    "forest_secondary_molecular.png"
  )
  fit_sum <- model_fit_summary(
    spec, primary_mi, secondary_mi, primary_cc, secondary_cc,
    primary_conc, secondary_conc, ph, influence, km, mi_diag
  )
  write_inference_csv(fit_sum, "model_fit_summary.csv")
  session <- inference_session_info()
  write_inference_json(session, "r_session_info.json")
  write_model_metadata(
    spec, primary_cc, secondary_cc, primary_conc, secondary_conc, ph, mi_diag, session
  )
  list(primary_comparison = primary_cmp, secondary_comparison = secondary_cmp, session = session)
}
