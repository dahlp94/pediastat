#!/usr/bin/env Rscript
# Fallback HTML renderer when the Quarto CLI is unavailable.

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
inf <- file.path(root, "artifacts", "inference")
fig <- file.path(inf, "figures")
ph <- file.path(inf, "ph")
mi <- file.path(inf, "mi")
out_path <- file.path(root, "reports", "stage6_inferential_analysis.html")

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

img_tag <- function(path, alt) {
  if (!file.exists(path)) {
    return(paste0("<p><em>Missing figure: ", html_escape(basename(path)), "</em></p>"))
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

read_inf <- function(name) {
  utils::read.csv(file.path(inf, name), check.names = FALSE, stringsAsFactors = FALSE)
}

fmt_hr <- function(row) {
  sprintf(
    "HR %.2f (95%% CI %.2f–%.2f); p = %.3g",
    row$hr, row$hr_lcl, row$hr_ucl, row$p_value
  )
}

interpret_row <- function(row, adjustment) {
  direction <- if (row$hr >= 1) "higher" else "lower"
  precision <- if (row$hr_lcl < 1 && row$hr_ucl > 1) {
    sprintf(
      "The interval was compatible with both higher and lower hazard, so the estimate was imprecise."
    )
  } else {
    sprintf("The interval was compatible with a %s hazard of death.", direction)
  }
  sprintf(
    "After adjustment for %s, %s was associated with a %s hazard of death (adjusted HR %.2f, 95%% CI %.2f–%.2f; nominal p = %.3g). %s This is a prognostic association, not a causal effect.",
    adjustment,
    row$predictor_label,
    direction,
    row$hr, row$hr_lcl, row$hr_ucl, row$p_value,
    precision
  )
}

primary <- round_df(read_inf("primary_cox_mi.csv"), 4)
secondary <- round_df(read_inf("secondary_cox_mi.csv"), 4)
primary_cc <- round_df(read_inf("primary_cox_complete_case.csv"), 4)
secondary_cc <- round_df(read_inf("secondary_cox_complete_case.csv"), 4)
cmp <- round_df(read_inf("mi_vs_complete_case.csv"), 4)
nl <- round_df(read_inf("nonlinear_sensitivity_summary.csv"), 4)
phs <- round_df(read_inf("ph_diagnostics_summary.csv"), 4)
fit <- read_inf("model_fit_summary.csv")
meta <- jsonlite::fromJSON(file.path(inf, "model_metadata.json"))
session <- jsonlite::fromJSON(file.path(inf, "r_session_info.json"))
deviations <- paste(
  readLines(file.path(root, "docs", "stage6_sap_deviations.md"), warn = FALSE),
  collapse = "\n"
)

show_cols <- c(
  "predictor_label", "comparison_or_unit", "hr", "hr_lcl", "hr_ucl",
  "p_value", "beta", "se", "fmi"
)
sec_cols <- c(show_cols, "q_value")
show_cols <- intersect(show_cols, names(primary))
sec_cols <- intersect(sec_cols, names(secondary))

css <- paste(
  "body{font-family:Georgia,serif;max-width:980px;margin:2rem auto;padding:0 1rem;line-height:1.5;color:#222}",
  "h1,h2,h3{font-family:Helvetica,Arial,sans-serif}",
  "table{border-collapse:collapse;width:100%;margin:1rem 0;font-size:0.92rem}",
  "th,td{border:1px solid #ccc;padding:0.4rem 0.5rem;text-align:left}",
  "th{background:#f4f6f8}",
  "figure{margin:1.5rem 0} img{max-width:100%;height:auto}",
  "pre{white-space:pre-wrap;background:#f7f7f7;padding:1rem}"
)

html <- c(
  "<!DOCTYPE html><html><head><meta charset='utf-8'>",
  "<title>PediaStat — Inferential Survival Analysis</title>",
  paste0("<style>", css, "</style></head><body>"),
  "<h1>PediaStat — Inferential Survival Analysis</h1>",
  "<p>Stage 6 execution of the frozen Stage 5 Cox + multiple-imputation plan. Language is prognostic association, not causal effect.</p>",
  "<h2>Executive summary</h2>",
  "<ul>",
  sprintf("<li>Population: frozen primary TARGET-AML OS cohort, N = %s analysis persons &lt;18 years at diagnosis (%s deaths, %s censored).</li>", meta$cohort_n, meta$deaths, meta$censored),
  "<li>Primary prognostic variables: protocol risk group and log2 WBC, adjusted for age and sex.</li>",
  sprintf("<li>Primary High vs Low risk: %s.</li>", fmt_hr(primary[primary$term == "risk_group_stdHigh", ][1, ])),
  sprintf("<li>Primary WBC per doubling: %s.</li>", fmt_hr(primary[primary$term == "log2_wbc", ][1, ])),
  "<li>Complete-case sensitivity used the same formulas; see the comparison table for direction and magnitude.</li>",
  "<li>PH diagnostics used scaled Schoenfeld residuals; remediation followed the frozen hierarchy without replacing the primary model.</li>",
  "<li>Limitations include observational TARGET data, MAR-based MI, possible residual confounding, and a small 10-year risk set.</li>",
  "</ul>",
  "<h2>1. Scientific objective</h2>",
  "<p>Among children and adolescents with AML, estimate adjusted associations between prespecified baseline characteristics and the hazard of all-cause death after diagnosis.</p>",
  "<h2>2. Prespecified primary cohort</h2>",
  sprintf("<p>N = %s; deaths = %s; censored = %s. Age at diagnosis &lt;18 years. Eligibility was not reconstructed in R.</p>", meta$cohort_n, meta$deaths, meta$censored),
  "<h2>3. Prespecified statistical models</h2>",
  sprintf("<p>Primary: <code>%s</code></p>", html_escape(meta$primary_formula)),
  sprintf("<p>Secondary: <code>%s</code></p>", html_escape(meta$secondary_formula)),
  "<p>Ties: Efron. No interactions. Risk group is absent from the secondary model.</p>",
  "<h2>4. Missing data</h2>",
  sprintf("<p>Primary analysis used mice with m = %s, seed = %s, maxit = %s. Survival time and event were not imputed. Nelson–Aalen cumulative hazard and event status were auxiliary predictors.</p>", meta$m, meta$seed, meta$mice_maxit),
  img_tag(file.path(mi, "mi_trace_plots.png"), "MICE chain-mean trace plots"),
  "<h2>5. Primary clinical model</h2>",
  df_to_html(primary[, show_cols], "Pooled primary Cox model (Rubin rules on coefficients)"),
  img_tag(file.path(fig, "forest_primary_clinical.png"), "Primary clinical model forest plot"),
  paste0("<p>", html_escape(interpret_row(primary[primary$term == "risk_group_stdHigh", ][1, ], "age, sex, WBC, and risk group")), "</p>"),
  paste0("<p>", html_escape(interpret_row(primary[primary$term == "log2_wbc", ][1, ], "age, sex, WBC, and risk group")), "</p>"),
  "<h2>6. Secondary molecular/cytogenetic model</h2>",
  df_to_html(secondary[, sec_cols], "Pooled secondary Cox model with BH q-values for the frozen biological family"),
  img_tag(file.path(fig, "forest_secondary_molecular.png"), "Secondary molecular model forest plot"),
  "<h2>7. Complete-case sensitivity</h2>",
  df_to_html(cmp, "MI vs complete-case adjusted HRs"),
  "<h2>8. Functional-form sensitivity</h2>",
  df_to_html(nl, "Restricted cubic spline tests; knots frozen from Stage 4"),
  img_tag(file.path(fig, "age_spline_relative_hazard.png"), "Age spline relative hazard"),
  img_tag(file.path(fig, "wbc_spline_relative_hazard.png"), "WBC spline relative hazard"),
  "<h2>9. Proportional-hazards diagnostics</h2>",
  df_to_html(phs, "cox.zph complete-case diagnostics and classifications"),
  img_tag(file.path(ph, "primary_cox_zph_complete_case.png"), "Primary model Schoenfeld plots"),
  img_tag(file.path(ph, "secondary_cox_zph_complete_case.png"), "Secondary model Schoenfeld plots"),
  "<h2>10. Influence diagnostics</h2>",
  "<p>Deviance residuals and dfbeta were summarized without identifiers. Valid influential observations were retained.</p>",
  img_tag(file.path(fig, "primary_deviance_residuals.png"), "Primary model deviance residuals"),
  "<h2>11. Descriptive Kaplan–Meier figures</h2>",
  img_tag(file.path(fig, "km_risk_group.png"), "Unadjusted KM by risk group"),
  img_tag(file.path(fig, "km_flt3_itd.png"), "Unadjusted KM by FLT3/ITD"),
  "<p>These figures are descriptive and were not used for variable selection. No log-rank tests were computed.</p>",
  "<h2>12–15. Interpretation, limitations, deviations, conclusions</h2>",
  "<p>See the Quarto source for the full narrative. Concordance is descriptive model information, not a prediction-model validation.</p>",
  "<h2>SAP deviations</h2>",
  paste0("<pre>", html_escape(deviations), "</pre>"),
  "<h2>Software</h2>",
  sprintf("<p>R %s; survival %s; mice %s. Timestamp %s.</p>",
          html_escape(session$r_version),
          html_escape(session$packages$survival),
          html_escape(session$packages$mice),
          html_escape(meta$run_timestamp)),
  "</body></html>"
)

dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
writeLines(html, out_path)
message("Wrote ", out_path)
