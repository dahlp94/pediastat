# PediaStat project pitch

## 30-second version

PediaStat is an applied biostatistics study of overall survival in pediatric AML using public NCI TARGET-AML data. I started from a scientific question, audited overlapping GDC and clinical-supplement sources, and froze a cohort of 1,978 patients diagnosed before age 18 before looking at predictor–survival associations. I then followed a prespecified plan: Kaplan–Meier summaries, 30-fold multiple imputation, Cox models for protocol risk group and molecular markers, and diagnostics for proportional hazards, nonlinearity, and influence. The result is an investigator-facing prognostic association analysis, not a causal or machine-learning product.

## 60-second version

PediaStat asks which baseline characteristics are associated with overall survival among children and adolescents with AML. The data were public but messy: 2,492 GDC cases, seven overlapping clinical supplements, discordant overall-survival time fields, experimental identifiers, and missing AML-specific covariates. I reconciled those sources, excluded ambiguous non-patient records rather than guessing, and locked a primary cohort of 1,978 patients with 695 deaths before any modeling.

The analysis followed a written statistical analysis plan. Overall 5-year survival was about 63%. The primary Cox model, pooled across 30 imputations, found substantially higher adjusted hazards for both Standard and High protocol risk versus Low risk, a modest age association, and a WBC association of about 1.08 per doubling. A secondary molecular model found lower adjusted hazards for NPM, CEBPA, t(8;21), and inv(16), and a higher hazard for monosomy 7. Complete-case, spline, and proportional-hazards checks did not change the primary conclusions. I report prognostic associations and limitations, not causal effects or a validated prediction tool.
