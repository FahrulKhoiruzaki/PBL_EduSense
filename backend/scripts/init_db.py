"""Membuat tabel: schema.sql (bila database masih kosong) lalu semua migrasi.

    python -m scripts.init_db
"""

from pathlib import Path

import psycopg
from sqlalchemy.engine import make_url

from app.core.config import get_settings

DB_DIR = Path(__file__).resolve().parents[1] / "db"


def main() -> None:
    settings = get_settings()
    conninfo = make_url(settings.database_url).render_as_string(hide_password=False)
    conninfo = conninfo.replace("+psycopg", "", 1)

    with psycopg.connect(conninfo, autocommit=True) as conn:
        exists = conn.execute("SELECT to_regclass('public.users') IS NOT NULL").fetchone()[0]
        scripts = sorted((DB_DIR / "migrations").glob("*.sql"))
        if not exists:
            print("Database kosong: menerapkan schema.sql")
            scripts.insert(0, DB_DIR / "schema.sql")
        for script in scripts:
            print(f"Menerapkan {script.name}")
            conn.execute(script.read_text())
    print("Selesai.")


if __name__ == "__main__":
    main()
