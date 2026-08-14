PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
PYTEST ?= $(if $(wildcard .venv/bin/pytest),.venv/bin/pytest,pytest)
RUFF ?= $(if $(wildcard .venv/bin/ruff),.venv/bin/ruff,ruff)

.PHONY: test lint check audit

test:
	$(PYTEST)

lint:
	$(RUFF) check .

check: lint test
	$(PYTHON) scripts/check_environment.py

audit:
	$(PYTHON) scripts/audit_target_aml_source.py
