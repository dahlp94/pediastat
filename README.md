# PediaStat

PediaStat is an applied biostatistics portfolio project that demonstrates a collaborative biostatistician workflow for pediatric oncology data. The project will analyze pediatric acute myeloid leukemia (AML) clinical data, likely from the NCI TARGET-AML program, with emphasis on study definitions, data QA/QC, a written analysis plan, and investigator-facing reporting. The eventual scientific objective is to evaluate associations between baseline patient/disease characteristics and overall survival among pediatric AML patients while explicitly addressing censoring, missing data, statistical assumptions, and uncertainty.

## Scientific Question

Among children and adolescents with acute myeloid leukemia, which baseline patient and disease characteristics are associated with overall survival, and how robust are those associations to missing-data and modeling assumptions?

This is an observational association question. Causal effects will not be claimed from the planned analysis.

## Project Goals

- State the scientific question, cohort, and endpoints before modeling.
- Keep raw clinical data immutable after ingestion and record transformations from raw to staging to analytics.
- Perform clinical data QA/QC, including explicit handling of missingness.
- Estimate associations with overall survival using standard, interpretable survival methods.
- Quantify uncertainty and assess robustness through missing-data and sensitivity analyses.
- Communicate findings in an investigator-facing statistical report.

## Planned Statistical Workflow

```text
Scientific Question
        ↓
Statistical Analysis Plan
        ↓
Raw Clinical Data
        ↓
Data QA/QC
        ↓
Analysis Cohort
        ↓
Descriptive Statistics
        ↓
Survival Analysis
        ↓
Missing-Data Analysis
        ↓
Sensitivity Analysis
        ↓
Power / Sample-Size Analysis
        ↓
Investigator-Facing Report
```

## Technology Stack

| Layer | Tool | Role |
| --- | --- | --- |
| Ingestion, validation, data utilities | Python 3.12+ | Load source files, validate raw data, write to PostgreSQL |
| Data storage | PostgreSQL | Separate `raw`, `staging`, and `analytics` schemas |
| Statistical analysis | R | Descriptive statistics, survival models, missing-data and sensitivity analyses |
| Investigator-facing report | Quarto | Cohort definition, tables, figures, interpretation, and limitations |

Predictive machine-learning models, dashboards, and cloud deployment are outside the initial scope.

## Repository Structure

```text
pediastat/
├── README.md
├── pyproject.toml
├── .gitignore
├── .env.example
├── Makefile
├── config/                  # Non-secret project settings examples
├── data/                    # raw / interim / processed (not committed)
├── docs/                    # SAP template, data dictionary, decision log
├── sql/                     # Schema and ingestion metadata DDL
├── artifacts/               # metadata summaries from source audits
├── src/pediastat/           # Python package
├── scripts/                 # Environment, audit, ingestion, reconciliation
├── analysis/                # Future R analysis scripts
├── reports/                 # Future Quarto reports
└── tests/                   # Automated tests for infrastructure
```

## Reproducibility

1. Create a Python 3.12+ virtual environment and install the package with development tools:

   ```bash
   python3.12 -m venv .venv
   source .venv/bin/activate
   pip install -e ".[dev]"
   ```

2. Copy `.env.example` to `.env` and replace placeholder credentials. Do not commit `.env`.

3. Confirm the local environment:

   ```bash
   make check
   ```

PostgreSQL is required only when data are ingested. Stage 0 checks do not require a running database. Source data are not included in this repository; downloaded clinical files belong under `data/raw/` and are gitignored.

The statistical analysis plan in `docs/statistical_analysis_plan.md` will be completed before primary modeling. Analysis choices should follow that plan rather than being selected after inspecting favorable results.

## Project Status

Stage 6 — frozen Stage 5 Cox models and multiple imputation have been
executed. The primary cohort remains N = 1978 (695 deaths; 1283
censored). Models were not redesigned from the observed associations.

## Stage 6 commands

```bash
make inference
```

This loads the locked PostgreSQL cohort, runs the frozen MICE
specification, fits and pools the primary and secondary Cox models,
writes aggregate artifacts under `artifacts/inference/`, and renders
`reports/stage6_inferential_analysis.qmd` when Quarto is available.
Person-level imputations under `data/interim/stage6/` are gitignored.

## Stage 5 commands

```bash
make model-plan
```

This writes aggregate planning artifacts under `artifacts/model_plan/`
and runs coding/preflight checks on the locked cohort. It does not fit
Cox models or run multiple imputation.

## Stage 4 commands

```bash
make descriptive
```

This reads the locked PostgreSQL cohort, writes aggregate artifacts under
`artifacts/descriptive/`, and renders `reports/stage4_descriptive_analysis.qmd`
when Quarto is available. It does not rebuild the cohort.

R is expected from the `pediastat-r` conda environment (see
`analysis/R/README.md`). Person-level extracts under `data/interim/stage4/`
are gitignored.


## Stage 2 commands

```bash
python scripts/bootstrap_database.py --local-cluster
python scripts/ingest_gdc_cases.py --local-cluster
python scripts/ingest_target_aml_supplements.py --local-cluster
python scripts/run_source_reconciliation.py --local-cluster
```

Or `make db-bootstrap` then `make ingest`. The local cluster uses `.pgdata`
on port 5433 and is gitignored. Downloaded XLSX files remain under
`data/raw/` and are gitignored.
