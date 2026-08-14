"""Application configuration for PediaStat.

Runtime settings are loaded from environment variables or a local ``.env``
file. Secrets are never hard-coded and are omitted from log-safe
representations.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_YAML_PATH = PROJECT_ROOT / "config" / "settings.yaml"
EXAMPLE_YAML_PATH = PROJECT_ROOT / "config" / "settings.example.yaml"


class Settings(BaseSettings):
    """Environment-backed application settings."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_db: str = "pediastat"
    postgres_user: str = "pediastat"
    postgres_password: SecretStr = SecretStr("")
    data_dir: Path = Path("data")

    @property
    def resolved_data_dir(self) -> Path:
        """Resolve ``DATA_DIR`` against the repository root when relative."""
        path = Path(self.data_dir)
        if not path.is_absolute():
            path = PROJECT_ROOT / path
        return path.resolve()

    def redacted(self) -> dict[str, Any]:
        """Return a snapshot suitable for logs (password omitted)."""
        return {
            "postgres_host": self.postgres_host,
            "postgres_port": self.postgres_port,
            "postgres_db": self.postgres_db,
            "postgres_user": self.postgres_user,
            "postgres_password": "[redacted]",
            "data_dir": str(self.resolved_data_dir),
        }

    def __repr__(self) -> str:
        return (
            "Settings("
            f"postgres_host={self.postgres_host!r}, "
            f"postgres_port={self.postgres_port!r}, "
            f"postgres_db={self.postgres_db!r}, "
            f"postgres_user={self.postgres_user!r}, "
            "postgres_password=SecretStr('[redacted]'), "
            f"data_dir={self.data_dir!r})"
        )


def load_yaml_config(path: Path | None = None) -> dict[str, Any]:
    """Load optional non-secret project settings from YAML.

    If ``path`` is omitted, ``config/settings.yaml`` is used when present;
    otherwise the committed example file is used. A ``password`` key under
    ``database`` is discarded if present.
    """
    if path is None:
        path = DEFAULT_YAML_PATH if DEFAULT_YAML_PATH.exists() else EXAMPLE_YAML_PATH
    if not path.exists():
        return {}

    with path.open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle) or {}
    if not isinstance(loaded, dict):
        msg = f"YAML config at {path} must be a mapping."
        raise ValueError(msg)

    database = loaded.get("database")
    if isinstance(database, dict):
        database.pop("password", None)
    return loaded


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide settings object."""
    return Settings()
