from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.models.base import KategoriNilai, StatusAbsensi


class KelasRingkasOut(BaseModel):
    kelas: str
    jumlah_siswa: int
    persen_hadir: int


class SiswaKelasOut(BaseModel):
    id: int
    nama: str
    klasifikasi: str | None
    # Kosong bila siswa belum diabsen hari ini; aplikasi menampilkannya sebagai belum hadir.
    status: str | None
    waktu: str | None
    literasi: int
    numerasi: int
    menurun: bool


class NilaiOut(BaseModel):
    id: int
    siswa_id: int
    siswa: str
    kategori: str
    jenis_ujian: str
    nilai: float
    nilai_sebelumnya: float | None
    tanggal: date
    catatan_guru: str | None


class TrenOut(BaseModel):
    literasi: list[int]
    numerasi: list[int]
    kehadiran: list[int]


class KelasDetailOut(BaseModel):
    siswa: list[SiswaKelasOut]
    nilai: list[NilaiOut]
    rata_literasi: int
    rata_numerasi: int
    tren: TrenOut


class AbsensiManualIn(BaseModel):
    status: StatusAbsensi
    metode_input: Literal["manual"] = "manual"
    catatan: str | None = Field(default=None, max_length=500)


class FinishOut(BaseModel):
    jumlah_alpa: int


class NilaiIn(BaseModel):
    siswa_id: int
    kategori: KategoriNilai
    jenis_ujian: str = Field(min_length=1, max_length=100)
    nilai: float = Field(ge=0, le=100)
    tanggal: date
    catatan_guru: str | None = Field(default=None, max_length=1000)


class NilaiCreatedOut(BaseModel):
    id: int


class NotifikasiOut(BaseModel):
    id: int
    judul: str
    target: str | None
    target_id: int | None
    dibaca: bool
    kelompok: Literal["hari_ini", "sebelumnya"]
    created_at: datetime


class AktivitasOut(BaseModel):
    judul: str
    target: str | None
    target_id: int | None
    created_at: datetime
