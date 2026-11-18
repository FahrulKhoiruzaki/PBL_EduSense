import enum
from typing import TypeVar

from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import DeclarativeBase

E = TypeVar("E", bound=enum.Enum)


class Base(DeclarativeBase):
    pass


def pg_enum(enum_cls: type[E], name: str) -> SAEnum:
    """Memetakan enum PostgreSQL yang sudah dibuat oleh schema.sql (nilai, bukan nama anggota)."""
    return SAEnum(
        enum_cls,
        name=name,
        values_callable=lambda e: [m.value for m in e],
        create_type=False,
        validate_strings=True,
    )


class UserRole(str, enum.Enum):
    ADMIN = "admin"
    GURU = "guru"
    ORTU = "ortu"


class Klasifikasi(str, enum.Enum):
    MAHIR = "Mahir"
    CUKUP = "Cukup"
    PERLU_PENDAMPINGAN = "Perlu Pendampingan"


class StatusAbsensi(str, enum.Enum):
    HADIR = "H"
    TERLAMBAT = "T"
    IZIN = "I"
    SAKIT = "S"
    ALPA = "A"


class MetodeInput(str, enum.Enum):
    MANUAL = "manual"
    FACE_RECOGNITION = "face_recognition"


class KategoriNilai(str, enum.Enum):
    LITERASI = "Literasi"
    NUMERASI = "Numerasi"


class KontenStatus(str, enum.Enum):
    DRAFT = "draft"
    TERBIT = "terbit"
    ARSIP = "arsip"


class BeritaKategori(str, enum.Enum):
    BERITA = "Berita"
    AKADEMIK = "Akademik"
    PPDB = "PPDB"
    KEGIATAN = "Kegiatan"


class KegiatanKategori(str, enum.Enum):
    AKADEMIK = "Akademik"
    EKSTRAKURIKULER = "Ekstrakurikuler"
    UPACARA = "Upacara"
    KEGIATAN_SISWA = "Kegiatan Siswa"
    SOSIAL = "Sosial"
    ACARA_SEKOLAH = "Acara Sekolah"


class FaqKategori(str, enum.Enum):
    UMUM = "Umum"
    PPDB = "PPDB"
    KEUANGAN = "Keuangan"
    AKADEMIK = "Akademik"
    KEGIATAN = "Kegiatan"


class LogTipe(str, enum.Enum):
    KELAS = "Kelas"
    AKUN = "Akun"
    SISWA = "Siswa"
    SISTEM = "Sistem"
