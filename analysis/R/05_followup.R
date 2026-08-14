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
