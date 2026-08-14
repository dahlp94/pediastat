# Stage 6 multiple imputation and convergence diagnostics.

MICE_MAXIT <- 20L

run_multiple_imputation <- function(mi_frame, meth, pred, spec) {
  m <- as.integer(spec$missing_data$m)
  seed <- as.integer(spec$missing_data$seed)
  if (!identical(m, 30L)) {
    stop("Frozen m is 30; refusing to run a different number of imputations.", call. = FALSE)
  }
  if (!identical(seed, 20260814L)) {
    stop("Frozen MI seed is 20260814.", call. = FALSE)
  }
  assert_mice_spec(meth, spec)
  message("Running mice: m = ", m, ", maxit = ", MICE_MAXIT, ", seed = ", seed)
  imp <- mice::mice(
    mi_frame,
    m = m,
    maxit = MICE_MAXIT,
    method = meth,
    predictorMatrix = pred,
    seed = seed,
    printFlag = FALSE
  )
  imp
}

completed_imputation <- function(imp, i, coded) {
  dat <- mice::complete(imp, action = i)
  dat <- restore_mice_factors(dat, imp$data)
  dat$analysis_person_id <- coded$analysis_person_id
  dat$age_at_diagnosis_years <- coded$age_at_diagnosis_years
  dat
}

restore_mice_factors <- function(dat, template) {
  for (nm in names(template)) {
    if (is.factor(template[[nm]]) && nm %in% names(dat)) {
      dat[[nm]] <- factor(as.character(dat[[nm]]), levels = levels(template[[nm]]))
    }
  }
  dat
}

all_completed_imputations <- function(imp, coded) {
  lapply(seq_len(imp$m), function(i) completed_imputation(imp, i, coded))
}

chain_trace_table <- function(imp) {
  cm <- imp$chainMean
  vars <- dimnames(cm)[[1]]
  iters <- dimnames(cm)[[2]]
  chains <- dimnames(cm)[[3]]
  rows <- list()
  for (v in vars) {
    for (ch in chains) {
      vals <- as.numeric(cm[v, , ch])
      if (all(is.na(vals))) next
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v,
        imputation = ch,
        iteration = as.integer(iters),
        chain_mean = vals,
        stringsAsFactors = FALSE
      )
    }
  }
  dplyr::bind_rows(rows)
}

