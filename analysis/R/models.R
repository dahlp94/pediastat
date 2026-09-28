# Stage 6: fit and pool the frozen primary and secondary Cox models.

PRIMARY_FORMULA <- stats::as.formula(
  "survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std"
)
SECONDARY_FORMULA <- stats::as.formula(
  paste(
    "survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc +",
    "flt3_itd_std + npm_std + cebpa_std +",
    "cytogenetics_t821_std + cytogenetics_inv16_std +",
    "cytogenetics_mll_std + cytogenetics_monosomy7_std"
  )
)

TERM_LABELS <- c(
  age5 = "Age at diagnosis (per 5 years)",
  sex_stdMale = "Male vs Female",
  log2_wbc = "WBC (per doubling)",
  risk_group_stdStandard = "Standard vs Low risk",
  risk_group_stdHigh = "High vs Low risk",
  flt3_itd_stdYes = "FLT3/ITD Yes vs No",
  npm_stdYes = "NPM mutation Yes vs No",
  cebpa_stdYes = "CEBPA mutation Yes vs No",
  cytogenetics_t821_stdYes = "t(8;21) Yes vs No",
  cytogenetics_inv16_stdYes = "inv(16) Yes vs No",
  cytogenetics_mll_stdYes = "MLL/KMT2A rearrangement Yes vs No",
  cytogenetics_monosomy7_stdYes = "Monosomy 7 Yes vs No"
)

TERM_UNITS <- c(
  age5 = "per 5-year increase",
  sex_stdMale = "Male vs Female",
  log2_wbc = "per doubling of WBC",
  risk_group_stdStandard = "Standard vs Low",
  risk_group_stdHigh = "High vs Low",
  flt3_itd_stdYes = "Yes vs No",
  npm_stdYes = "Yes vs No",
  cebpa_stdYes = "Yes vs No",
  cytogenetics_t821_stdYes = "Yes vs No",
  cytogenetics_inv16_stdYes = "Yes vs No",
  cytogenetics_mll_stdYes = "Yes vs No",
  cytogenetics_monosomy7_stdYes = "Yes vs No"
)

FDR_TERM_MAP <- c(
  flt3_itd_std = "flt3_itd_stdYes",
  npm_std = "npm_stdYes",
  cebpa_std = "cebpa_stdYes",
  cytogenetics_t821_std = "cytogenetics_t821_stdYes",
  cytogenetics_inv16_std = "cytogenetics_inv16_stdYes",
  cytogenetics_mll_std = "cytogenetics_mll_stdYes",
  cytogenetics_monosomy7_std = "cytogenetics_monosomy7_stdYes"
)

PRIMARY_TERM_ORDER <- c(
  "age5", "sex_stdMale", "log2_wbc",
  "risk_group_stdStandard", "risk_group_stdHigh"
)

SECONDARY_TERM_ORDER <- c(
  "age5", "sex_stdMale", "log2_wbc",
  "flt3_itd_stdYes", "npm_stdYes", "cebpa_stdYes",
  "cytogenetics_t821_stdYes", "cytogenetics_inv16_stdYes",
  "cytogenetics_mll_stdYes", "cytogenetics_monosomy7_stdYes"
)

