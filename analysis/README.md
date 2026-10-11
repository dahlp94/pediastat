# Analysis

R is the primary statistical-analysis language. Python is used for
ingestion, cohort construction, and the model-preflight export.

Current scripts live under `analysis/R/`. See `analysis/R/README.md`.

Descriptive analysis: Table 1, missingness, overall KM, reverse KM.
Model preflight: inferential coding and checks (no Cox fit, no `mice()`).
Inference: execute the frozen Cox + MI plan (`make inference`).
