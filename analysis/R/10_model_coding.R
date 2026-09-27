# Stage 5 analysis-variable coding. Does not fit Cox models or run MI.

load_model_spec_yaml <- function() {
  yaml::read_yaml(file.path(PROJECT_ROOT, "config", "model_spec.yaml"))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

age5 <- function(age_years, divisor = 5) {
  out <- as.numeric(age_years) / divisor
  out[!is.finite(out)] <- NA_real_
  out
}

log2_wbc <- function(wbc) {
  x <- as.numeric(wbc)
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x) & x > 0
  out[ok] <- log2(x[ok])
  out
}

standardize_sex <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  mapping <- unlist(spec$coding$sex$map, use.names = TRUE)
  index <- match(tolower(raw), tolower(names(mapping)))
  out <- rep(NA_character_, length(raw))
  hit <- !is.na(index)
  out[hit] <- unname(mapping[index[hit]])
  missing <- is.na(raw) | !nzchar(raw) | raw %in% spec$coding$sex$missing_tokens
  out[missing] <- NA_character_
  factor(out, levels = c(spec$coding$sex$reference, "Male"))
}

standardize_yes_no <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  out <- rep(NA_character_, length(raw))
  out[raw %in% spec$coding$yes_no$yes_tokens | toupper(raw) == "YES"] <- "Yes"
  out[raw %in% spec$coding$yes_no$no_tokens | toupper(raw) == "NO"] <- "No"
  missing <- is.na(raw) | raw %in% spec$coding$yes_no$missing_tokens | raw %in% c("", "NA")
  out[missing] <- NA_character_
  factor(out, levels = c(spec$coding$yes_no$reference, "Yes"))
}

standardize_risk_group <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  raw <- trimws(as.character(x))
  std <- qa <- rep(NA_character_, length(raw))
  action <- rep("missing", length(raw))
  for (i in seq_along(raw)) {
    token <- raw[[i]]
    if (is.na(token) || !nzchar(token) || token == "NA") next
    if (token %in% spec$coding$risk_group$unresolved_tokens) {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unresolved_set_missing"
      next
    }
    if (token %in% spec$coding$risk_group$missing_tokens) {
      action[[i]] <- "source_missing"
      next
    }
    mapped <- spec$coding$risk_group$map[[token]]
    if (is.null(mapped)) {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unrecognized_set_missing"
    } else {
      std[[i]] <- mapped
      action[[i]] <- "mapped"
    }
  }
  list(
    original = ifelse(is.na(raw) | raw == "", NA_character_, raw),
    standardized = factor(
      std, levels = c(spec$coding$risk_group$reference, "Standard", "High")
    ),
    qa_flag = qa,
    mapping_action = action
  )
}

nelson_aalen_cumulative_hazard <- function(time, event) {
  # Retained for Stage 6 compatibility; this is an MI auxiliary, not a model fit.
  fit <- survival::survfit(
    survival::Surv(time, event) ~ 1, type = "fleming-harrington"
  )
  idx <- findInterval(time, fit$time)
  out <- rep(0, length(time))
  out[idx > 0] <- fit$cumhaz[idx[idx > 0]]
  out
}

code_inferential_cohort <- function(cohort, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  out <- cohort
  out$age5 <- age5(out$age_at_diagnosis_years, spec$coding$age5_divisor)

  wbc <- suppressWarnings(as.numeric(out$wbc_at_diagnosis))
  if ("wbc_at_diagnosis_missingness" %in% names(out)) {
    wbc[out$wbc_at_diagnosis_missingness != "observed"] <- NA_real_
  }
  out$wbc_at_diagnosis_num <- wbc
  out$log2_wbc <- log2_wbc(wbc)
  out$sex_std <- standardize_sex(out$sex_at_birth, spec)

  risk <- standardize_risk_group(out$risk_group, spec)
  out$risk_group_original <- risk$original
  out$risk_group_std <- risk$standardized
  out$risk_group_qa_flag <- risk$qa_flag
  out$risk_group_mapping_action <- risk$mapping_action

  yes_no <- c(
    "flt3_itd", "npm", "cebpa", "cytogenetics_t821", "cytogenetics_inv16",
    "cytogenetics_mll", "cytogenetics_monosomy7", "cns_disease"
  )
  for (nm in intersect(yes_no, names(out))) {
    out[[paste0(nm, "_std")]] <- standardize_yes_no(out[[nm]], spec)
  }

  if ("wbc_at_diagnosis_source_workbook" %in% names(out)) {
    workbook <- out$wbc_at_diagnosis_source_workbook
    out$source_family_aml1031 <- as.integer(
      grepl("AML1031", workbook, ignore.case = TRUE) &
        !grepl("additional|sorted", workbook, ignore.case = TRUE)
    )
  }
  out
}
