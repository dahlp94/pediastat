# Analysis

This directory will hold the statistical analysis scripts.

R is the primary statistical-analysis language. Python may be used for
data-prep utilities, but inferential analyses belong under `analysis/R/`.

Scripts will be numbered so the workflow is explicit. Later stages are
expected to add:

```text
01_build_analysis_cohort.R
02_descriptive_statistics.R
03_survival_analysis.R
04_missing_data.R
05_sensitivity_analysis.R
06_power_analysis.R
```

Those scripts are not present in Stage 0. They will be written after the
source data are inspected and the statistical analysis plan is completed.
Do not treat empty filenames as a substitute for a written analysis plan.
