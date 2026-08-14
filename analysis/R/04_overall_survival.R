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
