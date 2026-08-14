"""Create or reuse a project-local PostgreSQL cluster for PediaStat."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

from pediastat.config import PROJECT_ROOT, Settings
from pediastat.database.engine import SQL_FILES, apply_sql_file, create_db_engine

DEFAULT_DATA_DIR = PROJECT_ROOT / ".pgdata"
DEFAULT_PORT = 5432
DEFAULT_USER = "pediastat"
DEFAULT_DB = "pediastat"


def _postgres_bin(name: str) -> str:
    env_dir = os.environ.get("POSTGRES_BIN")
    candidates = []
    if env_dir:
        candidates.append(Path(env_dir) / name)
    which = shutil.which(name)
    if which:
        candidates.append(Path(which))
    candidates.extend(
        [
            Path("/Library/PostgreSQL/18/bin") / name,
            Path("/Library/PostgreSQL/17/bin") / name,
            Path("/usr/local/opt/postgresql@18/bin") / name,
            Path("/opt/homebrew/opt/postgresql@18/bin") / name,
        ]
    )
    for path in candidates:
        if path.is_file():
            return str(path)
    msg = f"Could not find {name}. Install PostgreSQL or set POSTGRES_BIN."
    raise FileNotFoundError(msg)


def cluster_is_running(data_dir: Path = DEFAULT_DATA_DIR) -> bool:
    pg_ctl = _postgres_bin("pg_ctl")
    result = subprocess.run(
        [pg_ctl, "-D", str(data_dir), "status"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def bootstrap_cluster(
    data_dir: Path = DEFAULT_DATA_DIR,
    port: int = DEFAULT_PORT,
    user: str = DEFAULT_USER,
    database: str = DEFAULT_DB,
) -> Settings:
    """Initialize a local trust-auth cluster if needed and apply DDL."""
    data_dir.mkdir(parents=True, exist_ok=True)
    pg_ctl = _postgres_bin("pg_ctl")
    initdb = _postgres_bin("initdb")
    createdb = _postgres_bin("createdb")
    marker = data_dir / "PG_VERSION"
    if not marker.exists():
        init_cmd = [
            initdb,
            "-D",
            str(data_dir),
            "-U",
            user,
            "--auth-local=trust",
            "--auth-host=trust",
            "--encoding=UTF8",
        ]
        result = subprocess.run(
            [*init_cmd, "--locale=C"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            for child in list(data_dir.iterdir()):
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            subprocess.run(init_cmd, check=True)
        config = data_dir / "postgresql.conf"
        extra = (
            f"\nport = {port}\n"
            f"unix_socket_directories = '{data_dir}'\n"
            "listen_addresses = 'localhost'\n"
        )
        config.write_text(config.read_text(encoding="utf-8") + extra, encoding="utf-8")
    if not cluster_is_running(data_dir):
        log_file = data_dir / "pg.log"
        subprocess.run(
            [
                pg_ctl,
                "-D",
                str(data_dir),
                "-l",
                str(log_file),
                "start",
            ],
            check=True,
        )
        time.sleep(1.0)
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": "localhost",
            "PGPORT": str(port),
            "PGUSER": user,
        }
    )
    exists = subprocess.run(
        [
            _postgres_bin("psql"),
            "-h",
            "localhost",
            "-p",
            str(port),
            "-U",
            user,
            "-d",
            "postgres",
            "-tAc",
            f"SELECT 1 FROM pg_database WHERE datname = '{database}'",
        ],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    if exists.stdout.strip() != "1":
        subprocess.run(
            [
                createdb,
                "-h",
                "localhost",
                "-p",
                str(port),
                "-U",
                user,
                database,
            ],
            check=True,
            env=env,
        )
    settings = Settings(
        postgres_host="localhost",
        postgres_port=port,
        postgres_db=database,
        postgres_user=user,
        postgres_password="",
        _env_file=None,
    )
    engine = create_db_engine(settings)
    sql_dir = PROJECT_ROOT / "sql"
    for name in SQL_FILES:
        apply_sql_file(engine, (sql_dir / name).read_text(encoding="utf-8"))
    return settings
