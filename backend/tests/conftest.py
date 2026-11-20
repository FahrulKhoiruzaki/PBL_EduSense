"""Fixture tes. Tes berjalan di PostgreSQL sungguhan dengan schema.sql + migrasi.

Sumber database (berurutan):
  1. TEST_DATABASE_URL (nama database WAJIB berakhiran `_test`; isinya akan dikosongkan).
  2. Klaster PostgreSQL sementara yang dibuat sendiri (butuh `initdb`/`pg_ctl`; atur PG_BIN bila
     tidak ditemukan otomatis).
"""

import glob
import os
import shutil
import socket
import subprocess
import tempfile
from collections.abc import Iterator
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.main import create_app

ROOT = Path(__file__).resolve().parents[1]
SQL_FILES = [ROOT / "db" / "schema.sql", *sorted((ROOT / "db" / "migrations").glob("*.sql"))]
SINGLETONS = {"pengaturan_sekolah", "profil_sekolah"}


def _find_pg_bin() -> Path | None:
    candidates = [os.environ.get("PG_BIN")]
    which = shutil.which("pg_ctl")
    if which:
        candidates.append(str(Path(which).parent))
    for pattern in (
        "/Library/PostgreSQL/*/bin",
        "/opt/homebrew/opt/postgresql@*/bin",
        "/usr/local/opt/postgresql@*/bin",
        "/usr/lib/postgresql/*/bin",
    ):
        candidates.extend(sorted(glob.glob(pattern), reverse=True))
    for c in candidates:
        if c and (Path(c) / "initdb").exists() and (Path(c) / "pg_ctl").exists():
            return Path(c)
    return None


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _apply_schema(conninfo: str) -> None:
    with psycopg.connect(conninfo, autocommit=True) as conn:
        for path in SQL_FILES:
            conn.execute(path.read_text())


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    external = os.environ.get("TEST_DATABASE_URL")
    if external:
        url = make_url(external)
        if not (url.database or "").endswith("_test"):
            pytest.exit("TEST_DATABASE_URL harus menunjuk ke database berakhiran _test.", 2)
        conninfo = url.render_as_string(hide_password=False).replace("+psycopg", "", 1)
        with psycopg.connect(conninfo, autocommit=True) as conn:
            conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
        _apply_schema(conninfo)
        yield external
        return

    bin_dir = _find_pg_bin()
    if bin_dir is None:
        pytest.skip("PostgreSQL tidak ditemukan; atur PG_BIN atau TEST_DATABASE_URL.")

    base = Path(tempfile.mkdtemp(prefix="pgt", dir="/tmp"))
    data, port = base / "data", _free_port()
    subprocess.run(
        [bin_dir / "initdb", "-D", data, "-U", "tester", "--auth=trust", "-E", "UTF8"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        [
            bin_dir / "pg_ctl", "-D", data, "-w", "-l", base / "log",
            "-o", f"-p {port} -k {base} -c listen_addresses=''",
            "start",
        ],
        check=True,
        capture_output=True,
    )
    try:
        conninfo = f"host={base} port={port} user=tester dbname=postgres"
        with psycopg.connect(conninfo, autocommit=True) as conn:
            conn.execute("CREATE DATABASE sdn02_test")
        conninfo = f"host={base} port={port} user=tester dbname=sdn02_test"
        _apply_schema(conninfo)
        yield f"postgresql+psycopg://tester@/sdn02_test?host={base}&port={port}"
    finally:
        subprocess.run([bin_dir / "pg_ctl", "-D", data, "-m", "immediate", "stop"], capture_output=True)
        shutil.rmtree(base, ignore_errors=True)


@pytest.fixture(autouse=True)
def _clean_database(database_url: str) -> None:
    url = make_url(database_url)
    if url.drivername.startswith("postgresql+psycopg"):
        query = dict(url.query)
        conninfo = (
            f"host={query.get('host', url.host)} port={query.get('port', url.port or 5432)} "
            f"user={url.username} dbname={url.database}"
            + (f" password={url.password}" if url.password else "")
        )
    else:
        pytest.fail("Driver tidak didukung")

    with psycopg.connect(conninfo, autocommit=True) as conn:
        tables = [
            r[0]
            for r in conn.execute(
                "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
            ).fetchall()
            if r[0] not in SINGLETONS
        ]
        conn.execute(f"TRUNCATE {', '.join(tables)} RESTART IDENTITY CASCADE")
        conn.execute(
            "UPDATE pengaturan_sekolah SET batas_jam_terlambat = NULL, tahun_ajaran = '2026/2027'"
        )
        conn.execute(
            "UPDATE profil_sekolah SET nama = DEFAULT, kota = DEFAULT, npsn = NULL, alamat = NULL,"
            " akreditasi = NULL, telepon = NULL, email = NULL, media_sosial = NULL,"
            " whatsapp = NULL, peta_url = NULL, foto_url = NULL"
        )


@pytest.fixture
def settings(database_url: str, tmp_path: Path) -> Settings:
    return Settings(
        database_url=database_url,
        secret_key="x" * 48,
        environment="test",
        face_match_threshold=0.8,
        face_max_photos_per_student=3,
        max_upload_bytes=64 * 1024,
        media_dir=str(tmp_path / "media"),
        max_media_bytes=64 * 1024,
    )


@pytest.fixture
def app(settings: Settings):
    application = create_app(settings)
    with TestClient(application) as _:
        yield application


@pytest.fixture
def client(app) -> Iterator[TestClient]:
    with TestClient(app) as c:
        yield c


@pytest.fixture
def db(app) -> Iterator[Session]:
    session = app.state.session_factory()
    try:
        yield session
    finally:
        session.close()
