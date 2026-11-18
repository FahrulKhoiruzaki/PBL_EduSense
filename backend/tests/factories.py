"""Pembuat data uji."""

from datetime import date
from decimal import Decimal

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
    KomponenPenilaian,
    MapelGuru,
    MataPelajaran,
    OrangTua,
    PeriodeAkademik,
    Pengumuman,
    Siswa,
    User,
)
from app.models.base import (
    BeritaKategori,
    FaqKategori,
    KategoriNilai,
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


def make_period(
    db: Session,
    tahun: str = "2026/2027",
    semester: int = 1,
    mulai: date = date(2026, 7, 13),
    selesai: date = date(2026, 12, 19),
    *,
    aktif: bool = True,
) -> PeriodeAkademik:
    periode = PeriodeAkademik(
        tahun_ajaran=tahun, semester=semester, tanggal_mulai=mulai, tanggal_selesai=selesai, aktif=aktif
    )
    db.add(periode)
    db.commit()
    return periode


def make_subject(
    db: Session, kode: str, nama: str, *, jenis: str = "umum", tingkat=(1, 2, 3, 4, 5, 6), aktif: bool = True
) -> MataPelajaran:
    mapel = MataPelajaran(kode=kode, nama=nama, jenis=jenis, tingkat=list(tingkat), aktif=aktif)
    db.add(mapel)
    db.commit()
    return mapel


def make_component(
    db: Session,
    periode: PeriodeAkademik,
    mapel: MataPelajaran,
    nama: str,
    kategori: KategoriNilai | None = None,
    bobot: float | None = None,
    *,
    aktif: bool = True,
) -> KomponenPenilaian:
    komponen = KomponenPenilaian(
        periode_id=periode.id, mapel_id=mapel.id, kategori=kategori, nama=nama,
        bobot=Decimal(str(bobot)) if bobot is not None else None, aktif=aktif,
    )
    db.add(komponen)
    db.commit()
    return komponen


def assign(db: Session, guru: Guru, kelas: Kelas, mapel: MataPelajaran) -> MapelGuru:
    row = MapelGuru(guru_id=guru.id, kelas_id=kelas.id, mapel_id=mapel.id)
    db.add(row)
    db.commit()
    return row


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
    "KategoriNilai",
    "KontenStatus",
    "Pengumuman",
    "date",
    "assign",
    "make_class",
    "make_component",
    "make_guru",
    "make_period",
    "make_student",
    "make_subject",
    "make_user",
    "publish",
]
