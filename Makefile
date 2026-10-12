PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
PYTEST ?= $(if $(wildcard .venv/bin/pytest),.venv/bin/pytest,pytest)
RUFF ?= $(if $(wildcard .venv/bin/ruff),.venv/bin/ruff,ruff)

.PHONY: test lint check audit db-bootstrap ingest-gdc ingest-supplements reconcile ingest cohort descriptive model-plan inference

CONDA_RSCRIPT := $(HOME)/miniconda3/envs/pediastat-r/bin/Rscript
CONDA_QUARTO := $(HOME)/miniconda3/envs/pediastat-r/bin/quarto
RSCRIPT ?= $(if $(wildcard $(CONDA_RSCRIPT)),$(CONDA_RSCRIPT),Rscript)
# Use the conda Quarto binary only when --version prints a version.
# A present shim that exits 0 without a version must not hide a working quarto.
QUARTO ?= $(shell \
candidate='$(CONDA_QUARTO)'; \
version=""; \
if [ -x "$$candidate" ]; then \
version=$$("$$candidate" --version 2>/dev/null | head -n 1); \
fi; \
if [ -n "$$version" ]; then \
printf '%s\n' "$$candidate"; \
else \
found=""; \
if command -v quarto >/dev/null 2>&1; then \
found=$$(command -v quarto); \
fi; \
found_version=""; \
if [ -n "$$found" ]; then \
found_version=$$("$$found" --version 2>/dev/null | head -n 1); \
fi; \
if [ -n "$$found_version" ]; then \
printf '%s\n' "$$found"; \
elif [ -x "$$candidate" ]; then \
printf '%s\n' "$$candidate"; \
else \
printf '%s\n' quarto; \
fi; \
fi)
# R executable in the same environment as RSCRIPT. QUARTO_DART_SASS is not
# assigned here: when the caller exports it, Quarto inherits that value.
QUARTO_R ?= $(shell rscript='$(RSCRIPT)'; \
if command -v "$$rscript" >/dev/null 2>&1; then \
resolved=$$(command -v "$$rscript"); \
else \
resolved="$$rscript"; \
fi; \
rdir=$$(dirname "$$resolved"); \
if [ -x "$$rdir/R" ]; then \
printf '%s\n' "$$rdir/R"; \
elif command -v R >/dev/null 2>&1; then \
command -v R; \
else \
printf '%s\n' R; \
fi)

export QUARTO
export QUARTO_R

test:
	$(PYTEST)

lint:
	$(RUFF) check .

check: lint test
	$(PYTHON) scripts/check_environment.py

audit:
	$(PYTHON) -m pediastat.gdc

db-bootstrap:
	$(PYTHON) scripts/bootstrap_database.py --local-cluster

ingest-gdc:
	$(PYTHON) scripts/ingest_gdc_cases.py --local-cluster

ingest-supplements:
	$(PYTHON) scripts/ingest_target_aml_supplements.py --local-cluster

reconcile:
	$(PYTHON) scripts/run_source_reconciliation.py --local-cluster

cohort:
	$(PYTHON) scripts/build_primary_cohort.py --local-cluster

ingest: ingest-gdc ingest-supplements reconcile

descriptive:
	$(PYTHON) scripts/check_environment.py
	$(RSCRIPT) analysis/R/run_descriptive.R
	@QUARTO='$(QUARTO)' QUARTO_R='$(QUARTO_R)' RSCRIPT='$(RSCRIPT)' sh analysis/R/render_quarto_or_fallback.sh reports/descriptive_analysis.qmd analysis/R/render_descriptive_report.R 'descriptive analysis' reports/descriptive_analysis.html

model-plan:
	$(PYTHON) scripts/check_environment.py
	$(RSCRIPT) analysis/R/run_model_preflight.R

inference:
	$(PYTHON) scripts/check_environment.py
	INFERENCE_DEFER_REPORT_RENDER=1 $(RSCRIPT) analysis/R/run_inference.R
	@QUARTO='$(QUARTO)' QUARTO_R='$(QUARTO_R)' RSCRIPT='$(RSCRIPT)' sh analysis/R/render_quarto_or_fallback.sh reports/inferential_analysis.qmd analysis/R/render_inference_report.R 'inferential analysis' reports/inferential_analysis.html
