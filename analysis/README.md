# Analysis

R is the primary statistical-analysis language. Python is used for
ingestion, cohort construction, and the Stage 5 model-plan export.

Current scripts live under `analysis/R/`. See `analysis/R/README.md`.

Stage 4: descriptive Table 1, missingness, overall KM, reverse KM.  
Stage 5: inferential coding and preflight (no Cox fit, no `mice()`).  
Stage 6 will execute the frozen Cox + MI plan.
