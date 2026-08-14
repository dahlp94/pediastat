"""Tests for environment-backed configuration."""

from __future__ import annotations

from pathlib import Path

from pediastat.config import PROJECT_ROOT, Settings, load_yaml_config


def test_settings_load_successfully() -> None:
    settings = Settings(_env_file=None)
    assert settings.postgres_host
    assert settings.postgres_db
    assert settings.postgres_user


def test_default_port_is_integer() -> None:
    settings = Settings(_env_file=None)
    assert settings.postgres_port == 5432
    assert isinstance(settings.postgres_port, int)


def test_data_directory_resolves_relative_to_project_root() -> None:
    settings = Settings(_env_file=None)
    assert settings.data_dir == Path("data")
    assert settings.resolved_data_dir == (PROJECT_ROOT / "data").resolve()


def test_environment_variables_override_defaults(
    monkeypatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("POSTGRES_HOST", "db.example.org")
    monkeypatch.setenv("POSTGRES_PORT", "6543")
    monkeypatch.setenv("POSTGRES_DB", "testdb")
    monkeypatch.setenv("POSTGRES_USER", "tester")
    monkeypatch.setenv("DATA_DIR", str(tmp_path))

    settings = Settings(_env_file=None)

    assert settings.postgres_host == "db.example.org"
    assert settings.postgres_port == 6543
    assert settings.postgres_db == "testdb"
    assert settings.postgres_user == "tester"
    assert settings.resolved_data_dir == tmp_path.resolve()


def test_redacted_representation_hides_password(monkeypatch) -> None:
    secret = "supersecret-password"
    monkeypatch.setenv("POSTGRES_PASSWORD", secret)
    settings = Settings(_env_file=None)

    redacted = settings.redacted()
    rendered = repr(settings)

    assert settings.postgres_password.get_secret_value() == secret
    assert redacted["postgres_password"] == "[redacted]"
    assert secret not in str(redacted)
    assert secret not in rendered
    assert secret not in repr(redacted)


def test_yaml_config_loads_without_secrets() -> None:
    loaded = load_yaml_config()
    assert loaded["project"]["name"] == "pediastat"
    assert loaded["schemas"]["raw"] == "raw"
    database = loaded["database"]
    assert "password" not in database
