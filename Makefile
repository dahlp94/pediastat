PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
PYTEST ?= $(if $(wildcard .venv/bin/pytest),.venv/bin/pytest,pytest)
RUFF ?= $(if $(wildcard .venv/bin/ruff),.venv/bin/ruff,ruff)

.PHONY: test lint check audit db-bootstrap ingest-gdc ingest-supplements reconcile ingest cohort descriptive

CONDA_RSCRIPT := $(HOME)/miniconda3/envs/pediastat-r/bin/Rscript
CONDA_QUARTO := $(HOME)/miniconda3/envs/pediastat-r/bin/quarto
RSCRIPT ?= $(if $(wildcard $(CONDA_RSCRIPT)),$(CONDA_RSCRIPT),Rscript)
QUARTO ?= $(if $(wildcard $(CONDA_QUARTO)),$(CONDA_QUARTO),quarto)

test:
	$(PYTEST)

lint:
	$(RUFF) check .

check: lint test
	$(PYTHON) scripts/check_environment.py

audit:
	$(PYTHON) scripts/audit_target_aml_source.py

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
	$(RSCRIPT) analysis/R/run_stage4.R
	@if [ -x "$(QUARTO)" ] && [ -x "$(dir $(QUARTO))tools/x86_64/deno" ]; then \
		$(QUARTO) render reports/stage4_descriptive_analysis.qmd --to html --output-dir reports; \
	else \
		echo "Complete Quarto CLI not available; rendering HTML from Stage 4 artifacts with R."; \
		$(RSCRIPT) analysis/R/07_render_report.R; \
	fi
