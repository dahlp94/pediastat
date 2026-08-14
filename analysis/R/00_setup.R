# Stage 4 shared setup. No modeling. No outcome-stratified tables.

EXPECTED_N <- 1978L
EXPECTED_DEATHS <- 695L
EXPECTED_CENSORED <- 1283L
DAYS_PER_YEAR <- 365.25
KM_TIMES_YEARS <- c(0, 1, 3, 5, 10)
SPARSE_N <- 20L

REQUIRED_PACKAGES <- c(
  "DBI", "RPostgres", "dplyr", "tidyr", "ggplot2", "survival",
  "gtsummary", "gt", "broom", "here", "scales", "yaml", "jsonlite",
  "testthat"
)

SUPPLEMENT_CONCEPTS <- c(
  "wbc_at_diagnosis", "risk_group", "flt3_itd", "npm", "cebpa", "fab",
  "cns_disease", "marrow_blasts", "peripheral_blasts",
  "cytogenetics_t821", "cytogenetics_inv16", "cytogenetics_mll",
  "cytogenetics_monosomy7", "primary_cytogenetic_code"
)

CORE_CANDIDATES <- c(
  "age_at_diagnosis_years", "sex_at_birth", "wbc_at_diagnosis",
  "risk_group", "flt3_itd", "npm", "cebpa"
)

YES_NO_CONCEPTS <- c(
  "flt3_itd", "npm", "cebpa", "cns_disease",
  "cytogenetics_t821", "cytogenetics_inv16", "cytogenetics_mll",
  "cytogenetics_monosomy7"
)

find_project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) {
    return(here::here())
  }
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    script <- normalizePath(sub("^--file=", "", file_arg), winslash = "/", mustWork = TRUE)
    return(normalizePath(file.path(dirname(script), "..", ".."), winslash = "/", mustWork = TRUE))
  }
  getwd()
}

PROJECT_ROOT <- find_project_root()
DESCRIPTIVE_DIR <- file.path(PROJECT_ROOT, "artifacts", "descriptive")
FIGURE_DIR <- file.path(DESCRIPTIVE_DIR, "figures")
INTERIM_DIR <- file.path(PROJECT_ROOT, "data", "interim", "stage4")
SQL_VIEW_FILE <- file.path(PROJECT_ROOT, "sql", "08_create_stage4_extract_view.sql")

ensure_output_dirs <- function() {
  dir.create(DESCRIPTIVE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(INTERIM_DIR, recursive = TRUE, showWarnings = FALSE)
}

load_stage4_packages <- function() {
  missing <- REQUIRED_PACKAGES[!vapply(
    REQUIRED_PACKAGES,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )]
  if (length(missing)) {
    stop(
      "Missing R packages: ", paste(missing, collapse = ", "),
      ". Install the pediastat-r conda environment or renv restore.",
      call. = FALSE
    )
  }
  invisible(lapply(REQUIRED_PACKAGES, library, character.only = TRUE))
}

connect_pediastat <- function() {
  host <- Sys.getenv("POSTGRES_HOST", "localhost")
  port_env <- Sys.getenv("POSTGRES_PORT", "")
  dbname <- Sys.getenv("POSTGRES_DB", "pediastat")
  user <- Sys.getenv("POSTGRES_USER", "pediastat")
  password <- Sys.getenv("POSTGRES_PASSWORD", "")
  ports <- if (nzchar(port_env)) {
    as.integer(port_env)
  } else {
    c(5433L, 5432L)
  }
  last_error <- NULL
  for (port in unique(ports)) {
    tryCatch(
      {
        con <- DBI::dbConnect(
          RPostgres::Postgres(),
          host = host,
          port = port,
          dbname = dbname,
          user = user,
          password = password
        )
        return(con)
      },
      error = function(e) {
        last_error <<- e
      }
    )
  }
  stop("Could not connect to PostgreSQL: ", conditionMessage(last_error), call. = FALSE)
}

workbook_family <- function(workbook_name) {
  name <- tolower(ifelse(is.na(workbook_name), "", workbook_name))
  dplyr::case_when(
    !nzchar(name) ~ NA_character_,
    grepl("additional|sortedcells", name) ~ "additional",
    grepl("lowdepth", name) ~ "LowDepth",
    grepl("validation", name) ~ "Validation",
    grepl("discovery", name) ~ "Discovery",
    grepl("aml1031", name) ~ "AML1031",
    TRUE ~ NA_character_
  )
}

harmonize_yes_no <- function(x) {
  raw <- trimws(as.character(x))
  out <- raw
  out[toupper(raw) == "YES"] <- "Yes"
  out[toupper(raw) == "NO"] <- "No"
  out[raw == "" | is.na(raw)] <- NA_character_
  out
}

is_unknown_token <- function(x) {
  token <- tolower(trimws(as.character(x)))
  token %in% c("unknown", "unspecified", "not reported", "notreported")
}

categorical_for_table <- function(value, missingness) {
  value_chr <- ifelse(is.na(value), "", trimws(as.character(value)))
  miss <- ifelse(is.na(missingness), "", as.character(missingness))
  dplyr::case_when(
    miss == "structurally_missing" | value_chr == "" ~ "Missing",
    miss == "not_reported" ~ "Not reported",
    miss == "unknown" | is_unknown_token(value_chr) ~ "Unknown",
    TRUE ~ value_chr
  )
}

write_csv_artifact <- function(data, filename) {
  path <- file.path(DESCRIPTIVE_DIR, filename)
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

write_json_artifact <- function(data, filename) {
  path <- file.path(DESCRIPTIVE_DIR, filename)
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

quantile_named <- function(x, probs) {
  stats::quantile(x, probs = probs, names = FALSE, na.rm = TRUE, type = 7)
}

surv_quantile <- function(fit, p) {
  q <- stats::quantile(fit, probs = p)
  if (is.list(q)) {
    c(
      est = as.numeric(q$quantile)[1],
      lcl = as.numeric(q$lower)[1],
      ucl = as.numeric(q$upper)[1]
    )
  } else {
    c(est = as.numeric(q)[1], lcl = NA_real_, ucl = NA_real_)
  }
}

session_info_list <- function() {
  info <- utils::sessionInfo()
  pkgs <- vapply(info$otherPkgs, function(p) p$Version, character(1))
  attached <- vapply(info$loadedOnly, function(p) p$Version, character(1))
  list(
    r_version = paste(info$R.version$major, info$R.version$minor, sep = "."),
    platform = info$R.version$platform,
    running = info$running,
    packages = as.list(c(pkgs, attached)[REQUIRED_PACKAGES])
  )
}
