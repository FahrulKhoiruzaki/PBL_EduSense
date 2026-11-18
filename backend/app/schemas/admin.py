import re
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, BeforeValidator, Field

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")
_CLASS_CODE = re.compile(r"^[1-6][A-Z]$")
_ACADEMIC_YEAR = re.compile(r"^(\d{4})/(\d{4})$")
_TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$")


def _name(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Kolom ini wajib diisi.")
    return value


def _email(value: str) -> str:
    value = value.strip().lower()
    if not _EMAIL.match(value):
        raise ValueError("Format email tidak valid.")
    return value


def _class_code(value: str) -> str:
    value = value.strip().upper()
    if not _CLASS_CODE.match(value):
        raise ValueError("Gunakan format seperti 5C.")
    return value


def _blank_to_none(value: object) -> object:
    return None if isinstance(value, str) and not value.strip() else value


def _academic_year(value: str) -> str:
    match = _ACADEMIC_YEAR.match(value.strip())
    if not match or int(match.group(2)) != int(match.group(1)) + 1:
        raise ValueError("Gunakan format seperti 2026/2027.")
    return value.strip()


def _optional_academic_year(value: str | None) -> str | None:
    return None if value is None else _academic_year(value)


def _late_limit(value: str | None) -> str | None:
    if value is None:
        return None
    if not _TIME.match(value.strip()):
        raise ValueError("Gunakan format jam seperti 07:15.")
    return value.strip()[:5]


Name = Annotated[str, Field(max_length=120), AfterValidator(_name)]
Email = Annotated[str, Field(max_length=254), AfterValidator(_email)]
ClassCode = Annotated[str, Field(max_length=10), AfterValidator(_class_code)]


class StaffIn(BaseModel):
    nama: Name
    email: Email


class GuruCreateIn(StaffIn):
    # Wali kelas ditentukan oleh penugasan kelas; nilai ini hanya petunjuk untuk langkah berikutnya.
    peran: Literal["wali", "mapel"] = "mapel"


class SiswaIn(BaseModel):
    nama: Name
    kelas: ClassCode
    nama_orang_tua: Name


class KelasCreateIn(BaseModel):
    kode: ClassCode


class WaliIn(BaseModel):
    guru_id: Annotated[int | None, BeforeValidator(_blank_to_none)]


class MapelIn(BaseModel):
    guru_id: int
    # Mata pelajaran yang diajarkan. Kosong = penugasan tingkat kelas saja (perilaku lama): guru
    # boleh mencatat absensi tetapi belum boleh memasukkan nilai.
    mapel_id: int | None = None


class MoveIn(BaseModel):
    siswa_ids: list[int] = Field(min_length=1, max_length=500)
    kelas_tujuan: ClassCode


class ActiveIn(BaseModel):
    aktif: bool


class SettingsIn(BaseModel):
    # Tahun ajaran mengikuti periode akademik aktif; kolom ini hanya diterima bila sama dengannya
    # (atau bila belum ada periode aktif). Kosong = tidak diubah.
    tahun_ajaran: Annotated[
        str | None, BeforeValidator(_blank_to_none), AfterValidator(_optional_academic_year)
    ] = None
    batas_jam_terlambat: Annotated[
        str | None, BeforeValidator(_blank_to_none), AfterValidator(_late_limit)
    ] = None


class PasswordIn(BaseModel):
    old_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=1, max_length=256)


class MeOut(BaseModel):
    id: int
    nama: str
    email: str


class CredentialsOut(BaseModel):
    id: int
    email: str
    password_sementara: str


class AccountOut(BaseModel):
    id: int
    nama: str
    email: str
    aktif: bool
    wajib_ganti_password: bool


class GuruAdminOut(AccountOut):
    peran: Literal["wali", "mapel"]


class SiswaAdminOut(AccountOut):
    kelas: str
    nama_orang_tua: str


class PenugasanOut(BaseModel):
    guru_id: int
    mapel_id: int | None
    mapel: str | None


class KelasAdminOut(BaseModel):
    kode: str
    wali_id: int | None
    # Guru mapel (unik) di kelas ini; detail mapel per guru ada di `penugasan`.
    mapel_ids: list[int]
    penugasan: list[PenugasanOut]


class LogOut(BaseModel):
    waktu: datetime
    jenis: str
    pesan: str


class SettingsOut(BaseModel):
    # Dari periode akademik aktif (fallback: nilai lama pengaturan sekolah).
    tahun_ajaran: str
    periode_aktif: str | None
    batas_jam_terlambat: str | None
