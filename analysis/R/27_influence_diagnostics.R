# Influence diagnostics on complete-case principal models.
# Patient-level files stay under data/interim/stage6 (gitignored).
# Valid observations are not deleted for influence alone.

influence_summary_from_fit <- function(fit, data, model_name) {
  n <- nrow(data)
  dfb <- stats::residuals(fit, type = "dfbeta")
  coef_names <- names(stats::coef(fit))
  if (is.null(dim(dfb))) {
    dfb <- matrix(dfb, ncol = max(1L, length(coef_names)))
  }
  if (is.null(colnames(dfb)) || any(colnames(dfb) == "")) {
    colnames(dfb) <- coef_names[seq_len(ncol(dfb))]
  }
  deviance_res <- as.numeric(stats::residuals(fit, type = "deviance"))
  martingale_res <- as.numeric(stats::residuals(fit, type = "martingale"))
  thresh <- 2 / sqrt(n)
  max_abs <- apply(abs(dfb), 2, function(x) max(x, na.rm = TRUE))
  n_over <- apply(abs(dfb), 2, function(x) sum(x > thresh, na.rm = TRUE))
  summary_tbl <- data.frame(
    model = model_name,
    term = colnames(dfb),
    n = n,
    dfbeta_threshold_2_over_sqrt_n = thresh,
    max_abs_dfbeta = as.numeric(max_abs),
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
    secondary_max_dfbeta = max(secondary$summary$max_abs_dfbeta)
  )
}
