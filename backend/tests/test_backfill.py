"""Backfill periode untuk nilai lama (scripts.backfill_periode_nilai)."""

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select, text

from app.models import AturanKlasifikasi, KlasifikasiSiswa, Nilai
from app.models.base import KategoriNilai
from scripts import backfill_periode_nilai as backfill
from tests.factories import make_class, make_period, make_student

L, N = KategoriNilai.LITERASI, KategoriNilai.NUMERASI


def legacy(db, siswa, kategori, value, day):
    row = Nilai(siswa_id=siswa.id, kategori=kategori, jenis_ujian="UH", nilai=Decimal(value), tanggal=day)
    db.add(row)
    db.commit()
    return row


@pytest.fixture
def legacy_world(db):
    """Nilai lama dibuat SEBELUM ada periode (kondisi database sebelum migrasi 005)."""
    kelas = make_class(db, "5A")
    ahmad = make_student(db, "Ahmad", kelas)
    rows = {
        "n_lalu": legacy(db, ahmad, L, 70, date(2026, 3, 2)),
        "kini_l": legacy(db, ahmad, L, 90, date(2026, 9, 1)),
        "kini_n": legacy(db, ahmad, N, 80, date(2026, 9, 2)),
        "libur": legacy(db, ahmad, N, 60, date(2026, 7, 1)),  # libur: tidak tercakup periode
    }
    db.execute(text("ALTER TABLE nilai DISABLE TRIGGER trg_nilai_updated_at"))
    db.execute(text("UPDATE nilai SET updated_at = '2026-01-01T00:00:00+07'"))
    db.execute(text("ALTER TABLE nilai ENABLE TRIGGER trg_nilai_updated_at"))
    db.commit()
    assert all(r.periode_id is None for r in rows.values())
    lalu = make_period(db, "2025/2026", 2, date(2026, 1, 5), date(2026, 6, 20), aktif=False)
    kini = make_period(db)
    db.add(AturanKlasifikasi(periode_id=kini.id, metode="rata_rata",
                             batas_mahir=Decimal(80), batas_cukup=Decimal(65)))
    db.add(AturanKlasifikasi(periode_id=lalu.id, metode="rata_rata",
                             batas_mahir=Decimal(80), batas_cukup=Decimal(65)))
    db.commit()
    return {"ahmad": ahmad, "lalu": lalu, "kini": kini, **rows}


def _status(plan, nilai):
    return next(r for r in plan.rows if r.nilai_id == nilai.id)


def test_plan_maps_only_dates_inside_exactly_one_period(db, legacy_world):
    w = legacy_world
    plan = backfill.build_plan(db)
    mapped = {r.nilai_id: r.periode_id for r in plan.by_status(backfill.MAPPED)}
    assert mapped == {
        w["n_lalu"].id: w["lalu"].id,
        w["kini_l"].id: w["kini"].id,
        w["kini_n"].id: w["kini"].id,
    }
    assert [r.nilai_id for r in plan.by_status(backfill.UNMAPPED)] == [w["libur"].id]
    assert plan.by_status(backfill.PROBLEM) == []


def test_plan_reports_inconsistent_rows_without_touching_them(db, legacy_world):
    w = legacy_world
    # Simulasi data rusak (mis. impor manual saat trigger nonaktif).
    db.execute(text("ALTER TABLE nilai DISABLE TRIGGER trg_nilai_sinkron_periode"))
    db.execute(text("UPDATE nilai SET periode_id = :p WHERE id = :n"),
               {"p": w["kini"].id, "n": w["n_lalu"].id})
    db.execute(text("ALTER TABLE nilai ENABLE TRIGGER trg_nilai_sinkron_periode"))
    db.commit()
    problems = backfill.build_plan(db).by_status(backfill.PROBLEM)
    assert [(r.nilai_id, r.keterangan.startswith("Tanggal di luar")) for r in problems] == [
        (w["n_lalu"].id, True)
    ]


def test_dry_run_is_the_default_and_changes_nothing(db, legacy_world, capsys, monkeypatch):
    monkeypatch.setattr(backfill, "build_engine", lambda url: db.get_bind())
    monkeypatch.setattr(backfill, "build_session_factory", lambda engine: lambda: _NoClose(db))
    assert backfill.main([]) == 0
    out = capsys.readouterr().out
    assert "DRY-RUN" in out and "Dapat dipetakan       : 3" in out and "bulan 2026-07: 1" in out
    db.expire_all()
    assert db.scalar(select(Nilai.id).where(Nilai.periode_id.is_not(None))) is None


def test_apply_requires_explicit_confirmation(db, legacy_world, monkeypatch):
    monkeypatch.setattr(backfill, "build_engine", lambda url: db.get_bind())
    monkeypatch.setattr(backfill, "build_session_factory", lambda engine: lambda: _NoClose(db))
    monkeypatch.setattr("builtins.input", lambda prompt: "tidak")
    assert backfill.main(["--apply"]) == 1
    db.expire_all()
    assert db.scalar(select(Nilai.id).where(Nilai.periode_id.is_not(None))) is None


def test_apply_maps_keeps_updated_at_and_recomputes_active_period_only(db, legacy_world, tmp_path):
    w = legacy_world
    plan = backfill.build_plan(db)
    report = tmp_path / "laporan.csv"
    backfill.write_report(plan, report)
    assert report.read_text().count("\n") == 5  # header + 4 baris

    updated = backfill.apply_plan(db, plan)
    db.commit()
    assert updated == {w["lalu"].id: 1, w["kini"].id: 2}
    db.expire_all()
    periods = dict(db.execute(select(Nilai.id, Nilai.periode_id)).all())
    assert periods[w["n_lalu"].id] == w["lalu"].id
    assert periods[w["kini_l"].id] == periods[w["kini_n"].id] == w["kini"].id
    assert periods[w["libur"].id] is None
    # updated_at tidak berubah (backfill tidak tampil sebagai "nilai diperbarui").
    stamps = {s.date().isoformat() for s in db.scalars(select(Nilai.updated_at))}
    assert stamps <= {"2025-12-31", "2026-01-01"}
    # Trigger updated_at aktif kembali.
    enabled = db.scalar(text("SELECT tgenabled FROM pg_trigger WHERE tgname = 'trg_nilai_updated_at'"))
    assert enabled == "O"

    results = {r.periode_id: r for r in db.scalars(select(KlasifikasiSiswa))}
    assert set(results) == {w["kini"].id}  # periode lama tidak dihitung ulang secara default
    assert float(results[w["kini"].id].skor_akhir) == 85.0

    # Menjalankan ulang: tidak ada lagi yang perlu dipetakan (idempoten).
    again = backfill.build_plan(db)
    assert again.by_status(backfill.MAPPED) == []
    assert len(again.by_status(backfill.UNMAPPED)) == 1


def test_recompute_old_periods_is_opt_in(db, legacy_world):
    w = legacy_world
    backfill.apply_plan(db, backfill.build_plan(db), recompute_old=True)
    db.commit()
    periods = set(db.scalars(select(KlasifikasiSiswa.periode_id)))
    assert periods == {w["kini"].id, w["lalu"].id}


class _NoClose:
    """Membungkus sesi tes agar `with session:` di main() tidak menutupnya."""

    def __init__(self, db):
        self._db = db

    def __enter__(self):
        return self._db

    def __exit__(self, *exc):
        return False
