# Aggregate Stage 6 tables, forest plots, metadata, and MI vs complete-case comparison.

mi_cc_comparison <- function(mi_tbl, cc_tbl) {
  merged <- merge(
    mi_tbl[, c("term", "predictor_label", "hr", "hr_lcl", "hr_ucl", "p_value")],
    cc_tbl[, c("term", "hr", "hr_lcl", "hr_ucl", "p_value", "n", "deaths")],
    by = "term",
    suffixes = c("_mi", "_cc")
  )
  merged$direction_same <- sign(log(merged$hr_mi)) == sign(log(merged$hr_cc))
  merged$hr_ratio_cc_over_mi <- merged$hr_cc / merged$hr_mi
  merged$qualitative <- vapply(seq_len(nrow(merged)), function(i) {
    mi_hr <- merged$hr_mi[[i]]
    cc_hr <- merged$hr_cc[[i]]
    mi_crosses <- merged$hr_lcl_mi[[i]] < 1 && merged$hr_ucl_mi[[i]] > 1
    cc_crosses <- merged$hr_lcl_cc[[i]] < 1 && merged$hr_ucl_cc[[i]] > 1
    rel <- abs(log(cc_hr) - log(mi_hr))
    if (isTRUE(mi_crosses) && isTRUE(cc_crosses)) {
      "similar"
    } else if (rel < log(1.15) && identical(merged$direction_same[[i]], TRUE)) {
      "similar"
    } else if (!identical(merged$direction_same[[i]], TRUE) &&
               !(isTRUE(mi_crosses) && isTRUE(cc_crosses))) {
      "meaningfully different"
    } else if (rel >= log(1.25)) {
      "meaningfully different"
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

stage6_session_info <- function() {
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

write_stage6_outputs <- function(spec, primary_mi, secondary_mi, primary_cc, secondary_cc,
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
  session <- stage6_session_info()
  write_inference_json(session, "r_session_info.json")
  write_model_metadata(
    spec, primary_cc, secondary_cc, primary_conc, secondary_conc, ph, mi_diag, session
  )
  list(primary_comparison = primary_cmp, secondary_comparison = secondary_cmp, session = session)
}