fit_cox_one <- function(data, formula) {
  warnings <- character()
  fit <- withCallingHandlers(
    survival::coxph(
      formula,
      data = data,
      ties = "efron",
      model = TRUE,
      x = TRUE,
      y = TRUE
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  if (isTRUE(fit$nevent < 1) || any(!is.finite(coef(fit)))) {
    attr(fit, "estimable") <- FALSE
  } else {
    attr(fit, "estimable") <- TRUE
  }
  attr(fit, "warnings") <- warnings
  fit
}

fit_cox_across_imputations <- function(imp, coded, formula, mutate_fn = NULL) {
  analyses <- lapply(seq_len(imp$m), function(i) {
    dat <- completed_imputation(imp, i, coded)
    if (!is.null(mutate_fn)) {
      dat <- mutate_fn(dat)
    }
    fit_cox_one(dat, formula)
  })
  call_obj <- call("coxph", formula = formula, ties = "efron")
  mira <- list(
    call = call_obj,
    call1 = imp$call,
    nmis = imp$nmis,
    analyses = analyses
  )
  oldClass(mira) <- c("mira", "matrix")
  mira
}

assert_cox_ties_efron <- function(fit) {
  method <- fit$method
  if (!identical(method, "efron")) {
    stop("Cox ties method is not Efron.", call. = FALSE)
  }
  invisible(TRUE)
}

assert_no_interactions <- function(fit) {
  nms <- names(coef(fit))
  if (any(grepl(":", nms, fixed = TRUE))) {
    stop("Interaction terms found in a principal Cox model.", call. = FALSE)
  }
  invisible(TRUE)
}

pool_cox_mira <- function(mira_obj, model_name, term_order) {
  lapply(mira_obj$analyses, assert_cox_ties_efron)
  lapply(mira_obj$analyses, assert_no_interactions)
  pooled <- mice::pool(mira_obj)
  sm <- summary(pooled, conf.int = TRUE, exponentiate = FALSE)
  pooled_df <- as.data.frame(pooled$pooled)
  pick <- function(primary, fallback) {
    if (!is.null(primary) && length(primary) == nrow(sm)) {
      as.numeric(primary)
    } else if (!is.null(fallback) && length(fallback) == nrow(sm)) {
      as.numeric(fallback)
    } else {
      rep(NA_real_, nrow(sm))
    }
  }
  fmi <- pick(sm$fmi, pooled_df$fmi)
  riv <- pick(sm$riv, pooled_df$riv)
  lambda <- pick(sm$lambda, pooled_df$lambda)
  df_col <- pick(sm$df, pooled_df$df)
  out <- data.frame(
    model = model_name,
    term = as.character(sm$term),
    predictor_label = unname(TERM_LABELS[as.character(sm$term)]),
    comparison_or_unit = unname(TERM_UNITS[as.character(sm$term)]),
    beta = as.numeric(sm$estimate),
    se = as.numeric(sm$std.error),
    statistic = as.numeric(sm$statistic),
    df = as.numeric(df_col),
    p_value = as.numeric(sm$p.value),
    hr = exp(as.numeric(sm$estimate)),
    hr_lcl = exp(as.numeric(sm$conf.low)),
    hr_ucl = exp(as.numeric(sm$conf.high)),
    n_imputations = length(mira_obj$analyses),
    fmi = as.numeric(fmi),
    riv = as.numeric(riv),
    lambda = as.numeric(lambda),
    q_value = NA_real_,
    stringsAsFactors = FALSE
  )
  out$predictor_label[is.na(out$predictor_label)] <- out$term[is.na(out$predictor_label)]
  ord <- match(out$term, term_order)
  out <- out[order(ord, na.last = TRUE), ]
  rownames(out) <- NULL
  if (any(abs(out$hr - exp(out$beta)) > 1e-10, na.rm = TRUE)) {
    stop("HR is not exp(beta) after pooling.", call. = FALSE)
  }
  out
}

concordance_from_mira <- function(mira_obj) {
  vals <- vapply(mira_obj$analyses, function(fit) {
    conc <- survival::concordance(fit)
    as.numeric(conc$concordance)
  }, numeric(1))
  list(
    mean = mean(vals, na.rm = TRUE),
    min = min(vals, na.rm = TRUE),
    max = max(vals, na.rm = TRUE),
    n = length(vals)
  )
}

cox_warning_summary <- function(mira_obj, model_name) {
  notes <- lapply(seq_along(mira_obj$analyses), function(i) {
    w <- attr(mira_obj$analyses[[i]], "warnings")
    if (!length(w)) return(NULL)
    data.frame(
      model = model_name,
      imputation = i,
      warning = paste(unique(w), collapse = " | "),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(notes)
}

global_risk_group_test <- function(imp, coded) {
  full <- with(
    imp,
    survival::coxph(
      survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc + risk_group_std,
      ties = "efron"
    )
  )
  reduced <- with(
    imp,
    survival::coxph(
      survival::Surv(os_days, os_event) ~ age5 + sex_std + log2_wbc,
      ties = "efron"
    )
  )
  d1 <- mice::D1(full, reduced)
  res <- as.data.frame(d1$result)
  p_col <- intersect(c("P(>F)", "Pr(>F)", "p.value", "pvalue"), names(res))
  if (!length(p_col)) {
    p_val <- NA_real_
  } else {
    p_val <- as.numeric(res[[p_col[[1]]]][1])
  }
  stat_col <- intersect(c("F", "F.value", "statistic", "Wald"), names(res))
  list(
    method = "mice::D1 multivariate Wald test (risk_group_std 2 df vs nested model without risk group)",
    statistic = if (length(stat_col)) as.numeric(res[[stat_col[[1]]]][1]) else NA_real_,
    df1 = if ("df1" %in% names(res)) as.numeric(res$df1[1]) else NA_real_,
    df2 = if ("df2" %in% names(res)) as.numeric(res$df2[1]) else NA_real_,
    p_value = p_val,
    result_columns = paste(names(res), collapse = ",")
  )
}

apply_bh_qvalues <- function(secondary_tbl, spec) {
  family <- unlist(spec$multiplicity$secondary$fdr_family, use.names = FALSE)
  expected <- unname(FDR_TERM_MAP[family])
  if (any(is.na(expected))) {
    stop("FDR family mapping incomplete.", call. = FALSE)
  }
  forbidden <- unlist(spec$multiplicity$secondary$fdr_not_applied_to, use.names = FALSE)
  if (any(secondary_tbl$term %in% c("age5", "sex_stdMale", "log2_wbc") &
          !is.na(secondary_tbl$q_value))) {
    stop("q-values were applied to adjustment terms.", call. = FALSE)
  }
  idx <- match(expected, secondary_tbl$term)
  if (any(is.na(idx))) {
    stop("Secondary table is missing an FDR-family coefficient.", call. = FALSE)
  }
  secondary_tbl$q_value[idx] <- p.adjust(secondary_tbl$p_value[idx], method = "BH")
  extra_q <- setdiff(which(!is.na(secondary_tbl$q_value)), idx)
  if (length(extra_q)) {
    stop("q-values assigned outside the frozen FDR family.", call. = FALSE)
  }
  invisible(family)
  secondary_tbl
}

tidy_complete_case_cox <- function(fit, model_name, term_order, n, deaths) {
  sm <- broom::tidy(fit, conf.int = TRUE, exponentiate = FALSE)
  out <- data.frame(
    model = model_name,
    term = sm$term,
    predictor_label = unname(TERM_LABELS[sm$term]),
    comparison_or_unit = unname(TERM_UNITS[sm$term]),
    beta = sm$estimate,
    se = sm$std.error,
    statistic = sm$statistic,
    p_value = sm$p.value,
    hr = exp(sm$estimate),
    hr_lcl = exp(sm$conf.low),
    hr_ucl = exp(sm$conf.high),
    n = n,
    deaths = deaths,
    percent_of_primary_cohort = round(100 * n / EXPECTED_N, 2),
    stringsAsFactors = FALSE
  )
  out$predictor_label[is.na(out$predictor_label)] <- out$term[is.na(out$predictor_label)]
  ord <- match(out$term, term_order)
  out <- out[order(ord, na.last = TRUE), ]
  rownames(out) <- NULL
  out
}

fit_complete_case <- function(coded, formula, terms, model_name, term_order) {
  cc <- coded[stats::complete.cases(coded[, terms, drop = FALSE]), , drop = FALSE]
  fit <- fit_cox_one(cc, formula)
  assert_cox_ties_efron(fit)
  assert_no_interactions(fit)
  n <- nrow(cc)
  deaths <- sum(cc$os_event == 1L)
  tbl <- tidy_complete_case_cox(fit, model_name, term_order, n, deaths)
  conc <- as.numeric(survival::concordance(fit)$concordance)
  list(fit = fit, table = tbl, n = n, deaths = deaths, concordance = conc, data = cc)
}

forest_plot <- function(tbl, title, subtitle, filename) {
  d <- tbl
  d$predictor_label <- factor(d$predictor_label, levels = rev(d$predictor_label))
  p <- ggplot2::ggplot(d, ggplot2::aes(x = hr, y = predictor_label)) +
    ggplot2::geom_vline(xintercept = 1, linetype = "dashed", color = "#666666") +
    ggplot2::geom_pointrange(
      ggplot2::aes(xmin = hr_lcl, xmax = hr_ucl),
      color = "#2F4B7C",
      linewidth = 0.7
    ) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      x = "Adjusted hazard ratio (95% CI)",
      y = NULL
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
  save_inference_plot(p, filename, width = 2400, height = 1400)
}
