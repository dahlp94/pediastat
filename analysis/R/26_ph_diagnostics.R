# Proportional-hazards diagnostics and prespecified remediation.

PH_ROLES_PRIMARY <- c(
  age5 = "nuisance",
  sex_std = "nuisance",
  log2_wbc = "important",
  risk_group_std = "important"
)

PH_ROLES_SECONDARY <- c(
  age5 = "nuisance",
  sex_std = "nuisance",
  log2_wbc = "nuisance",
  flt3_itd_std = "important",
  npm_std = "important",
  cebpa_std = "important",
  cytogenetics_t821_std = "important",
  cytogenetics_inv16_std = "important",
  cytogenetics_mll_std = "important",
  cytogenetics_monosomy7_std = "important"
)

# Frozen before inspecting results: combine test, |rho|, and scientific role.
# A p-value alone is not treated as proof of a material violation.
classify_ph <- function(p, rho, role) {
  p <- suppressWarnings(as.numeric(p)[1])
  rho <- suppressWarnings(as.numeric(rho)[1])
  if (isTRUE(is.na(p))) {
    return("UNCERTAIN")
  }
  if (isTRUE(is.na(rho))) {
    if (p >= 0.05) {
      return("NO MATERIAL EVIDENCE OF VIOLATION")
    }
    return("UNCERTAIN")
  }
  abs_rho <- abs(rho)
  if (p >= 0.05 && abs_rho < 0.10) {
    return("NO MATERIAL EVIDENCE OF VIOLATION")
  }
  if (p >= 0.05 && abs_rho >= 0.10) {
    return("UNCERTAIN")
  }
  if (p < 0.05 && abs_rho < 0.10) {
    return("MINOR DEPARTURE")
  }
  if (p < 0.05 && abs_rho < 0.20) {
    if (identical(role, "nuisance")) {
      return("MINOR DEPARTURE")
    }
    return("MATERIAL VIOLATION")
  }
  "MATERIAL VIOLATION"
}

normalize_zph_term <- function(term) {
  term <- gsub("TRUE$", "", term)
  term <- gsub("Male$", "", term)
  term <- gsub("Female$", "", term)
  term <- gsub("Standard$", "", term)
  term <- gsub("High$", "", term)
  term <- gsub("Low$", "", term)
  term <- gsub("Yes$", "", term)
  term <- gsub("No$", "", term)
  term
}

zph_table <- function(fit, model_name, source, roles) {
  z <- survival::cox.zph(fit)
  tbl <- as.data.frame(z$table)
  tbl$term <- rownames(z$table)
  rownames(tbl) <- NULL
  if (!("rho" %in% names(tbl))) {
    tbl$rho <- NA_real_
  }
  if (!is.null(z$y) && !is.null(z$x) && ncol(as.matrix(z$y)) > 0) {
    ymat <- as.matrix(z$y)
    for (nm in colnames(ymat)) {
      idx <- which(tbl$term == nm)
      if (length(idx) == 1L && isTRUE(is.na(tbl$rho[idx]))) {
        tbl$rho[idx] <- suppressWarnings(
          stats::cor(z$x, ymat[, nm], use = "complete.obs")
        )
      }
    }
  }
  if (!("p" %in% names(tbl)) && "p" %in% names(z$table)) {
    tbl$p <- z$table[, "p"]
  }
  pcol <- intersect(c("p", "Pr(>|z|)", "P"), names(tbl))
  if (length(pcol) && !("p" %in% names(tbl))) {
    tbl$p <- tbl[[pcol[[1]]]]
  }
  tbl$model <- model_name
  tbl$source <- source
  tbl$base_term <- vapply(tbl$term, function(nm) {
    if (identical(nm, "GLOBAL")) return("GLOBAL")
    normalize_zph_term(nm)
  }, character(1))
  tbl$role <- unname(roles[tbl$base_term])
  tbl$role[tbl$term == "GLOBAL"] <- "global"
  tbl$classification <- NA_character_
  for (i in seq_len(nrow(tbl))) {
    if (identical(tbl$term[[i]], "GLOBAL")) {
      tbl$classification[[i]] <- NA_character_
    } else {
      tbl$classification[[i]] <- classify_ph(
        tbl$p[[i]],
        tbl$rho[[i]],
        tbl$role[[i]]
      )
    }
  }
  keep <- intersect(
    c(
      "model", "source", "term", "base_term", "role",
      "rho", "chisq", "df", "p", "classification"
    ),
    names(tbl)
  )
  tbl[, keep]
}

