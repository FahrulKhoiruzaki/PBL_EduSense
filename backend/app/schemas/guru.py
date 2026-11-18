from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.models.base import StatusAbsensi
from app.schemas.academic import PeriodeOut, TitikTrenSetOut


class KelasRingkasOut(BaseModel):
    kelas: str
    jumlah_siswa: int
    persen_hadir: int


class SiswaKelasOut(BaseModel):
    id: int
    nama: str
    # Klasifikasi pada periode yang ditampilkan; kosong bila belum diklasifikasi (bukan "Cukup").
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
    # Kosong untuk komponen di luar Literasi/Numerasi (mis. PJOK).
    kategori: str | None
    jenis_ujian: str
    periode_id: int | None
    mapel_id: int | None
    mapel: str | None
    komponen_id: int | None
    komponen: str | None
    nilai: float
    nilai_sebelumnya: float | None
    tanggal: date
    catatan_guru: str | None


class TrenOut(BaseModel):
    # Nilai bulat per minggu (kontrak lama, tetap ada).
    literasi: list[int]
    numerasi: list[int]
    kehadiran: list[int]
    # Data yang sama dengan tanggal awal minggu dan jumlah data per titik (untuk sumbu X grafik).
    titik: TitikTrenSetOut


class KelasDetailOut(BaseModel):
    # Periode yang dipakai untuk nilai, rata-rata, tren, dan klasifikasi. None = periode belum
    # ditetapkan admin (semua data ditampilkan). Status absensi siswa selalu untuk hari ini.
    periode: PeriodeOut | None
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
    # Komponen penilaian yang ditetapkan admin; menentukan mapel, kategori, dan periode nilai.
    komponen_id: int
    # Keterangan penilaian (mis. "Tugas Bab 2"); kosong = nama komponen.
    jenis_ujian: str | None = Field(default=None, max_length=100)
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