summarize_chain_stability <- function(trace) {
  if (is.null(trace) || !nrow(trace)) {
    return(data.frame(
      variable = character(),
      last5_mean_range = numeric(),
      last5_sd = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  max_iter <- max(trace$iteration)
  last <- trace[trace$iteration > (max_iter - 5L), ]
  dplyr::bind_rows(lapply(split(last, last$variable), function(d) {
    data.frame(
      variable = d$variable[[1]],
      last5_mean = mean(d$chain_mean, na.rm = TRUE),
      last5_sd = stats::sd(d$chain_mean, na.rm = TRUE),
      last5_min = min(d$chain_mean, na.rm = TRUE),
      last5_max = max(d$chain_mean, na.rm = TRUE),
      last5_range = diff(range(d$chain_mean, na.rm = TRUE)),
      stringsAsFactors = FALSE
    )
  }))
}

observed_vs_imputed_numeric <- function(imp, varname) {
  where <- imp$where[, varname]
  observed <- imp$data[[varname]][!where]
  rows <- lapply(seq_len(imp$m), function(i) {
    comp <- mice::complete(imp, i)
    imputed <- comp[[varname]][where]
    data.frame(
      variable = varname,
      imputation = i,
      n_observed = sum(!is.na(observed)),
      n_imputed = sum(!is.na(imputed)),
      observed_mean = mean(observed, na.rm = TRUE),
      observed_sd = stats::sd(observed, na.rm = TRUE),
      observed_min = min(observed, na.rm = TRUE),
      observed_max = max(observed, na.rm = TRUE),
      imputed_mean = mean(imputed, na.rm = TRUE),
      imputed_sd = stats::sd(imputed, na.rm = TRUE),
      imputed_min = min(imputed, na.rm = TRUE),
      imputed_max = max(imputed, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

observed_vs_imputed_categorical <- function(imp, varname) {
  where <- imp$where[, varname]
  observed <- as.character(imp$data[[varname]][!where])
  levels_all <- levels(imp$data[[varname]])
  if (is.null(levels_all)) {
    levels_all <- sort(unique(c(observed, as.character(mice::complete(imp, 1)[[varname]]))))
  }
  rows <- list()
  obs_tab <- table(factor(observed, levels = levels_all))
  for (i in seq_len(imp$m)) {
    comp <- mice::complete(imp, i)
    imputed <- as.character(comp[[varname]][where])
    imp_tab <- table(factor(imputed, levels = levels_all))
    for (lvl in levels_all) {
      rows[[length(rows) + 1L]] <- data.frame(
        variable = varname,
        imputation = i,
        level = lvl,
        n_observed = as.integer(obs_tab[[lvl]]),
        n_imputed = as.integer(imp_tab[[lvl]]),
        stringsAsFactors = FALSE
      )
    }
  }
  dplyr::bind_rows(rows)
}

check_imputed_plausibility <- function(imp) {
  issues <- character()
  for (i in seq_len(imp$m)) {
    dat <- mice::complete(imp, i)
    if (any(!is.finite(dat$log2_wbc))) {
      issues <- c(issues, sprintf("imputation %s: non-finite log2_wbc", i))
    }
    wbc <- 2^dat$log2_wbc
    if (any(!is.finite(wbc) | wbc <= 0, na.rm = TRUE)) {
      issues <- c(issues, sprintf("imputation %s: nonpositive WBC after back-transform", i))
    }
    rg <- as.character(dat$risk_group_std)
    if (any(!rg %in% c("Low", "Standard", "High") & !is.na(rg))) {
      issues <- c(issues, sprintf("imputation %s: impossible risk-group level", i))
    }
    for (nm in c(
      "flt3_itd_std", "npm_std", "cebpa_std",
      "cytogenetics_t821_std", "cytogenetics_inv16_std",
      "cytogenetics_mll_std", "cytogenetics_monosomy7_std",
      "cns_disease_std"
    )) {
      vals <- as.character(dat[[nm]])
      if (any(!vals %in% c("No", "Yes") & !is.na(vals))) {
        issues <- c(issues, sprintf("imputation %s: impossible level in %s", i, nm))
      }
    }
    if (any(is.na(dat$log2_wbc)) || any(is.na(dat$risk_group_std))) {
      issues <- c(issues, sprintf("imputation %s: residual missingness in analysis covariates", i))
    }
  }
  unique(issues)
}

plot_mice_traces <- function(trace) {
  if (is.null(trace) || !nrow(trace)) {
    return(invisible(NULL))
  }
  keep_vars <- unique(trace$variable)
  keep_vars <- keep_vars[seq_len(min(length(keep_vars), 12L))]
  d <- trace[trace$variable %in% keep_vars, ]
  p <- ggplot2::ggplot(
    d,
    ggplot2::aes(x = iteration, y = chain_mean, group = imputation, color = imputation)
  ) +
    ggplot2::geom_line(alpha = 0.7, linewidth = 0.4) +
    ggplot2::facet_wrap(~variable, scales = "free_y") +
    ggplot2::guides(color = "none") +
    ggplot2::labs(
      title = "MICE chain means",
      subtitle = "Trace plots of imputation-chain means across iterations. Not used to select models.",
      x = "Iteration",
      y = "Chain mean"
    ) +
    ggplot2::theme_bw(base_size = 11)
  save_inference_plot(p, "mi_trace_plots.png", subdir = "mi", width = 2600, height = 2000)
}

write_mi_diagnostics <- function(imp, mi_frame, spec) {
  trace <- chain_trace_table(imp)
  stability <- summarize_chain_stability(trace)
  numeric_vars <- c("log2_wbc", "marrow_blasts_num", "peripheral_blasts_num")
  numeric_vars <- numeric_vars[numeric_vars %in% names(imp$data)]
  cat_vars <- c(
    "risk_group_std", "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std",
    "cns_disease_std", "race_aux", "ethnicity_aux"
  )
  cat_vars <- cat_vars[cat_vars %in% names(imp$data)]
  dist_num <- dplyr::bind_rows(lapply(numeric_vars, function(v) {
    if (any(imp$where[, v])) observed_vs_imputed_numeric(imp, v) else NULL
  }))
  dist_cat <- dplyr::bind_rows(lapply(cat_vars, function(v) {
    if (any(imp$where[, v])) observed_vs_imputed_categorical(imp, v) else NULL
  }))
  issues <- check_imputed_plausibility(imp)
  logged <- if (is.null(imp$loggedEvents) || !nrow(imp$loggedEvents)) {
    data.frame(iteration = integer(), imputation = integer(), note = character())
  } else {
    imp$loggedEvents
  }
  miss <- mice_missingness_summary(mi_frame)
  write_inference_csv(trace, "mi_trace_summary.csv", subdir = "mi")
  write_inference_csv(stability, "mi_chain_stability.csv", subdir = "mi")
  write_inference_csv(dist_num, "mi_distribution_summary.csv", subdir = "mi")
  write_inference_csv(dist_cat, "mi_categorical_frequency_summary.csv", subdir = "mi")
  write_inference_csv(miss, "mi_missingness_in_imputation_frame.csv", subdir = "mi")
  if (nrow(logged)) {
    write_inference_csv(logged, "mi_logged_events.csv", subdir = "mi")
  }
  plot_mice_traces(trace)
  n_issues <- length(issues)
  md <- c(
    "# Stage 6 multiple-imputation diagnostics",
    "",
    sprintf("- Software: mice %s", as.character(utils::packageVersion("mice"))),
    sprintf("- m = %s", imp$m),
    sprintf("- maxit = %s", imp$iteration),
    sprintf("- seed = %s", spec$missing_data$seed),
    sprintf("- Nelson-Aalen auxiliary: nonparametric Fleming-Harrington; not from a Cox model."),
    sprintf("- Outcome, time, ID, age, and sex were not imputed."),
    sprintf("- Auxiliary race used a collapsed 4-level factor (White / Black or African American / Asian / Other) because source OMB cells included n = 8 and n = 13. Race is not in either principal Cox model. This choice was made before viewing hazard ratios."),
    "",
    "## Plausibility",
    if (n_issues == 0L) {
      "No impossible imputed values were detected in completed analysis covariates."
    } else {
      paste(c("Issues:", paste("-", issues)), collapse = "\n")
    },
    "",
    "## Logged mice events",
    if (!nrow(logged)) {
      "No mice loggedEvents rows."
    } else {
      sprintf("%s loggedEvents rows were written to mi_logged_events.csv.", nrow(logged))
    },
    "",
    "## Convergence",
    "Inspect mi_trace_plots.png and mi_chain_stability.csv. Chain means in the last five iterations should not wander without bound.",
    "",
    "These diagnostics are not used to choose a more favorable Cox specification."
  )
  md_path <- file.path(INFERENCE_MI_DIR, "mi_diagnostics.md")
  writeLines(md, md_path)
  list(
    issues = issues,
    n_logged_events = nrow(logged),
    m = imp$m,
    maxit = imp$iteration,
    seed = spec$missing_data$seed,
    diagnostics_md = md_path
  )
}