save_zph_plot <- function(fit, filename, title) {
  path <- file.path(INFERENCE_PH_DIR, filename)
  z <- survival::cox.zph(fit)
  grDevices::png(path, width = 2400, height = 2200, res = 150)
  graphics::plot(z, col = "#2F4B7C", main = title)
  grDevices::dev.off()
  path
}

median_zph_across_mi <- function(imp, coded, formula, model_name, roles, mutate_fn = NULL) {
  rows <- lapply(seq_len(imp$m), function(i) {
    dat <- completed_imputation(imp, i, coded)
    if (!is.null(mutate_fn)) dat <- mutate_fn(dat)
    fit <- fit_cox_one(dat, formula)
    zph_table(fit, model_name, paste0("imputation_", i), roles)
  })
  all_tbl <- dplyr::bind_rows(rows)
  dplyr::bind_rows(lapply(split(all_tbl, all_tbl$term), function(d) {
    data.frame(
      model = model_name,
      source = "mi_median",
      term = d$term[[1]],
      base_term = d$base_term[[1]],
      role = d$role[[1]],
      rho = stats::median(d$rho, na.rm = TRUE),
      chisq = stats::median(d$chisq, na.rm = TRUE),
      df = d$df[[1]],
      p = stats::median(d$p, na.rm = TRUE),
      p_min = min(d$p, na.rm = TRUE),
      p_max = max(d$p, na.rm = TRUE),
      n_p_lt_05 = sum(d$p < 0.05, na.rm = TRUE),
      classification = if (identical(d$term[[1]], "GLOBAL")) {
        NA_character_
      } else {
        classify_ph(
          stats::median(d$p, na.rm = TRUE),
          stats::median(d$rho, na.rm = TRUE),
          d$role[[1]]
        )
      },
      stringsAsFactors = FALSE
    )
  }))
}

fit_stratified_sensitivity <- function(data, formula, strata_var) {
  rhs <- paste(deparse(formula[[3]]), collapse = " ")
  rhs <- gsub(paste0("\\b", strata_var, "\\b\\s*\\+\\s*"), "", rhs)
  rhs <- gsub(paste0("\\+\\s*\\b", strata_var, "\\b"), "", rhs)
  new_f <- stats::as.formula(
    sprintf("survival::Surv(os_days, os_event) ~ %s + strata(%s)", rhs, strata_var)
  )
  fit_cox_one(data, new_f)
}

