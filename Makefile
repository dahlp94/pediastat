PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
PYTEST ?= $(if $(wildcard .venv/bin/pytest),.venv/bin/pytest,pytest)
RUFF ?= $(if $(wildcard .venv/bin/ruff),.venv/bin/ruff,ruff)

.PHONY: test lint check audit db-bootstrap ingest-gdc ingest-supplements reconcile ingest

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

ingest: ingest-gdc ingest-supplements reconcile
