"""Periode akademik terpusat: satu sumber kebenaran untuk tahun ajaran dan semester.

Semua fitur akademik (nilai, absensi, rekap, klasifikasi, statistik) menentukan periodenya lewat
modul ini, sehingga tidak ada halaman yang memakai tahun ajaran berbeda dari halaman lain.
Aturan pemilihan:
  * Bila klien mengirim `periode_id`, periode itu yang dipakai (404 bila tidak ada).
  * Bila tidak, periode aktif yang dipakai.
  * Bila belum ada periode aktif, hasilnya None dan pemanggil menampilkan data tanpa filter
    periode (perilaku lama) sambil memberi tahu klien bahwa periode belum ditetapkan.
"""

from datetime import date

from sqlalchemy import Select, and_, select
from sqlalchemy.orm import Session

from app.core.errors import not_found
from app.models import Absensi, Kelas, Nilai, PengaturanSekolah, PeriodeAkademik
from app.schemas.academic import PeriodeOut


def active_period(db: Session) -> PeriodeAkademik | None:
    return db.scalar(select(PeriodeAkademik).where(PeriodeAkademik.aktif))


def get_period(db: Session, periode_id: int) -> PeriodeAkademik:
    periode = db.get(PeriodeAkademik, periode_id)
    if periode is None:
        raise not_found("Periode akademik tidak ditemukan.")
    return periode


def resolve_period(db: Session, periode_id: int | None) -> PeriodeAkademik | None:
    return get_period(db, periode_id) if periode_id is not None else active_period(db)


def period_for_date(db: Session, day: date) -> PeriodeAkademik | None:
    return db.scalar(
        select(PeriodeAkademik).where(
            PeriodeAkademik.tanggal_mulai <= day, PeriodeAkademik.tanggal_selesai >= day
        )
    )


def ordered_periods(db: Session) -> list[PeriodeAkademik]:
    """Periode terbaru lebih dulu."""
    return list(db.scalars(select(PeriodeAkademik).order_by(PeriodeAkademik.tanggal_mulai.desc())))


def previous_period(db: Session, periode: PeriodeAkademik) -> PeriodeAkademik | None:
    return db.scalar(
        select(PeriodeAkademik)
        .where(PeriodeAkademik.tanggal_selesai < periode.tanggal_mulai)
        .order_by(PeriodeAkademik.tanggal_mulai.desc())
        .limit(1)
    )


def period_out(periode: PeriodeAkademik | None) -> PeriodeOut | None:
    if periode is None:
        return None
    return PeriodeOut(
        id=periode.id,
        tahun_ajaran=periode.tahun_ajaran,
        semester=periode.semester,
        semester_label=periode.semester_label,
        label=periode.label,
        tanggal_mulai=periode.tanggal_mulai,
        tanggal_selesai=periode.tanggal_selesai,
        aktif=periode.aktif,
    )


def current_academic_year(db: Session) -> str:
    """Tahun ajaran periode aktif; bila belum ada, nilai lama di pengaturan sekolah."""
    periode = active_period(db)
    if periode is not None:
        return periode.tahun_ajaran
    return db.scalar(select(PengaturanSekolah.tahun_ajaran)) or ""


def grades_in(stmt: Select, periode: PeriodeAkademik | None) -> Select:
    """Membatasi query nilai ke satu periode (tanpa periode: semua nilai, perilaku lama)."""
    return stmt if periode is None else stmt.where(Nilai.periode_id == periode.id)


def attendance_in(stmt: Select, periode: PeriodeAkademik | None) -> Select:
    """Absensi dipetakan ke periode lewat tanggalnya (tidak ada kolom periode di absensi)."""
    if periode is None:
        return stmt
    return stmt.where(
        and_(Absensi.tanggal >= periode.tanggal_mulai, Absensi.tanggal <= periode.tanggal_selesai)
    )


def class_level(kelas: Kelas) -> int:
    """Tingkat kelas dari kodenya ('5A' -> 5); format dijamin CHECK di database."""
    return int(kelas.nama_kelas[0])
