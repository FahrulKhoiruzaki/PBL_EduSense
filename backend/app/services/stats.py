from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Absensi, KomponenPenilaian, MataPelajaran, Nilai, PeriodeAkademik, Siswa
from app.models.base import KategoriNilai, StatusAbsensi
from app.schemas.academic import TitikTrenOut, TitikTrenSetOut
from app.services.periods import attendance_in, grades_in

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


def _grade_weeks(db, student_ids, category, points, periode):
    """(minggu, rata-rata mentah, jumlah nilai) terlama dulu; minggu tanpa nilai tidak ada."""
    week = func.date_trunc("week", Nilai.tanggal).label("week")
    stmt = select(week, func.avg(Nilai.nilai), func.count(Nilai.id)).where(
        Nilai.siswa_id.in_(student_ids), Nilai.kategori == category
    )
    rows = db.execute(grades_in(stmt, periode).group_by(week).order_by(week.desc()).limit(points)).all()
    return list(reversed(rows))


def _attendance_weeks(db, student_ids, points, periode):
    """(minggu, hadir+terlambat, total catatan) terlama dulu; minggu tanpa catatan tidak ada."""
    week = func.date_trunc("week", Absensi.tanggal).label("week")
    stmt = select(
        week,
        func.count(Absensi.id).filter(Absensi.status.in_(PRESENT)),
        func.count(Absensi.id),
    ).where(Absensi.siswa_id.in_(student_ids))
    rows = db.execute(attendance_in(stmt, periode).group_by(week).order_by(week.desc()).limit(points)).all()
    return [r for r in reversed(rows) if r[2]]


def weekly_grade_points(
    db: Session,
    student_ids: list[int],
    category: KategoriNilai,
    points: int,
    periode: PeriodeAkademik | None = None,
) -> list[TitikTrenOut]:
    """Rata-rata nilai per minggu; `tanggal` = Senin awal minggu."""
    return [
        TitikTrenOut(tanggal=_day(w), nilai=float(Decimal(avg).quantize(Decimal("0.01"))), jumlah=n)
        for w, avg, n in _grade_weeks(db, student_ids, category, points, periode)
    ]


def weekly_grade_trend(
    db: Session,
    student_ids: list[int],
    category: KategoriNilai,
    points: int,
    periode: PeriodeAkademik | None = None,
) -> list[int]:
    return [round_int(avg) for _, avg, _ in _grade_weeks(db, student_ids, category, points, periode)]


def weekly_attendance_points(
    db: Session, student_ids: list[int], points: int, periode: PeriodeAkademik | None = None
) -> list[TitikTrenOut]:
    """Persen hadir (Hadir + Terlambat) per minggu, satu desimal; `jumlah` = catatan absensi."""
    return [
        TitikTrenOut(tanggal=_day(w), nilai=round(present / total * 100, 1), jumlah=total)
        for w, present, total in _attendance_weeks(db, student_ids, points, periode)
    ]


def weekly_attendance_trend(
    db: Session, student_ids: list[int], points: int, periode: PeriodeAkademik | None = None
) -> list[int]:
    return [round(present / total * 100) for _, present, total in _attendance_weeks(db, student_ids, points, periode)]


def trend_points(
    db: Session, student_ids: list[int], points: int, periode: PeriodeAkademik | None
) -> TitikTrenSetOut:
    return TitikTrenSetOut(
        literasi=weekly_grade_points(db, student_ids, KategoriNilai.LITERASI, points, periode),
        numerasi=weekly_grade_points(db, student_ids, KategoriNilai.NUMERASI, points, periode),
        kehadiran=weekly_attendance_points(db, student_ids, points, periode),
    )


def _day(value) -> date:
    return value.date() if isinstance(value, datetime) else value


def grade_rows(
    db: Session, student_ids: list[int], limit: int, periode: PeriodeAkademik | None = None
):
    """Nilai terbaru lebih dulu, dengan nilai sebelumnya di kolom `prev`.

    "Sebelumnya" = nilai sebelumnya pada komponen yang sama; nilai lama tanpa komponen dibandingkan
    dalam kategori yang sama (perilaku lama). Kolom `mapel` dan `komponen` berisi nama (atau None).
    """
    previous = func.lag(Nilai.nilai).over(
        partition_by=[Nilai.siswa_id, Nilai.komponen_id, Nilai.kategori],
        order_by=[Nilai.tanggal, Nilai.id],
    )
    stmt = select(
        Nilai.id, Nilai.siswa_id, Nilai.kategori, Nilai.jenis_ujian, Nilai.nilai,
        Nilai.tanggal, Nilai.catatan_guru, Nilai.periode_id, Nilai.mapel_id, Nilai.komponen_id,
        previous.label("prev"),
    ).where(Nilai.siswa_id.in_(student_ids))
    with_previous = grades_in(stmt, periode).subquery()
    return db.execute(
        select(
            with_previous,
            Siswa.nama,
            MataPelajaran.nama.label("mapel"),
            KomponenPenilaian.nama.label("komponen"),
        )
        .join(Siswa, Siswa.id == with_previous.c.siswa_id)
        .outerjoin(MataPelajaran, MataPelajaran.id == with_previous.c.mapel_id)
        .outerjoin(KomponenPenilaian, KomponenPenilaian.id == with_previous.c.komponen_id)
        .order_by(with_previous.c.tanggal.desc(), with_previous.c.id.desc())
        .limit(limit)
    ).all()


def academic_year_start(tahun_ajaran: str, today: date) -> date:
    """Tahun ajaran dimulai 1 Juli tahun pertama (mis. '2026/2027' -> 2026-07-01)."""
    try:
        return date(int(tahun_ajaran[:4]), 7, 1)
    except ValueError:
        return date(today.year if today.month >= 7 else today.year - 1, 7, 1)
