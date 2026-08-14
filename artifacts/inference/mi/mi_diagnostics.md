# Stage 6 multiple-imputation diagnostics

- Software: mice 3.19.0
- m = 30
- maxit = 20
- seed = 20260814
- Nelson-Aalen auxiliary: nonparametric Fleming-Harrington; not from a Cox model.
- Outcome, time, ID, age, and sex were not imputed.
- Auxiliary race used a collapsed 4-level factor (White / Black or African American / Asian / Other) because source OMB cells included n = 8 and n = 13. Race is not in either principal Cox model. This choice was made before viewing hazard ratios.

## Plausibility
No impossible imputed values were detected in completed analysis covariates.

## Logged mice events
No mice loggedEvents rows.

## Convergence
Inspect mi_trace_plots.png and mi_chain_stability.csv. Chain means in the last five iterations should not wander without bound.

These diagnostics are not used to choose a more favorable Cox specification.
