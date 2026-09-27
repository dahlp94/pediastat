"""Tests for database helpers that do not require PostgreSQL."""

from __future__ import annotations

from uuid import uuid4

import pytest

from pediastat.database import _split_sql, replace_gdc_entities
from pediastat.ingest import parse_cases


def test_split_sql_preserves_statements() -> None:
    sql = """
    -- setup
    CREATE SCHEMA raw;

    CREATE TABLE raw.example (
        id INTEGER
    );
    """
    statements = _split_sql(sql)
    assert len(statements) == 2
    assert statements[0].startswith("CREATE SCHEMA raw")
    assert "CREATE TABLE raw.example" in statements[1]


class _FakeResult:
    def scalar_one(self) -> object:
        return uuid4()


class _FakeConnection:
    def __init__(self, fail_on: str | None = None) -> None:
        self.statements: list[str] = []
        self.fail_on = fail_on
        self.exited_with: type[BaseException] | None = None

    def execute(self, statement: object, params: object = None) -> _FakeResult:
        sql = str(statement)
        self.statements.append(sql)
        if self.fail_on and self.fail_on in sql:
            raise RuntimeError("forced failure")
        return _FakeResult()


class _FakeTransaction:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection

    def __enter__(self) -> _FakeConnection:
        return self.connection

    def __exit__(
        self, exc_type: type[BaseException] | None, exc: object, tb: object
    ) -> bool:
        self.connection.exited_with = exc_type
        return False


class _FakeEngine:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection

    def begin(self) -> _FakeTransaction:
        return _FakeTransaction(self.connection)


def test_replace_gdc_entities_deletes_before_insert_and_rolls_back() -> None:
    parsed = parse_cases(
        [
            {
                "case_id": "abc",
                "submitter_id": "TARGET-20-PASFYF",
                "follow_ups": [
                    {"follow_up_id": "f1", "days_to_follow_up": 1},
                    {"follow_up_id": "f2", "days_to_follow_up": 2},
                ],
            }
        ]
    )

    connection = _FakeConnection()
    counts = replace_gdc_entities(
        _FakeEngine(connection),  # type: ignore[arg-type]
        source_id=uuid4(),
        run_id=uuid4(),
        entities=parsed,
    )
    assert counts["follow_ups"] == 2
    deletes = [sql for sql in connection.statements if sql.upper().startswith("DELETE")]
    inserts = [sql for sql in connection.statements if "INSERT INTO raw.gdc_" in sql]
    assert deletes
    assert any("raw.gdc_follow_ups" in sql for sql in inserts)

    failing = _FakeConnection(fail_on="INSERT INTO raw.gdc_follow_ups")
    with pytest.raises(RuntimeError, match="forced failure"):
        replace_gdc_entities(
            _FakeEngine(failing),  # type: ignore[arg-type]
            source_id=uuid4(),
            run_id=uuid4(),
            entities=parsed,
        )
    assert failing.exited_with is RuntimeError
    assert not any(
        "INSERT INTO staging.gdc_follow_ups" in sql for sql in failing.statements
    )
