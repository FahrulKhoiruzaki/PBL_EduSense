from datetime import date
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Absensi, Nilai, Siswa
from app.models.base import KategoriNilai, StatusAbsensi

PRESENT = (StatusAbsensi.HADIR, StatusAbsensi.TERLAMBAT)

STATUS_LABEL = {
    StatusAbsensi.HADIR: "Hadir",
    StatusAbsensi.TERLAMBAT: "Terlambat",
    StatusAbsensi.IZIN: "Izin",
    StatusAbsensi.SAKIT: "Sakit",
    StatusAbsensi.ALPA: "Alpa",
}

MONTHS_ID = (
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember",
)


def round_int(value: float | Decimal | None) -> int:
    return round(float(value)) if value is not None else 0


def weekly_grade_trend(
    db: Session, student_ids: list[int], category: KategoriNilai, points: int
) -> list[int]:
    week = func.date_trunc("week", Nilai.tanggal).label("week")
    rows = db.execute(
        select(week, func.avg(Nilai.nilai))
        .where(Nilai.siswa_id.in_(student_ids), Nilai.kategori == category)
        .group_by(week)
        .order_by(week.desc())
        .limit(points)
    ).all()
    return [round_int(avg) for _, avg in reversed(rows)]


def weekly_attendance_trend(db: Session, student_ids: list[int], points: int) -> list[int]:
    week = func.date_trunc("week", Absensi.tanggal).label("week")
    rows = db.execute(
        select(
            week,
            func.count(Absensi.id).filter(Absensi.status.in_(PRESENT)),
            func.count(Absensi.id),
        )
        .where(Absensi.siswa_id.in_(student_ids))
        .group_by(week)
        .order_by(week.desc())
        .limit(points)
    ).all()
    return [round(present / total * 100) for _, present, total in reversed(rows) if total]


def grade_rows(db: Session, student_ids: list[int], limit: int):
    """Nilai terbaru lebih dulu, dengan nilai sebelumnya (kategori yang sama) di kolom `prev`."""
    previous = func.lag(Nilai.nilai).over(
        partition_by=[Nilai.siswa_id, Nilai.kategori], order_by=[Nilai.tanggal, Nilai.id]
    )
    with_previous = (
        select(
            Nilai.id, Nilai.siswa_id, Nilai.kategori, Nilai.jenis_ujian, Nilai.nilai,
            Nilai.tanggal, Nilai.catatan_guru, previous.label("prev"),
        )
        .where(Nilai.siswa_id.in_(student_ids))
        .subquery()
    )
    return db.execute(
        select(with_previous, Siswa.nama)
        .join(Siswa, Siswa.id == with_previous.c.siswa_id)
        .order_by(with_previous.c.tanggal.desc(), with_previous.c.id.desc())
        .limit(limit)
    ).all()


def academic_year_start(tahun_ajaran: str, today: date) -> date:
    """Tahun ajaran dimulai 1 Juli tahun pertama (mis. '2026/2027' -> 2026-07-01)."""
    try:
        return date(int(tahun_ajaran[:4]), 7, 1)
    except ValueError:
        return date(today.year if today.month >= 7 else today.year - 1, 7, 1)
