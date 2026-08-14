#!/usr/bin/env Rscript
# Fallback HTML report renderer when the Quarto CLI is unavailable.

script_dir <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)))
  }
  file.path(getwd(), "analysis", "R")
})()
source(file.path(script_dir, "00_setup.R"), local = FALSE)
load_stage4_packages()

root <- PROJECT_ROOT
desc <- DESCRIPTIVE_DIR
fig <- FIGURE_DIR
out_path <- file.path(root, "reports", "stage4_descriptive_analysis.html")

read_desc <- function(name) {
  utils::read.csv(file.path(desc, name), check.names = FALSE, stringsAsFactors = FALSE)
}

html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x
}

df_to_html <- function(df, caption = NULL) {
  header <- paste0("<th>", html_escape(names(df)), "</th>", collapse = "")
  rows <- apply(df, 1, function(row) {
    paste0("<td>", html_escape(row), "</td>", collapse = "")
  })
  body <- paste0("<tr>", rows, "</tr>", collapse = "\n")
  cap <- if (is.null(caption)) "" else paste0("<caption>", html_escape(caption), "</caption>")
  paste0("<table>", cap, "<thead><tr>", header, "</tr></thead><tbody>", body, "</tbody></table>")
}

img_tag <- function(filename, alt) {
  path <- file.path(fig, filename)
  if (!file.exists(path)) {
    return(paste0("<p><em>Missing figure: ", html_escape(filename), "</em></p>"))
  }
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  paste0(
    '<figure><img src="data:image/png;base64,',
    jsonlite::base64_enc(raw),
    '" alt="', html_escape(alt), '"><figcaption>',
    html_escape(alt), "</figcaption></figure>"
  )
}

round_df <- function(df, digits = 3) {
  num <- vapply(df, is.numeric, logical(1))
  df[num] <- lapply(df[num], function(x) round(x, digits))
  df
}

accounting <- jsonlite::fromJSON(file.path(desc, "population_accounting.json"))
endpoint <- jsonlite::fromJSON(file.path(desc, "endpoint_followup_description.json"))
followup <- jsonlite::fromJSON(file.path(desc, "followup_summary.json"))
km_summary <- jsonlite::fromJSON(file.path(desc, "overall_survival_summary.json"))
session <- jsonlite::fromJSON(file.path(desc, "r_session_info.json"))
km_est <- round_df(read_desc("overall_survival_estimates.csv"))
n_risk <- round_df(read_desc("number_at_risk.csv"))
cont <- round_df(read_desc("continuous_distribution_summary.csv"), 2)
miss <- round_df(read_desc("missingness_by_variable.csv"), 2)
prov <- read_desc("baseline_source_provenance.csv")
readiness <- read_desc("core_candidate_readiness.csv")
redundancy <- read_desc("redundancy_findings.csv")
patterns <- round_df(read_desc("missingness_patterns_top15.csv"), 2)
tbl1 <- read_desc("table1_primary_cohort.csv")
cont_show <- cont[cont$variable %in% c(
  "age_at_diagnosis_years", "wbc_at_diagnosis", "marrow_blasts", "peripheral_blasts"
), c("variable", "units", "n_observed", "n_missing", "mean", "sd", "median", "q1", "q3", "min", "max", "n_zero", "n_negative", "skewness")]
km_show <- km_est[km_est$time_years %in% c(1, 3, 5), ]

css <- paste(
  "body{font-family:Georgia,serif;max-width:980px;margin:2rem auto;padding:0 1.5rem;line-height:1.45;color:#222;}",
  "h1,h2,h3{font-family:Helvetica,Arial,sans-serif;color:#1f3b4d;}",
  "table{border-collapse:collapse;width:100%;margin:1rem 0 2rem;font-size:0.92rem;}",
  "th,td{border:1px solid #d0d7de;padding:0.4rem 0.55rem;text-align:left;vertical-align:top;}",
  "th{background:#eef3f7;}",
  "caption{text-align:left;font-weight:bold;margin-bottom:0.4rem;}",
  "figure{margin:1.5rem 0;}",
  "img{max-width:100%;height:auto;border:1px solid #d0d7de;}",
  "figcaption{font-size:0.9rem;color:#444;margin-top:0.4rem;}",
  "nav a{margin-right:0.8rem;}",
  sep = "\n"
)

