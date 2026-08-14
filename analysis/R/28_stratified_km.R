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
