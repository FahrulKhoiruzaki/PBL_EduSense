"""Aturan akses kelas untuk guru.

Wali kelas hanya boleh MELIHAT kelasnya (kontrak aplikasi: mode lihat). Mencatat absensi dan nilai
hanya untuk guru mapel kelas itu. Mengelola wajah siswa hanya untuk wali kelas.
"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import forbidden, not_found
from app.models import Guru, Kelas, MapelGuru, Siswa


def get_class(db: Session, kode: str) -> Kelas:
    kelas = db.scalar(select(Kelas).where(Kelas.nama_kelas == kode.upper()))
    if kelas is None:
        raise not_found("Kelas tidak ditemukan.")
    return kelas


def is_mapel(db: Session, guru: Guru, kelas: Kelas) -> bool:
    return (
        db.scalar(
            select(MapelGuru.id).where(MapelGuru.guru_id == guru.id, MapelGuru.kelas_id == kelas.id)
        )
        is not None
    )


def accessible_classes(db: Session, guru: Guru) -> list[Kelas]:
    """Kelas yang boleh dilihat guru: sebagai wali kelas atau guru mapel."""
    mapel_ids = select(MapelGuru.kelas_id).where(MapelGuru.guru_id == guru.id)
    return list(
        db.scalars(
            select(Kelas)
            .where((Kelas.wali_kelas_id == guru.id) | (Kelas.id.in_(mapel_ids)))
            .order_by(Kelas.nama_kelas)
        )
    )


def require_read(db: Session, guru: Guru, kelas: Kelas) -> None:
    if kelas.wali_kelas_id != guru.id and not is_mapel(db, guru, kelas):
        raise forbidden("Anda tidak mengampu kelas ini.")


def require_mapel(db: Session, guru: Guru, kelas: Kelas) -> None:
    if not is_mapel(db, guru, kelas):
        raise forbidden("Hanya guru mapel kelas ini yang dapat mencatat absensi dan nilai.")


def require_wali(guru: Guru, kelas: Kelas) -> None:
    if kelas.wali_kelas_id != guru.id:
        raise forbidden("Hanya wali kelas yang dapat mengelola wajah siswa kelasnya.")


def get_student(db: Session, kelas: Kelas, siswa_id: int) -> Siswa:
    siswa = db.get(Siswa, siswa_id)
    if siswa is None or siswa.kelas_id != kelas.id:
        raise not_found("Siswa tidak ditemukan di kelas ini.")
    return siswa
