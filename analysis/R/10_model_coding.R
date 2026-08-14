# Stage 5 analysis-variable coding. Does not fit Cox models or run MI.

load_model_spec_yaml <- function() {
  spec_path <- file.path(PROJECT_ROOT, "config", "model_spec.yaml")
  yaml::read_yaml(spec_path)
}

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
  mapping <- spec$coding$sex$map
  missing_tokens <- spec$coding$sex$missing_tokens
  raw <- trimws(as.character(x))
  out <- rep(NA_character_, length(raw))
  for (i in seq_along(raw)) {
    token <- raw[[i]]
    if (is.na(token) || !nzchar(token) || token %in% missing_tokens) {
      next
    }
    mapped <- mapping[[token]]
    if (is.null(mapped)) {
      hit <- names(mapping)[tolower(names(mapping)) == tolower(token)]
      if (length(hit)) mapped <- mapping[[hit[[1]]]]
    }
    if (!is.null(mapped)) out[[i]] <- mapped
  }
  factor(out, levels = c(spec$coding$sex$reference, "Male"))
}

standardize_yes_no <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  yes_tokens <- spec$coding$yes_no$yes_tokens
  no_tokens <- spec$coding$yes_no$no_tokens
  missing_tokens <- spec$coding$yes_no$missing_tokens
  raw <- trimws(as.character(x))
  out <- rep(NA_character_, length(raw))
  out[raw %in% yes_tokens | toupper(raw) == "YES"] <- "Yes"
  out[raw %in% no_tokens | toupper(raw) == "NO"] <- "No"
  out[raw %in% missing_tokens | raw %in% c("", "NA")] <- NA_character_
  out[is.na(raw)] <- NA_character_
  factor(out, levels = c(spec$coding$yes_no$reference, "Yes"))
}

standardize_risk_group <- function(x, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  mapping <- spec$coding$risk_group$map
  unresolved <- spec$coding$risk_group$unresolved_tokens
  missing_tokens <- spec$coding$risk_group$missing_tokens
  raw <- trimws(as.character(x))
  std <- rep(NA_character_, length(raw))
  qa <- rep(NA_character_, length(raw))
  action <- rep("missing", length(raw))
  for (i in seq_along(raw)) {
    token <- raw[[i]]
    if (is.na(token) || !nzchar(token) || token %in% c("NA")) {
      action[[i]] <- "missing"
      next
    }
    if (token %in% unresolved) {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unresolved_set_missing"
      next
    }
    if (token %in% missing_tokens) {
      action[[i]] <- "source_missing"
      next
    }
    mapped <- mapping[[token]]
    if (!is.null(mapped)) {
      std[[i]] <- mapped
      action[[i]] <- "mapped"
    } else {
      qa[[i]] <- "unresolved_risk_group_token"
      action[[i]] <- "unrecognized_set_missing"
    }
  }
  list(
    original = ifelse(is.na(raw) | raw == "", NA_character_, raw),
    standardized = factor(std, levels = c(spec$coding$risk_group$reference, "Standard", "High")),
    qa_flag = qa,
    mapping_action = action
  )
}

nelson_aalen_cumulative_hazard <- function(time, event) {
  # Nonparametric Fleming-Harrington / Nelson-Aalen estimator.
  # This is not a Cox model and is not used for predictor screening.
  fit <- survival::survfit(
    survival::Surv(time, event) ~ 1,
    type = "fleming-harrington"
  )
  times <- fit$time
  haz <- fit$cumhaz
  idx <- findInterval(time, times)
  out <- rep(NA_real_, length(time))
  positive <- idx > 0
  out[positive] <- haz[idx[positive]]
  out[idx == 0] <- 0
  out
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

code_inferential_cohort <- function(cohort, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  out <- cohort
  out$age5 <- age5(out$age_at_diagnosis_years, spec$coding$age5_divisor)
  wbc_num <- suppressWarnings(as.numeric(out$wbc_at_diagnosis))
  if ("wbc_at_diagnosis_missingness" %in% names(out)) {
    wbc_num[out$wbc_at_diagnosis_missingness != "observed"] <- NA_real_
  }
  out$wbc_at_diagnosis_num <- wbc_num
  out$log2_wbc <- log2_wbc(wbc_num)
  out$sex_std <- standardize_sex(out$sex_at_birth, spec)
  rg <- standardize_risk_group(out$risk_group, spec)
  out$risk_group_original <- rg$original
  out$risk_group_std <- rg$standardized
  out$risk_group_qa_flag <- rg$qa_flag
  out$risk_group_mapping_action <- rg$mapping_action
  yn_vars <- c(
    "flt3_itd", "npm", "cebpa",
    "cytogenetics_t821", "cytogenetics_inv16",
    "cytogenetics_mll", "cytogenetics_monosomy7",
    "cns_disease"
  )
  for (nm in yn_vars) {
    if (nm %in% names(out)) {
      out[[paste0(nm, "_std")]] <- standardize_yes_no(out[[nm]], spec)
    }
  }
  if ("wbc_at_diagnosis_source_workbook" %in% names(out)) {
    out$source_family_aml1031 <- as.integer(
      grepl("AML1031", out$wbc_at_diagnosis_source_workbook, ignore.case = TRUE) &
        !grepl("additional|sorted", out$wbc_at_diagnosis_source_workbook, ignore.case = TRUE)
    )
  }
  out
}