html <- paste0(
  "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>",
  "<title>PediaStat — Descriptive Analysis of the Primary Pediatric AML Cohort</title>",
  "<style>", css, "</style></head><body>",
  "<h1>PediaStat — Descriptive Analysis of the Primary Pediatric AML Cohort</h1>",
  "<p><em>Stage 4: cohort characterization and overall survival summary. Rendered from locked aggregate artifacts because a complete Quarto CLI was not available.</em></p>",
  "<nav><a href='#obj'>1. Objective</a><a href='#pop'>2. Population</a><a href='#acct'>3. Construction</a>",
  "<a href='#t1'>4. Table 1</a><a href='#dist'>5. Distributions</a><a href='#miss'>6. Missing data</a>",
  "<a href='#src'>7. Provenance</a><a href='#os'>8. Overall survival</a><a href='#fu'>9. Follow-up</a>",
  "<a href='#ready'>10. Readiness</a><a href='#lim'>11. Limitations</a><a href='#next'>12. Next decisions</a></nav>",
  "<h2 id='obj'>1. Scientific Objective</h2>",
  "<p>This report describes the prespecified primary pediatric AML cohort in public TARGET-AML data and estimates the <strong>overall</strong> survival distribution. It does not compare survival across baseline subgroups, does not fit Cox models, and does not use p-values to screen covariates.</p>",
  "<h2 id='pop'>2. Prespecified Study Population</h2>",
  "<p>The unit of analysis is the analysis person. Primary eligibility is age at diagnosis &lt; 18 years, Alive or Dead vital status, and a valid status-specific OS time. Unknown / Not Reported vital status are excluded, never censored. Candidate covariates are not inclusion criteria.</p>",
  "<h2 id='acct'>3. Cohort Construction Summary</h2>",
  "<p>", html_escape(accounting$interpretation), "</p>",
  df_to_html(
    data.frame(
      Quantity = c(
        "Original GDC cases",
        "GDC cases mapping to valid person identity",
        "Unique valid analysis persons",
        "GDC cases ineligible (experimental / non-patient / ambiguous)",
        "Rows in analytics.cohort_eligibility",
        "Valid persons in eligibility table",
        "Ineligible identity records retained for audit",
        "Primary OS cohort"
      ),
      N = c(
        accounting$original_gdc_cases,
        accounting$gdc_cases_valid_identity,
        accounting$unique_valid_analysis_persons,
        accounting$gdc_cases_ineligible_identity,
        accounting$cohort_eligibility_rows,
        accounting$cohort_eligibility_valid_persons,
        accounting$cohort_eligibility_ineligible_identity_records,
        accounting$primary_os_cohort_n
      )
    ),
    "Identity and eligibility accounting"
  ),
  "<p>Primary OS event: GDC demographic.vital_status (Dead = 1, Alive = 0). Time: days_to_death if Dead; diagnoses.days_to_last_follow_up if Alive. Origin: initial pathologic diagnosis.</p>",
  "<h2 id='t1'>4. Primary Cohort Characteristics</h2>",
  "<p>Table 1 is an overall description of the locked cohort. It is not stratified by death status and contains no p-values. Unknown is retained as a reported category. Percentages use N = ",
  endpoint$primary_cohort_n, ".</p>",
  df_to_html(tbl1, "Table 1. Baseline characteristics of the primary pediatric AML cohort"),
  "<h2 id='dist'>5. Baseline Variable Distributions</h2>",
  df_to_html(cont_show, "Continuous baseline distributions"),
  img_tag("age_at_diagnosis_histogram.png", "Age at diagnosis"),
  img_tag("wbc_histogram.png", "WBC at diagnosis, raw scale"),
  img_tag("wbc_histogram_log10.png", "WBC at diagnosis, log10 scale"),
  "<p>All observed WBC values are greater than 0, so a log10 axis is defined. This does not lock a future model transformation.</p>",
  img_tag("marrow_blasts_histogram.png", "Bone marrow leukemic blast percentage"),
  img_tag("peripheral_blasts_histogram.png", "Peripheral blast percentage"),
  "<h2 id='miss'>6. Missing Data</h2>",
  "<p>These summaries do not establish MCAR, MAR, or MNAR and were not tested against survival. No imputation was performed.</p>",
  df_to_html(miss[, c("concept", "observed_n", "missing_n", "missing_percent", "unknown_n", "not_reported_n", "structurally_missing_n", "conflict_n")], "Missingness by baseline concept"),
  df_to_html(patterns, "Most common missingness patterns"),
  img_tag("missingness_heatmap.png", "Missingness heatmap (identifiers omitted)"),
  "<h2 id='src'>7. Data Source / Provenance Summary</h2>",
  df_to_html(prov, "Source contributing the selected baseline value"),
  "<h2 id='os'>8. Overall Survival</h2>",
  "<p>Kaplan–Meier estimates for the entire primary cohort. Not stratified. No log-rank test and no Cox model.</p>",
  df_to_html(km_show, "Kaplan-Meier overall survival at 1, 3, and 5 years"),
  "<p><strong>Median OS:</strong> ", html_escape(km_summary$median_os$statement), "</p>",
  img_tag("overall_kaplan_meier.png", "Overall Kaplan-Meier curve with 95% CI and number at risk"),
  df_to_html(n_risk, "Number at risk"),
  "<p>At 10 years only 16 persons remain at risk; that estimate is unstable and is shown only to document the limit of follow-up.</p>",
  "<h2 id='fu'>9. Follow-Up Duration</h2>",
  "<p>", html_escape(followup$statement), "</p>",
  "<p>", html_escape(followup$interpretation), "</p>",
  "<p>The median of observed OS times (", followup$observed_os_days_median,
  " days) is a range descriptor only. It must not be labeled median follow-up or Kaplan–Meier median survival.</p>",
  "<p>Observed OS range: ", endpoint$observed_os_days_min, "–", endpoint$observed_os_days_max,
  " days. Crude event percentage (", endpoint$crude_event_percent,
  "%) is deaths/N, not a cumulative mortality risk.</p>",
  "<h2 id='ready'>10. Analysis-Readiness Assessment</h2>",
  "<p>CORE CANDIDATE review uses definition, coding, missingness, sparsity, and source quality. Survival association was not used.</p>",
  df_to_html(readiness, "CORE CANDIDATE analysis-readiness"),
  df_to_html(redundancy, "Potential redundancy to review before model specification"),
  "<h2 id='lim'>11. Limitations</h2>",
  "<ul>",
  "<li>Public TARGET-AML data are observational and incomplete relative to controlled-access files.</li>",
  "<li>Baseline AML characteristics come from overlapping supplements; residual source conflict is flagged, not overwritten.</li>",
  "<li>FAB is largely missing. Several molecular and cytogenetic fields have non-negligible Unknown or structural missingness.</li>",
  "<li>Seven primary-cohort persons have an index_date QA flag and were retained under the locked Stage 3 rule.</li>",
  "<li>No causal interpretation and no multivariable inference yet.</li>",
  "</ul>",
  "<h2 id='next'>12. Next Statistical Decisions</h2>",
  "<p>Stage 5 must freeze the inferential plan before regression, including primary covariates, functional forms for age and WBC, Unknown vs missing handling, the missing-data method, redundancy of risk group with FLT3/lesion flags, unexpected risk-group tokens, whether primary cytogenetic code is used, interactions, multiplicity, and PH remediation.</p>",
  "<p>R ", html_escape(session$r_version), " (", html_escape(session$running), "). Source narrative: <code>reports/stage4_descriptive_analysis.qmd</code>.</p>",
  "</body></html>"
)

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
writeLines(html, out_path)
message("Wrote ", out_path)
