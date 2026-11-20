from pathlib import Path

import pytest

from app.core.config import Settings

BASE = {"DATABASE_URL": "postgresql+psycopg://u@/db", "SECRET_KEY": "x" * 40}


@pytest.fixture
def env(monkeypatch, tmp_path):
    """Settings dari variabel lingkungan saja (tanpa .env asli di folder kerja)."""
    monkeypatch.chdir(tmp_path)
    for key in ("CORS_ORIGINS", "ENVIRONMENT"):
        monkeypatch.delenv(key, raising=False)
    for key, value in BASE.items():
        monkeypatch.setenv(key, value)
    return monkeypatch


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("", []),
        ("   ", []),
        ("https://sekolah.id", ["https://sekolah.id"]),
        ("https://a.id, https://b.id ,", ["https://a.id", "https://b.id"]),
    ],
)
def test_cors_origins_accepts_empty_and_comma_separated_values(env, raw, expected):
    env.setenv("CORS_ORIGINS", raw)

    assert Settings().cors_origins == expected


def test_a_dotenv_copied_from_the_example_loads(tmp_path, monkeypatch):
    example = Path(__file__).resolve().parents[1] / ".env.example"
    lines = [
        "SECRET_KEY=" + "k" * 40 if line.startswith("SECRET_KEY=") else line
        for line in example.read_text().splitlines()
    ]
    (tmp_path / ".env").write_text("\n".join(lines))
    monkeypatch.chdir(tmp_path)
    for key in ("CORS_ORIGINS", "ENVIRONMENT", "DATABASE_URL", "SECRET_KEY"):
        monkeypatch.delenv(key, raising=False)

    settings = Settings()

    assert settings.cors_origins == [] and settings.environment == "development"
