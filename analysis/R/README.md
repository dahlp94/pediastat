# R Statistical Analysis

This directory will contain the R scripts that implement the statistical
analysis plan.

Expected later scripts:

```text
01_build_analysis_cohort.R
02_descriptive_statistics.R
03_survival_analysis.R
04_missing_data.R
05_sensitivity_analysis.R
06_power_analysis.R
```

These files are not created yet. When they are added, they should:

- Read analysis-ready data from the analytics layer (or a documented extract)
- Define the cohort and endpoints explicitly
- Preserve missingness unless a documented method handles it
- Fit pre-specified models rather than searching for favorable results
- Write tables and figures consumed by the Quarto report

Expected packages include dplyr, tidyr, ggplot2, survival, gtsummary,
broom, and mice. Package versions will be recorded at analysis time.
