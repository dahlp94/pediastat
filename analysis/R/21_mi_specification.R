# Stage 6 MICE specification. Methods, predictor matrix, and auxiliaries
# follow config/model_spec.yaml. No Cox fitting here.

MI_ANALYSIS_VARS <- c(
  "log2_wbc", "risk_group_std",
  "flt3_itd_std", "npm_std", "cebpa_std",
  "cytogenetics_t821_std", "cytogenetics_inv16_std",
  "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
)

MI_COMPLETE_PREDICTORS <- c(
  "age5", "sex_std", "os_event", "nelson_aalen", "source_family_aml1031"
)

MI_AUX_IMPUTED <- c(
  "marrow_blasts_num", "peripheral_blasts_num",
  "cns_disease_std", "race_aux", "ethnicity_aux"
)

MI_CARRIED <- c("os_days")

mi_column_order <- function() {
  c(MI_CARRIED, MI_COMPLETE_PREDICTORS, MI_ANALYSIS_VARS, MI_AUX_IMPUTED)
}

build_mice_frame <- function(coded) {
  cols <- mi_column_order()
  missing_cols <- setdiff(cols, names(coded))
  if (length(missing_cols)) {
    stop("MICE frame missing columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  forbidden_present <- intersect(FORBIDDEN_POST_BASELINE, names(coded))
  if (length(forbidden_present)) {
    # Presence on the cohort extract is allowed; they must not enter the MICE frame.
    extra <- intersect(forbidden_present, cols)
    if (length(extra)) {
      stop("Forbidden post-baseline columns in MICE frame: ", paste(extra, collapse = ", "), call. = FALSE)
    }
  }
  dat <- coded[, cols, drop = FALSE]
  dat$os_event <- as.integer(dat$os_event)
  dat$source_family_aml1031 <- as.integer(dat$source_family_aml1031)
  dat
}

build_mice_methods <- function(dat, spec) {
  meth <- mice::make.method(dat)
  meth[] <- ""
  planned <- spec$missing_data$methods
  meth[["log2_wbc"]] <- planned$log2_wbc
  meth[["risk_group_std"]] <- planned$risk_group_std
  for (nm in c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )) {
    meth[[nm]] <- planned[[nm]]
  }
  meth[["marrow_blasts_num"]] <- "pmm"
  meth[["peripheral_blasts_num"]] <- "pmm"
  meth[["cns_disease_std"]] <- "logreg"
  meth[["race_aux"]] <- "polyreg"
  meth[["ethnicity_aux"]] <- "logreg"
  do_not <- unlist(spec$missing_data$do_not_impute, use.names = FALSE)
  overlap <- intersect(names(meth), do_not)
  if (length(overlap)) {
    meth[overlap] <- ""
  }
  meth[["os_days"]] <- ""
  meth[["os_event"]] <- ""
  meth[["age5"]] <- ""
  meth[["sex_std"]] <- ""
  meth[["nelson_aalen"]] <- ""
  meth[["source_family_aml1031"]] <- ""
  meth
}

build_mice_predictor_matrix <- function(dat, meth) {
  pred <- mice::make.predictorMatrix(dat)
  # os_days is carried for Cox fits after imputation; it is not a predictor
  # because Nelson-Aalen already encodes nonparametric cumulative hazard.
  if ("os_days" %in% colnames(pred)) {
    pred[, "os_days"] <- 0
    pred["os_days", ] <- 0
  }
  for (nm in names(meth)) {
    if (identical(meth[[nm]], "")) {
      pred[nm, ] <- 0
    }
  }
  pred
}

assert_mice_spec <- function(meth, spec) {
  if (any(meth[c("os_event", "os_days", "age5", "sex_std")] != "")) {
    stop("Outcome, time, age, or sex was marked for imputation.", call. = FALSE)
  }
  if (!identical(unname(meth[["log2_wbc"]]), "pmm")) {
    stop("log2_wbc must use pmm.", call. = FALSE)
  }
  if (!identical(unname(meth[["risk_group_std"]]), "polyreg")) {
    stop("risk_group_std must use polyreg.", call. = FALSE)
  }
  if ("analysis_person_id" %in% names(meth)) {
    stop("analysis_person_id must not enter the MICE specification.", call. = FALSE)
  }
  invisible(TRUE)
}

mice_missingness_summary <- function(dat) {
  n <- nrow(dat)
  rows <- lapply(names(dat), function(nm) {
    n_miss <- sum(is.na(dat[[nm]]))
    data.frame(
      variable = nm,
      n = n,
      n_missing = n_miss,
      percent_missing = round(100 * n_miss / n, 2),
      class = paste(class(dat[[nm]]), collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}
