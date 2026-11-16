"""Pembuat data uji."""

from datetime import date

from sqlalchemy.orm import Session

from app.models import (
    Berita,
    Fasilitas,
    Faq,
    Guru,
    HalamanSitus,
    Kegiatan,
    KegiatanFoto,
    Kelas,
    MapelGuru,
    OrangTua,
    Pengumuman,
    Siswa,
    User,
)
from app.models.base import (
    BeritaKategori,
    FaqKategori,
    KegiatanKategori,
    KontenStatus,
    UserRole,
)
from app.services.auth_service import create_user

PASSWORD = "Password123"


def make_user(
    db: Session,
    role: UserRole,
    email: str,
    nama: str = "Pengguna",
    *,
    password: str = PASSWORD,
    must_change: bool = False,
    nip: str | None = None,
) -> User:
    return create_user(
        db, role=role, email=email, nama=nama, password=password, must_change_password=must_change, nip=nip
    )


def make_guru(db: Session, email: str, nama: str = "Bu Guru", **kw) -> Guru:
    return make_user(db, UserRole.GURU, email, nama, **kw).guru_profile


def make_class(
    db: Session, nama: str, *, wali: Guru | None = None, mapel: tuple[Guru, ...] = ()
) -> Kelas:
    kelas = Kelas(nama_kelas=nama, wali_kelas_id=wali.id if wali else None)
    db.add(kelas)
    db.flush()
    for guru in mapel:
        db.add(MapelGuru(guru_id=guru.id, kelas_id=kelas.id))
    db.commit()
    return kelas


def make_student(db: Session, nama: str, kelas: Kelas, ortu: OrangTua | None = None) -> Siswa:
    if ortu is None:
        ortu = make_user(
            db, UserRole.ORTU, f"ortu.{nama.lower().replace(' ', '.')}@contoh.id", f"Ortu {nama}"
        ).ortu_profile
    siswa = Siswa(nama=nama, kelas_id=kelas.id, orang_tua_id=ortu.id)
    db.add(siswa)
    db.commit()
    return siswa


def publish(model, db: Session, **fields):
    row = model(status=KontenStatus.TERBIT, **fields)
    db.add(row)
    db.commit()
    return row


__all__ = [
    "PASSWORD",
    "Berita",
    "BeritaKategori",
    "Fasilitas",
    "Faq",
    "FaqKategori",
    "HalamanSitus",
    "Kegiatan",
    "KegiatanFoto",
    "KegiatanKategori",
    "KontenStatus",
    "Pengumuman",
    "date",
    "make_class",
    "make_guru",
    "make_student",
    "make_user",
    "publish",
]