fit_logtime_sensitivity <- function(data, formula, tv_vars) {
  rhs <- paste(deparse(formula[[3]]), collapse = " ")
  tt_terms <- paste(sprintf("tt(%s)", tv_vars), collapse = " + ")
  new_f <- stats::as.formula(
    sprintf("survival::Surv(os_days, os_event) ~ %s + %s", rhs, tt_terms)
  )
  warnings <- character()
  fit <- withCallingHandlers(
    survival::coxph(
      new_f,
      data = data,
      ties = "efron",
      tt = function(x, t, ...) {
        x * log(pmax(as.numeric(t), 1))
      },
      model = TRUE
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  attr(fit, "warnings") <- warnings
  attr(fit, "estimable") <- !any(!is.finite(coef(fit)))
  fit
}

run_ph_diagnostics <- function(imp, coded, primary_cc, secondary_cc) {
  primary_cc_z <- zph_table(primary_cc$fit, "primary_clinical", "complete_case", PH_ROLES_PRIMARY)
  secondary_cc_z <- zph_table(secondary_cc$fit, "secondary_molecular", "complete_case", PH_ROLES_SECONDARY)
  primary_mi_z <- median_zph_across_mi(imp, coded, PRIMARY_FORMULA, "primary_clinical", PH_ROLES_PRIMARY)
  secondary_mi_z <- median_zph_across_mi(imp, coded, SECONDARY_FORMULA, "secondary_molecular", PH_ROLES_SECONDARY)

  save_zph_plot(
    primary_cc$fit,
    "primary_cox_zph_complete_case.png",
    "Primary clinical model, scaled Schoenfeld residuals (complete case)"
  )
  save_zph_plot(
    secondary_cc$fit,
    "secondary_cox_zph_complete_case.png",
    "Secondary molecular model, scaled Schoenfeld residuals (complete case)"
  )

  mid <- completed_imputation(imp, 15L, coded)
  save_zph_plot(
    fit_cox_one(mid, PRIMARY_FORMULA),
    "primary_cox_zph_imputation15.png",
    "Primary clinical model, scaled Schoenfeld residuals (imputation 15)"
  )
  save_zph_plot(
    fit_cox_one(mid, SECONDARY_FORMULA),
    "secondary_cox_zph_imputation15.png",
    "Secondary molecular model, scaled Schoenfeld residuals (imputation 15)"
  )

  combined <- dplyr::bind_rows(primary_cc_z, secondary_cc_z)
  write_inference_csv(combined, "ph_diagnostics_complete_case.csv", subdir = "ph")
  write_inference_csv(
    dplyr::bind_rows(primary_mi_z, secondary_mi_z),
    "ph_diagnostics_mi_median.csv",
    subdir = "ph"
  )

  # Decision uses complete-case zph plus MI-median classification.
  # Material violation is declared only if complete-case classification is
  # MATERIAL and MI-median classification is not NO MATERIAL EVIDENCE.
  decision_rows <- lapply(seq_len(nrow(combined)), function(i) {
    row <- combined[i, ]
    if (identical(row$term, "GLOBAL")) {
      row$decision <- NA_character_
      return(row)
    }
    mi_match <- dplyr::bind_rows(primary_mi_z, secondary_mi_z)
    mi_match <- mi_match[mi_match$model == row$model & mi_match$term == row$term, ]
    mi_class <- if (nrow(mi_match)) mi_match$classification[[1]] else NA_character_
    if (identical(row$classification, "MATERIAL VIOLATION") &&
        !identical(mi_class, "NO MATERIAL EVIDENCE OF VIOLATION")) {
      row$decision <- "MATERIAL VIOLATION"
    } else if (identical(row$classification, "MINOR DEPARTURE") ||
               identical(mi_class, "MINOR DEPARTURE")) {
      row$decision <- "MINOR DEPARTURE"
    } else {
      row$decision <- row$classification
    }
    row$mi_median_classification <- mi_class
    row
  })
  decisions <- dplyr::bind_rows(decision_rows)
  write_inference_csv(decisions, "ph_diagnostics_summary.csv")

  remediation <- run_ph_remediation(imp, coded, primary_cc, decisions)
  list(
    complete_case = combined,
    mi_median = dplyr::bind_rows(primary_mi_z, secondary_mi_z),
    decisions = decisions,
    remediation = remediation
  )
}

run_ph_remediation <- function(imp, coded, primary_cc, decisions) {
  primary_dec <- decisions[decisions$model == "primary_clinical" & !is.na(decisions$decision), ]
  material <- primary_dec[primary_dec$decision == "MATERIAL VIOLATION", ]
  notes <- list()
  tables <- list()
  if (!nrow(material)) {
    notes$primary <- "No material PH violation was classified for the primary clinical model. No remediation model was fit."
    return(list(notes = notes, tables = tables, performed = FALSE))
  }
  for (i in seq_len(nrow(material))) {
    term <- material$base_term[[i]]
    role <- material$role[[i]]
    if (identical(role, "nuisance")) {
      notes[[paste0("strata_", term)]] <- sprintf(
        "Material PH departure classified for nuisance factor %s. Fitted stratified Cox sensitivity; no HR is reported for the stratified factor. Primary unstratified Cox remains primary.",
        term
      )
      cc_fit <- fit_stratified_sensitivity(primary_cc$data, PRIMARY_FORMULA, term)
      sm <- broom::tidy(cc_fit, conf.int = TRUE, exponentiate = FALSE)
      sm$model <- "primary_stratified_sensitivity"
      sm$strata_variable <- term
      tables[[paste0("strata_", term)]] <- sm
      write_inference_csv(sm, sprintf("ph_remediation_strata_%s.csv", term), subdir = "ph")
    } else if (identical(role, "important")) {
      notes[[paste0("tt_", term)]] <- sprintf(
        "Material PH departure classified for scientifically important predictor %s. Fitted prespecified log(time) interaction sensitivity. The original Cox model remains primary.",
        term
      )
      tv <- if (identical(term, "risk_group_std")) {
        "risk_group_std"
      } else {
        term
      }
      cc_fit <- fit_logtime_sensitivity(primary_cc$data, PRIMARY_FORMULA, tv)
      sm <- broom::tidy(cc_fit, conf.int = TRUE, exponentiate = FALSE)
      sm$model <- "primary_logtime_sensitivity"
      sm$time_varying_variable <- tv
      tables[[paste0("tt_", term)]] <- sm
      write_inference_csv(sm, sprintf("ph_remediation_logtime_%s.csv", term), subdir = "ph")
    }
  }
  list(notes = notes, tables = tables, performed = TRUE)
}
