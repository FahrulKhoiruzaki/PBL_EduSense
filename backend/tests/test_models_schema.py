"""Memastikan model SQLAlchemy sama persis dengan database hasil schema.sql + migrasi."""

import sqlalchemy as sa
from sqlalchemy import inspect

from app.models import Base


def test_every_model_table_exists_with_the_same_columns(app):
    inspector = inspect(app.state.session_factory.kw["bind"])
    db_tables = set(inspector.get_table_names())

    for table in Base.metadata.sorted_tables:
        assert table.name in db_tables, f"tabel {table.name} tidak ada di database"
        db_columns = {c["name"] for c in inspector.get_columns(table.name)}
        model_columns = {c.name for c in table.columns}
        assert model_columns == db_columns, f"kolom {table.name} berbeda"


def test_no_database_table_is_missing_a_model(app):
    inspector = inspect(app.state.session_factory.kw["bind"])
    modelled = {t.name for t in Base.metadata.sorted_tables}
    assert set(inspector.get_table_names()) - modelled == set()


def test_enum_values_match_postgres_enums(app, db):
    expected = {
        "user_role": {"admin", "guru", "ortu"},
        "klasifikasi": {"Mahir", "Cukup", "Perlu Pendampingan"},
        "status_absensi": {"H", "T", "I", "S", "A"},
        "metode_input": {"manual", "face_recognition"},
        "kategori_nilai": {"Literasi", "Numerasi"},
        "konten_status": {"draft", "terbit", "arsip"},
    }
    for name, values in expected.items():
        rows = db.execute(
            sa.text(
                "SELECT e.enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid "
                "WHERE t.typname = :n"
            ),
            {"n": name},
        ).scalars()
        assert set(rows) == values

    mapped = {
        "user_role": {m.value for m in Base.metadata.tables["users"].c.role.type.enum_class},
        "status_absensi": {m.value for m in Base.metadata.tables["absensi"].c.status.type.enum_class},
    }
    assert mapped["user_role"] == expected["user_role"]
    assert mapped["status_absensi"] == expected["status_absensi"]


def test_composite_role_foreign_key_blocks_a_guru_row_on_a_parent_account(app, db):
    import pytest
    from sqlalchemy.exc import IntegrityError

    from app.models import Guru
    from app.models.base import UserRole
    from tests.factories import make_user

    ortu = make_user(db, UserRole.ORTU, "ortu@contoh.id")
    db.add(Guru(user_id=ortu.id, nama="Salah", role=UserRole.GURU))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()
