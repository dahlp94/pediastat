# Stage 6: load frozen cohort, apply Stage 5 coding, preflight.
# Does not rebuild eligibility. Does not fit Cox models.

init_stage6_paths <- function() {
  INFERENCE_DIR <<- file.path(PROJECT_ROOT, "artifacts", "inference")
  INFERENCE_MI_DIR <<- file.path(INFERENCE_DIR, "mi")
  INFERENCE_PH_DIR <<- file.path(INFERENCE_DIR, "ph")
  INFERENCE_FIG_DIR <<- file.path(INFERENCE_DIR, "figures")
  INTERIM_STAGE6 <<- file.path(PROJECT_ROOT, "data", "interim", "stage6")
  dir.create(INFERENCE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_MI_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_PH_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INFERENCE_FIG_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INTERIM_STAGE6, recursive = TRUE, showWarnings = FALSE)
  invisible(INFERENCE_DIR)
}

load_stage6_packages <- function() {
  load_stage4_packages()
  extra <- c("mice")
  missing <- extra[!vapply(extra, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop(
      "Missing Stage 6 R packages: ", paste(missing, collapse = ", "),
      ". Install r-mice in the pediastat-r conda environment.",
      call. = FALSE
    )
  }
  if (!requireNamespace("nnet", quietly = TRUE)) {
    stop("Package nnet is required for mice polyreg.", call. = FALSE)
  }
  invisible(lapply(extra, library, character.only = TRUE))
}

write_inference_csv <- function(data, filename, subdir = NULL) {
  base <- if (is.null(subdir)) INFERENCE_DIR else file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

write_inference_json <- function(data, filename, subdir = NULL) {
  base <- if (is.null(subdir)) INFERENCE_DIR else file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
  jsonlite::write_json(
    data,
    path,
    pretty = TRUE,
    auto_unbox = TRUE,
    na = "null",
    digits = NA
  )
  path
}

save_inference_plot <- function(plot, filename, subdir = "figures",
                                width = 2400, height = 1600, res = 220) {
  base <- file.path(INFERENCE_DIR, subdir)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(base, filename)
  ggplot2::ggsave(
    path,
    plot,
    width = width / res,
    height = height / res,
    dpi = res,
    units = "in"
  )
  path
}

FORBIDDEN_POST_BASELINE <- c(
  "sct_in_first_cr", "mrd_end_course_1", "gemtuzumab",
  "treatment_response", "first_event", "days_to_first_event"
)

standardize_race_aux <- function(x) {
  # Auxiliary-only collapse. Race is not a principal-model predictor.
  # Sparse OMB cells are grouped as Other so polyreg is estimable.
  raw <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(raw))
  out[raw == "white"] <- "White"
  out[raw == "black or african american"] <- "Black or African American"
  out[raw == "asian"] <- "Asian"
  out[raw %in% c(
    "american indian or alaska native",
    "native hawaiian or other pacific islander",
    "other"
  )] <- "Other"
  out[raw %in% c("unknown", "not reported", "notreported", "", "na")] <- NA_character_
  out[is.na(raw) | !nzchar(raw)] <- NA_character_
  leftover <- !is.na(raw) & nzchar(raw) & is.na(out) &
    !(raw %in% c("unknown", "not reported", "notreported", "na"))
  out[leftover] <- "Other"
  factor(
    out,
    levels = c("White", "Black or African American", "Asian", "Other")
  )
}

standardize_ethnicity_aux <- function(x) {
  raw <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(raw))
  out[grepl("not hispanic", raw)] <- "Not Hispanic or Latino"
  hispanic <- grepl("hispanic", raw) & !grepl("not hispanic", raw)
  out[hispanic] <- "Hispanic or Latino"
  out[raw %in% c("unknown", "not reported", "notreported", "", "na")] <- NA_character_
  factor(out, levels = c("Not Hispanic or Latino", "Hispanic or Latino"))
}

assert_no_post_baseline <- function(names_in_use) {
  hit <- intersect(FORBIDDEN_POST_BASELINE, names_in_use)
  if (length(hit)) {
    stop(
      "Post-baseline variables entered the inferential dataset: ",
      paste(hit, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

stage6_preflight_invariants <- function(coded, spec) {
  checks <- validate_frozen_cohort(coded)
  preflight <- preflight_coded_cohort(coded, spec)
  if (anyNA(coded$os_event)) {
    stop("Missing os_event in coded inferential cohort.", call. = FALSE)
  }
  if (anyNA(coded$os_days) || any(coded$os_days < 0, na.rm = TRUE)) {
    stop("Missing or negative os_days in coded inferential cohort.", call. = FALSE)
  }
  if (any(coded$os_days == 0, na.rm = TRUE)) {
    stop("Zero os_days found; Stage 3 frozen cohort had none.", call. = FALSE)
  }
  needed <- unique(c(primary_terms(), secondary_terms(), "os_days", "os_event", "age5"))
  missing_vars <- setdiff(needed, names(coded))
  if (length(missing_vars)) {
    stop("Missing expected model variables: ", paste(missing_vars, collapse = ", "), call. = FALSE)
  }
  if (!identical(levels(coded$sex_std), c("Female", "Male"))) {
    stop("Sex reference/levels are not Female, Male.", call. = FALSE)
  }
  if (!identical(levels(coded$risk_group_std), c("Low", "Standard", "High"))) {
    stop("Risk-group reference/levels are not Low, Standard, High.", call. = FALSE)
  }
  for (nm in c(
    "flt3_itd_std", "npm_std", "cebpa_std",
    "cytogenetics_t821_std", "cytogenetics_inv16_std",
    "cytogenetics_mll_std", "cytogenetics_monosomy7_std"
  )) {
    if (!identical(levels(coded[[nm]]), c("No", "Yes"))) {
      stop(nm, " reference/levels are not No, Yes.", call. = FALSE)
    }
  }
  assert_no_post_baseline(names(coded))
  if (grepl("risk_group", spec$secondary_model$formula, fixed = TRUE)) {
    stop("Secondary formula unexpectedly contains risk_group.", call. = FALSE)
  }
  if (length(spec$primary_model$interactions) || length(spec$secondary_model$interactions)) {
    stop("Principal models must have no interactions.", call. = FALSE)
  }
  preflight$cohort_checks <- checks
  preflight$n_unresolved_risk_tokens_recorded <- sum(
    coded$risk_group_mapping_action == "unresolved_set_missing",
    na.rm = TRUE
  )
  preflight
}

prepare_inferential_cohort <- function(loaded, spec = NULL) {
  spec <- spec %||% load_model_spec_yaml()
  coded <- code_inferential_cohort(loaded$cohort, spec)
  coded$nelson_aalen <- nelson_aalen_cumulative_hazard(coded$os_days, coded$os_event)
  if (any(!is.finite(coded$nelson_aalen))) {
    stop("Nelson-Aalen auxiliary has non-finite values.", call. = FALSE)
  }
  coded$race_aux <- standardize_race_aux(coded$race)
  coded$ethnicity_aux <- standardize_ethnicity_aux(coded$ethnicity)
  if (!("source_family_aml1031" %in% names(coded))) {
    coded$source_family_aml1031 <- 0L
  }
  coded$source_family_aml1031[is.na(coded$source_family_aml1031)] <- 0L
  preflight <- stage6_preflight_invariants(coded, spec)
  list(coded = coded, spec = spec, preflight = preflight, loaded = loaded)
}
