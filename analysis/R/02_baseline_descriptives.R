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
