# Overall Table 1, continuous distributions, and categorical audit.
# No stratification by survival. No p-values.

table1_data <- function(cohort) {
  dplyr::tibble(
    `Age at diagnosis, years` = cohort$age_at_diagnosis_years,
    `Sex at birth` = cohort$sex_at_birth_table,
    `Race` = cohort$race_table,
    `Ethnicity` = cohort$ethnicity_table,
    `WBC at diagnosis, x10^3/mcL` = cohort$wbc_at_diagnosis_num,
    `Risk group` = cohort$risk_group_table,
    `FLT3/ITD` = factor(cohort$flt3_itd_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `NPM mutation` = factor(cohort$npm_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `CEBPA mutation` = factor(cohort$cebpa_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `FAB category` = cohort$fab_table,
    `CNS disease` = factor(cohort$cns_disease_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `Bone marrow blasts, %` = cohort$marrow_blasts_num,
    `Peripheral blasts, %` = cohort$peripheral_blasts_num,
    `t(8;21)` = factor(cohort$cytogenetics_t821_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `inv(16)` = factor(cohort$cytogenetics_inv16_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `MLL` = factor(cohort$cytogenetics_mll_table, levels = c("Yes", "No", "Unknown", "Missing")),
    `Monosomy 7` = factor(cohort$cytogenetics_monosomy7_table, levels = c("Yes", "No", "Unknown", "Missing"))
  )
}

build_table1 <- function(cohort) {
  tbl <- table1_data(cohort) %>%
    gtsummary::tbl_summary(
      statistic = list(
        gtsummary::all_continuous() ~ "{median} ({p25}, {p75})",
        gtsummary::all_categorical() ~ "{n} ({p}%)"
      ),
      digits = list(
        gtsummary::all_continuous() ~ c(1, 1, 1),
        gtsummary::all_categorical() ~ c(0, 1)
      ),
      missing = "no",
      percent = "column"
    ) %>%
    gtsummary::modify_header(
      label ~ "**Characteristic**",
      gtsummary::all_stat_cols() ~ "**Overall**  \nN = {N}"
    ) %>%
    gtsummary::modify_footnote(
      gtsummary::all_stat_cols() ~ paste(
        "Median (Q1, Q3) for continuous variables; n (%) for categorical variables.",
        "Percentages use the full primary cohort (N = 1978) as the denominator.",
        "Unknown is retained as a reported category and is not treated as censoring or as a modeled reference level.",
        "Missing is structural absence of a source value.",
        "FLT3/ITD, NPM, CEBPA, and lesion flags display case-harmonized Yes/No; source mixed case is documented in the categorical audit.",
        "No p-values. Not stratified by vital status or any survival outcome."
      )
    ) %>%
    gtsummary::bold_labels()
  if ("p.value" %in% names(tbl$table_body)) {
    stop("Table 1 unexpectedly contains a p-value column.", call. = FALSE)
  }
  tbl
}

export_table1 <- function(tbl) {
  csv_path <- file.path(DESCRIPTIVE_DIR, "table1_primary_cohort.csv")
  html_path <- file.path(DESCRIPTIVE_DIR, "table1_primary_cohort.html")
  as.data.frame(tbl) %>%
    utils::write.csv(csv_path, row.names = FALSE)
  gt_tbl <- gtsummary::as_gt(tbl) %>%
    gt::tab_header(
      title = "Table 1. Baseline characteristics of the primary pediatric AML cohort",
      subtitle = "Prespecified overall cohort. Not stratified by survival."
    )
  gt::gtsave(gt_tbl, filename = html_path)
  list(csv = csv_path, html = html_path, has_pvalue = "p.value" %in% names(as.data.frame(tbl)))
}

summarize_continuous <- function(x, variable, units) {
  observed <- x[!is.na(x)]
  n_obs <- length(observed)
  n_miss <- sum(is.na(x))
  qs <- quantile_named(observed, c(0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99))
  data.frame(
    variable = variable,
    units = units,
    n_observed = n_obs,
    n_missing = n_miss,
    missing_percent = round(100 * n_miss / length(x), 2),
    mean = if (n_obs) mean(observed) else NA_real_,
    sd = if (n_obs) stats::sd(observed) else NA_real_,
    median = if (n_obs) stats::median(observed) else NA_real_,
    q1 = if (n_obs) qs[4] else NA_real_,
    q3 = if (n_obs) qs[6] else NA_real_,
    iqr = if (n_obs) qs[6] - qs[4] else NA_real_,
    min = if (n_obs) min(observed) else NA_real_,
    max = if (n_obs) max(observed) else NA_real_,
    p01 = if (n_obs) qs[1] else NA_real_,
    p05 = if (n_obs) qs[2] else NA_real_,
    p10 = if (n_obs) qs[3] else NA_real_,
    p90 = if (n_obs) qs[7] else NA_real_,
    p95 = if (n_obs) qs[8] else NA_real_,
    p99 = if (n_obs) qs[9] else NA_real_,
    n_zero = sum(observed == 0),
    n_negative = sum(observed < 0),
    n_above_100 = if (grepl("blast", variable)) sum(observed > 100) else NA_integer_,
    skewness = if (n_obs > 2L) {
      m <- mean(observed)
      s <- stats::sd(observed)
      if (s == 0) 0 else mean((observed - m)^3) / (s^3)
    } else {
      NA_real_
    },
    stringsAsFactors = FALSE
  )
}

continuous_summaries <- function(cohort) {
  dplyr::bind_rows(
    summarize_continuous(cohort$age_at_diagnosis_years, "age_at_diagnosis_years", "years"),
    summarize_continuous(cohort$age_at_diagnosis_days, "age_at_diagnosis_days", "days"),
    summarize_continuous(cohort$wbc_at_diagnosis_num, "wbc_at_diagnosis", "x10^3/mcL"),
    summarize_continuous(cohort$marrow_blasts_num, "marrow_blasts", "percent"),
    summarize_continuous(cohort$peripheral_blasts_num, "peripheral_blasts", "percent")
  )
}

save_distribution_figures <- function(cohort) {
  theme_desc <- ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 12))

  p_age <- ggplot2::ggplot(cohort, ggplot2::aes(x = age_at_diagnosis_years)) +
    ggplot2::geom_histogram(bins = 30, fill = "#4C78A8", color = "white") +
    ggplot2::labs(
      title = "Age at diagnosis",
      x = "Years",
      y = "Number of analysis persons",
      caption = "Primary cohort, N = 1978. Age is complete by eligibility."
    ) +
    theme_desc
  ggplot2::ggsave(file.path(FIGURE_DIR, "age_at_diagnosis_histogram.png"), p_age, width = 7, height = 4.5, dpi = 200)

  p_wbc <- ggplot2::ggplot(
    dplyr::filter(cohort, !is.na(wbc_at_diagnosis_num)),
    ggplot2::aes(x = wbc_at_diagnosis_num)
  ) +
    ggplot2::geom_histogram(bins = 40, fill = "#F58518", color = "white") +
    ggplot2::labs(
      title = "WBC at diagnosis (raw scale)",
      x = "WBC (x10^3/mcL)",
      y = "Number of analysis persons",
      caption = "Observed values only. Strong right skew is expected; this plot does not choose a model transformation."
    ) +
    theme_desc
  ggplot2::ggsave(file.path(FIGURE_DIR, "wbc_histogram.png"), p_wbc, width = 7, height = 4.5, dpi = 200)

  p_wbc_log <- ggplot2::ggplot(
    dplyr::filter(cohort, !is.na(wbc_at_diagnosis_num) & wbc_at_diagnosis_num > 0),
    ggplot2::aes(x = wbc_at_diagnosis_num)
  ) +
    ggplot2::geom_histogram(bins = 40, fill = "#F58518", color = "white") +
    ggplot2::scale_x_log10(labels = scales::label_number()) +
    ggplot2::labs(
      title = "WBC at diagnosis (log10 scale)",
      x = "WBC (x10^3/mcL), log10 scale",
      y = "Number of analysis persons",
      caption = "All observed WBC values are > 0, so a log axis is defined. Not an outcome-driven transformation."
    ) +
    theme_desc
  ggplot2::ggsave(file.path(FIGURE_DIR, "wbc_histogram_log10.png"), p_wbc_log, width = 7, height = 4.5, dpi = 200)

  p_marrow <- ggplot2::ggplot(
    dplyr::filter(cohort, !is.na(marrow_blasts_num)),
    ggplot2::aes(x = marrow_blasts_num)
  ) +
    ggplot2::geom_histogram(binwidth = 5, boundary = 0, fill = "#54A24B", color = "white") +
    ggplot2::labs(
      title = "Bone marrow leukemic blast percentage",
      x = "Marrow blasts (%)",
      y = "Number of analysis persons"
    ) +
    theme_desc
  ggplot2::ggsave(file.path(FIGURE_DIR, "marrow_blasts_histogram.png"), p_marrow, width = 7, height = 4.5, dpi = 200)

  p_peripheral <- ggplot2::ggplot(
    dplyr::filter(cohort, !is.na(peripheral_blasts_num)),
    ggplot2::aes(x = peripheral_blasts_num)
  ) +
    ggplot2::geom_histogram(binwidth = 5, boundary = 0, fill = "#B279A2", color = "white") +
    ggplot2::labs(
      title = "Peripheral blast percentage",
      x = "Peripheral blasts (%)",
      y = "Number of analysis persons"
    ) +
    theme_desc
  ggplot2::ggsave(file.path(FIGURE_DIR, "peripheral_blasts_histogram.png"), p_peripheral, width = 7, height = 4.5, dpi = 200)

  invisible(TRUE)
}

audit_one_categorical <- function(raw, missingness, variable, display = NULL) {
  raw_chr <- ifelse(is.na(raw), "", as.character(raw))
  miss <- ifelse(is.na(missingness), "structurally_missing", as.character(missingness))
  n <- length(raw_chr)
  tab <- as.data.frame(table(category = raw_chr, missingness = miss), stringsAsFactors = FALSE)
  names(tab)[names(tab) == "Freq"] <- "n"
  tab$variable <- variable
  tab$percent <- round(100 * tab$n / n, 2)
  tab$is_missing_class <- tab$missingness != "observed"
  tab$is_unknown <- tab$missingness == "unknown" | tolower(tab$category) %in% c("unknown", "unspecified")
  tab$is_rare <- tab$n > 0 & tab$n < SPARSE_N & tab$missingness == "observed"
  tab$recommendation <- dplyr::case_when(
    tab$n == 0 ~ NA_character_,
    tab$variable == "risk_group" & tab$category %in% c("10", "30") ~
      "NEEDS CLINICAL REVIEW",
    toupper(tab$category) %in% c("YES", "NO") ~
      "KEEP",
    tab$variable == "fab" & tab$category %in% c("Not classified", "M0 Undifferentiated", "M6") ~
      "POTENTIAL COLLAPSE BEFORE MODELING",
    tab$variable == "race" & tab$is_rare ~ "POTENTIAL COLLAPSE BEFORE MODELING",
    tab$is_rare ~ "POTENTIAL COLLAPSE BEFORE MODELING",
    TRUE ~ "KEEP"
  )
  tab[, c(
    "variable", "category", "missingness", "n", "percent",
    "is_unknown", "is_rare", "recommendation"
  )]
}

categorical_audit <- function(cohort) {
  specs <- list(
    list("sex_at_birth", cohort$sex_at_birth, cohort$sex_at_birth_missingness),
    list("race", cohort$race, cohort$race_missingness),
    list("ethnicity", cohort$ethnicity, cohort$ethnicity_missingness),
    list("risk_group", cohort$risk_group, cohort$risk_group_missingness),
    list("flt3_itd", cohort$flt3_itd, cohort$flt3_itd_missingness),
    list("npm", cohort$npm, cohort$npm_missingness),
    list("cebpa", cohort$cebpa, cohort$cebpa_missingness),
    list("fab", cohort$fab, cohort$fab_missingness),
    list("cns_disease", cohort$cns_disease, cohort$cns_disease_missingness),
    list("cytogenetics_t821", cohort$cytogenetics_t821, cohort$cytogenetics_t821_missingness),
    list("cytogenetics_inv16", cohort$cytogenetics_inv16, cohort$cytogenetics_inv16_missingness),
    list("cytogenetics_mll", cohort$cytogenetics_mll, cohort$cytogenetics_mll_missingness),
    list("cytogenetics_monosomy7", cohort$cytogenetics_monosomy7, cohort$cytogenetics_monosomy7_missingness),
    list("primary_cytogenetic_code", cohort$primary_cytogenetic_code, cohort$primary_cytogenetic_code_missingness)
  )
  rows <- lapply(specs, function(item) {
    audit_one_categorical(item[[2]], item[[3]], item[[1]])
  })
  out <- dplyr::bind_rows(rows)
  out[out$n > 0, ]
}

run_baseline_descriptives <- function(cohort) {
  tbl <- build_table1(cohort)
  paths <- export_table1(tbl)
  cont <- continuous_summaries(cohort)
  write_csv_artifact(cont, "continuous_distribution_summary.csv")
  save_distribution_figures(cohort)
  cats <- categorical_audit(cohort)
  write_csv_artifact(cats, "categorical_level_audit.csv")
  list(table1 = tbl, table1_paths = paths, continuous = cont, categorical = cats)
}
# Missingness characterization. No imputation. No missingness-vs-survival tests.

missingness_variable_table <- function(cohort, long_baseline) {
  concepts <- unique(long_baseline$concept)
  rows <- lapply(concepts, function(concept_name) {
    sub <- long_baseline[long_baseline$concept == concept_name, ]
    n <- nrow(sub)
    n_obs <- sum(sub$missingness_class == "observed", na.rm = TRUE)
    n_unknown <- sum(sub$missingness_class == "unknown", na.rm = TRUE)
    n_nr <- sum(sub$missingness_class == "not_reported", na.rm = TRUE)
    n_struct <- sum(sub$missingness_class == "structurally_missing", na.rm = TRUE)
    n_conflict <- sum(as.logical(sub$conflict_flag), na.rm = TRUE)
    n_missing_broad <- n - n_obs
    data.frame(
      concept = concept_name,
      n = n,
      observed_n = n_obs,
      missing_n = n_missing_broad,
      missing_percent = round(100 * n_missing_broad / n, 2),
      unknown_n = n_unknown,
      not_reported_n = n_nr,
      structurally_missing_n = n_struct,
      conflict_n = n_conflict,
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

missingness_indicator_matrix <- function(cohort) {
  vars <- c(
    "wbc_at_diagnosis", "risk_group", "flt3_itd", "npm", "cebpa", "fab",
    "cns_disease", "marrow_blasts", "peripheral_blasts",
    "cytogenetics_t821", "cytogenetics_inv16", "cytogenetics_mll",
    "cytogenetics_monosomy7", "primary_cytogenetic_code", "race", "ethnicity"
  )
  indicators <- lapply(vars, function(v) {
    miss_col <- paste0(v, "_missingness")
    as.integer(cohort[[miss_col]] != "observed")
  })
  mat <- as.data.frame(indicators, optional = TRUE)
  names(mat) <- vars
  mat
}

missingness_pattern_summary <- function(cohort) {
  mat <- missingness_indicator_matrix(cohort)
  key <- apply(mat, 1, paste, collapse = "")
  tab <- as.data.frame(table(pattern = key), stringsAsFactors = FALSE)
  names(tab)[2] <- "n"
  tab$percent <- round(100 * tab$n / nrow(mat), 2)
  tab$n_variables_missing <- nchar(gsub("0", "", tab$pattern))
  decode <- vapply(tab$pattern, function(p) {
    bits <- strsplit(p, "")[[1]] == "1"
    vars <- names(mat)[bits]
    if (!length(vars)) "complete on tabulated covariates" else paste(vars, collapse = " | ")
  }, character(1))
  tab$variables_missing <- decode
  tab <- tab[order(-tab$n), ]
  tab$rank <- seq_len(nrow(tab))
  tab[, c("rank", "n", "percent", "n_variables_missing", "variables_missing")]
}

save_missingness_heatmap <- function(cohort) {
  mat <- missingness_indicator_matrix(cohort)
  long <- mat
  long$row_id <- seq_len(nrow(long))
  long <- tidyr::pivot_longer(long, -row_id, names_to = "variable", values_to = "missing")
  # Order rows by missingness pattern so the figure stays aggregate and does not use IDs.
  pattern <- apply(mat, 1, paste, collapse = "")
  ord <- order(pattern, decreasing = TRUE)
  map <- match(seq_len(nrow(mat)), ord)
  long$row_plot <- map[long$row_id]
  p <- ggplot2::ggplot(long, ggplot2::aes(x = variable, y = row_plot, fill = factor(missing))) +
    ggplot2::geom_raster() +
    ggplot2::scale_fill_manual(
      values = c("0" = "#F7F7F7", "1" = "#C44E52"),
      labels = c("Observed", "Not observed"),
      name = NULL
    ) +
    ggplot2::labs(
      title = "Missingness pattern in the primary cohort",
      x = NULL,
      y = "Analysis persons (ordered by pattern, identifiers omitted)",
      caption = "Not observed includes Unknown, Not reported, and structural missing. No identifiers are plotted."
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      axis.text.y = ggplot2::element_blank(),
      axis.ticks.y = ggplot2::element_blank()
    )
  ggplot2::ggsave(
    file.path(FIGURE_DIR, "missingness_heatmap.png"),
    p,
    width = 10,
    height = 6,
    dpi = 200
  )
}

run_missingness <- function(cohort, long_baseline) {
  by_var <- missingness_variable_table(cohort, long_baseline)
  write_csv_artifact(by_var, "missingness_by_variable.csv")
  patterns <- missingness_pattern_summary(cohort)
  write_csv_artifact(patterns, "missingness_patterns.csv")
  save_missingness_heatmap(cohort)
  n_complete <- sum(patterns$n_variables_missing == 0)
  list(
    by_variable = by_var,
    patterns = patterns,
    n_complete_on_tabulated = n_complete,
    n_distinct_patterns = nrow(patterns)
  )
}
# Overall Kaplan-Meier only. No predictor strata. No log-rank. No Cox.

fit_overall_km <- function(cohort) {
  survival::survfit(
    survival::Surv(os_years, os_event) ~ 1,
    data = cohort,
    conf.type = "log-log"
  )
}

km_timepoint_estimates <- function(fit) {
  times <- c(1, 3, 5, 10)
  summarized <- summary(fit, times = times, extend = TRUE)
  data.frame(
    time_years = summarized$time,
    n_risk = summarized$n.risk,
    n_event = summarized$n.event,
    survival = summarized$surv,
    surv_lcl = summarized$lower,
    surv_ucl = summarized$upper,
    stringsAsFactors = FALSE
  )
}

median_os_summary <- function(fit) {
  tbl <- surv_quantile(fit, 0.5)
  median_est <- unname(tbl["est"])
  lcl <- unname(tbl["lcl"])
  ucl <- unname(tbl["ucl"])
  estimable <- !is.na(median_est)
  list(
    estimable = estimable,
    median_os_years = if (estimable) median_est else NA_real_,
    median_os_lcl_years = if (estimable) lcl else NA_real_,
    median_os_ucl_years = if (estimable) ucl else NA_real_,
    statement = if (estimable) {
      sprintf(
        "Median OS = %.2f years (95%% CI %.2f to %.2f).",
        median_est,
        lcl,
        ucl
      )
    } else {
      "Median OS not reached (Kaplan-Meier survival remains above 0.50 throughout supported follow-up)."
    }
  )
}

number_at_risk_table <- function(fit) {
  summarized <- summary(fit, times = KM_TIMES_YEARS, extend = TRUE)
  data.frame(
    time_years = summarized$time,
    n_risk = summarized$n.risk,
    n_event = summarized$n.event,
    n_censor = summarized$n.censor,
    survival = summarized$surv,
    stringsAsFactors = FALSE
  )
}

save_overall_km_figure <- function(fit, n_risk) {
  km_tidy <- broom::tidy(fit)
  xmax <- max(c(km_tidy$time, 10), na.rm = TRUE)
  p_curve <- ggplot2::ggplot(km_tidy, ggplot2::aes(x = time, y = estimate)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = conf.low, ymax = conf.high),
      fill = "#4C78A8",
      alpha = 0.2,
      na.rm = TRUE
    ) +
    ggplot2::geom_step(color = "#2F4B7C", linewidth = 0.9, na.rm = TRUE) +
    ggplot2::coord_cartesian(xlim = c(0, xmax), ylim = c(0, 1)) +
    ggplot2::scale_x_continuous(breaks = c(0, 1, 3, 5, 10)) +
    ggplot2::scale_y_continuous(
      breaks = seq(0, 1, 0.2),
      labels = scales::label_percent(accuracy = 1)
    ) +
    ggplot2::labs(
      title = "Overall survival, primary pediatric AML cohort",
      subtitle = "N = 1978 analysis persons. Kaplan-Meier estimate with 95% confidence band. Not stratified.",
      x = "Years from initial pathologic diagnosis",
      y = "Overall survival probability"
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  risk_df <- n_risk
  risk_df$label <- as.character(risk_df$n_risk)
  p_risk <- ggplot2::ggplot(risk_df, ggplot2::aes(x = time_years, y = 1, label = label)) +
    ggplot2::geom_text(size = 3.3) +
    ggplot2::coord_cartesian(xlim = c(0, xmax)) +
    ggplot2::scale_x_continuous(breaks = c(0, 1, 3, 5, 10)) +
    ggplot2::labs(x = NULL, y = "No. at risk") +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(
      axis.text.y = ggplot2::element_blank(),
      axis.ticks.y = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(0, 5.5, 5.5, 5.5)
    )

  g1 <- ggplot2::ggplotGrob(p_curve)
  g2 <- ggplot2::ggplotGrob(p_risk)
  g2$widths <- g1$widths
  png(
    file.path(FIGURE_DIR, "overall_kaplan_meier.png"),
    width = 2400,
    height = 1800,
    res = 220
  )
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(
    2, 1, heights = grid::unit(c(3, 0.7), "null")
  )))
  grid::pushViewport(grid::viewport(layout.pos.row = 1))
  grid::grid.draw(g1)
  grid::popViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 2))
  grid::grid.draw(g2)
  grid::popViewport(2)
  dev.off()
}

validate_km_fit <- function(fit, estimates) {
  km_tidy <- broom::tidy(fit)
  if (any(km_tidy$estimate < 0 | km_tidy$estimate > 1, na.rm = TRUE)) {
    stop("KM survival probability outside [0, 1].", call. = FALSE)
  }
  est <- km_tidy$estimate[!is.na(km_tidy$estimate)]
  if (any(diff(est) > 1e-10)) {
    stop("KM curve increased; expected non-increasing survival.", call. = FALSE)
  }
  if (any(estimates$survival < 0 | estimates$survival > 1, na.rm = TRUE)) {
    stop("Time-point survival estimates outside [0, 1].", call. = FALSE)
  }
  invisible(TRUE)
}

run_overall_survival <- function(cohort) {
  if (anyNA(cohort$os_event) || anyNA(cohort$os_years) || any(cohort$os_years < 0)) {
    stop("KM input has missing event/time or negative times.", call. = FALSE)
  }
  fit <- fit_overall_km(cohort)
  estimates <- km_timepoint_estimates(fit)
  median_os <- median_os_summary(fit)
  n_risk <- number_at_risk_table(fit)
  validate_km_fit(fit, estimates)
  write_csv_artifact(estimates, "overall_survival_estimates.csv")
  write_csv_artifact(n_risk, "number_at_risk.csv")
  save_overall_km_figure(fit, n_risk)
  list(fit = fit, estimates = estimates, median_os = median_os, n_risk = n_risk)
}
# Reverse Kaplan-Meier follow-up. Deaths are censored; original censoring is the event.

fit_reverse_km <- function(cohort) {
  follow_event <- as.integer(1L - cohort$os_event)
  survival::survfit(
    survival::Surv(os_years, follow_event) ~ 1,
    data = cohort,
    conf.type = "log-log"
  )
}

reverse_km_quantiles <- function(fit) {
  probs <- c(0.25, 0.50, 0.75)
  rows <- lapply(probs, function(p) {
    q <- surv_quantile(fit, p)
    data.frame(
      quantile = p,
      years = unname(q["est"]),
      lcl = unname(q["lcl"]),
      ucl = unname(q["ucl"]),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

run_followup <- function(cohort, km_result) {
  fit <- fit_reverse_km(cohort)
  qs <- reverse_km_quantiles(fit)
  median_row <- qs[qs$quantile == 0.50, ]
  estimable <- !is.na(median_row$years)
  observed_days <- cohort$os_days
  summary_list <- list(
    method = "reverse_kaplan_meier",
    interpretation = paste(
      "Reverse Kaplan-Meier estimates potential follow-up by treating deaths as censored",
      "and treating originally censored observations as events.",
      "This is not median overall survival and is not the median of os_days."
    ),
    median_followup_estimable = estimable,
    median_followup_years = if (estimable) median_row$years else NA_real_,
    median_followup_lcl_years = if (estimable) median_row$lcl else NA_real_,
    median_followup_ucl_years = if (estimable) median_row$ucl else NA_real_,
    q25_followup_years = qs$years[qs$quantile == 0.25],
    q75_followup_years = qs$years[qs$quantile == 0.75],
    statement = if (estimable) {
      sprintf(
        "Median potential follow-up by reverse KM: %.2f years (95%% CI %.2f to %.2f).",
        median_row$years,
        median_row$lcl,
        median_row$ucl
      )
    } else {
      "Reverse Kaplan-Meier median follow-up was not estimable; no substitute statistic was used."
    },
    observed_os_days_min = min(observed_days),
    observed_os_days_max = max(observed_days),
    observed_os_days_median = stats::median(observed_days),
    observed_os_years_min = min(cohort$os_years),
    observed_os_years_max = max(cohort$os_years),
    note_on_observed_median = paste(
      "The median of observed os_days is retained only as a range descriptor.",
      "It must not be labeled median follow-up or Kaplan-Meier median survival."
    )
  )
  write_json_artifact(summary_list, "followup_summary.json")
  write_csv_artifact(qs, "followup_reverse_km_quantiles.csv")
  c(summary_list, list(quantiles = qs, fit = fit))
}
# Provenance and compact descriptive-analysis summaries.

MODEL_PLANNING_ARTIFACTS <- c(
  "core_candidate_readiness.csv",
  "redundancy_continuous_spearman.csv",
  "redundancy_findings.csv",
  "redundancy_primary_code_by_inv16.csv",
  "redundancy_primary_code_by_mll.csv",
  "redundancy_primary_code_by_monosomy7.csv",
  "redundancy_primary_code_by_t821.csv",
  "redundancy_risk_group_by_flt3.csv",
  "redundancy_risk_group_by_t821.csv",
  "missingness_patterns_top15.csv"
)

remove_stale_stage4_artifacts <- function() {
  paths <- file.path(DESCRIPTIVE_DIR, MODEL_PLANNING_ARTIFACTS)
  existing <- paths[file.exists(paths)]
  if (length(existing)) {
    unlink(existing)
  }
  invisible(existing)
}

source_provenance_table <- function(long_baseline) {
  family <- workbook_family(long_baseline$source_workbook)
  family[long_baseline$source_kind == "gdc_cases_api"] <- "GDC"
  family[is.na(family)] <- "none/unresolved"
  long_baseline$family <- family

  families <- c(
    "AML1031",
    "Discovery",
    "Validation",
    "LowDepth",
    "additional",
    "GDC",
    "none/unresolved"
  )

  rows <- lapply(unique(long_baseline$concept), function(concept_name) {
    sub <- long_baseline[long_baseline$concept == concept_name, ]
    observed <- sub[sub$missingness_class == "observed", ]
    counts <- table(factor(observed$family, levels = families))

    data.frame(
      concept = concept_name,
      n_primary_cohort = nrow(sub),
      n_observed = nrow(observed),
      n_AML1031 = unname(counts["AML1031"]),
      n_Discovery = unname(counts["Discovery"]),
      n_Validation = unname(counts["Validation"]),
      n_LowDepth = unname(counts["LowDepth"]),
      n_additional = unname(counts["additional"]),
      n_GDC = unname(counts["GDC"]),
      n_none_unresolved_observed = unname(counts["none/unresolved"]),
      n_conflict_flag = sum(as.logical(sub$conflict_flag), na.rm = TRUE),
      n_not_observed = sum(sub$missingness_class != "observed"),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

endpoint_description <- function(cohort, km_result, followup) {
  list(
    primary_cohort_n = nrow(cohort),
    deaths = sum(cohort$os_event == 1L),
    censored = sum(cohort$os_event == 0L),
    crude_event_percent = round(100 * mean(cohort$os_event == 1L), 2),
    crude_event_percent_note = paste(
      "Crude event percentage is deaths/N, not cumulative mortality risk.",
      "Use Kaplan-Meier for survival probability."
    ),
    observed_os_days_min = min(cohort$os_days),
    observed_os_days_max = max(cohort$os_days),
    observed_os_years_min = min(cohort$os_years),
    observed_os_years_max = max(cohort$os_years),
    reverse_km_followup = followup$statement,
    median_os = km_result$median_os$statement,
    index_date_missing_qa_flag_n = sum(
      grepl(
        "index_date_missing",
        as.character(cohort$qa_flags),
        fixed = TRUE
      )
    )
  )
}

run_stage4_outputs <- function(
  loaded,
  descriptives,
  km_result,
  followup,
  provenance
) {
  remove_stale_stage4_artifacts()

  write_json_artifact(
    loaded$accounting,
    "population_accounting.json"
  )
  write_csv_artifact(
    provenance,
    "baseline_source_provenance.csv"
  )

  endpoint <- endpoint_description(
    loaded$cohort,
    km_result,
    followup
  )
  write_json_artifact(
    endpoint,
    "endpoint_followup_description.json"
  )

  session <- session_info_list()
  write_json_artifact(
    session,
    "r_session_info.json"
  )
  write_json_artifact(
    list(
      km_1_3_5_year = km_result$estimates[
        km_result$estimates$time_years %in% c(1, 3, 5),
      ],
      median_os = km_result$median_os,
      n_risk = km_result$n_risk,
      table1_has_pvalue = isTRUE(
        descriptives$table1_paths$has_pvalue
      )
    ),
    "overall_survival_summary.json"
  )

  list(
    accounting = loaded$accounting,
    endpoint = endpoint,
    session = session
  )
}
