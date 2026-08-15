# Resume bullets

Use only one version on a resume. All numbers below match the completed analysis.

## Two-bullet concise version

- Constructed a reproducible pediatric AML overall-survival cohort from 2,492 public TARGET-AML cases by reconciling GDC clinical data with seven open supplement workbooks and excluding experimental or ambiguous identifiers, yielding 1,978 patients diagnosed before age 18 (695 deaths).
- Prespecified and fit multiply imputed Cox models (*m* = 30) for protocol risk group, WBC, and molecular/cytogenetic markers; conducted proportional-hazards, nonlinearity, and influence diagnostics; and produced investigator-facing survival reports without stepwise selection or causal claims.

## Three-bullet technical version

- Built a source-faithful Python/PostgreSQL pipeline that ingested 2,492 GDC TARGET-AML cases and 13 clinical-supplement sheets, quantified GDC–supplement discordance, and locked overall survival to GDC death and last-follow-up times after supplement OS-time fields disagreed.
- Defined a frozen analysis cohort of 1,978 pediatric patients (695 deaths; 1,283 censored) before examining predictor–survival associations; unknown vital status was not treated as censoring, and predictor completeness was not an inclusion rule.
- Implemented 30-fold MICE with Nelson–Aalen auxiliary information, pooled primary and secondary Cox models, and documented complete-case, spline, Schoenfeld, and influence diagnostics; primary conclusions were unchanged, and no observation was removed for influence.

## Biostatistics-targeted version

- Translated an investigator question—baseline correlates of overall survival in pediatric AML—into a written statistical analysis plan with a frozen cohort, endpoint, model formulas, missing-data strategy, FDR family, and proportional-hazards remediation hierarchy.
- Analyzed overall survival among 1,978 TARGET-AML patients using Kaplan–Meier and reverse Kaplan–Meier summaries plus multiply imputed Cox regression; reported adjusted HRs and 95% CIs for age, sex, WBC, protocol risk group, and a secondary molecular/cytogenetic model.
- Distinguished primary clinical findings from secondary biological analyses, retained sparse but valid observations (for example, monosomy 7), documented the single pre-result SAP deviation, and wrote investigator-facing reports that state limitations and avoid causal or predictive-validation claims.
