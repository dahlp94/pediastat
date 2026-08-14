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
  write_csv_artifact(utils::head(patterns, 15), "missingness_patterns_top15.csv")
  save_missingness_heatmap(cohort)
  n_complete <- sum(patterns$n_variables_missing == 0)
  list(
    by_variable = by_var,
    patterns = patterns,
    n_complete_on_tabulated = n_complete,
    n_distinct_patterns = nrow(patterns)
  )
}
