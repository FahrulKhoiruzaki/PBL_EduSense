from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel

from app.schemas.academic import TitikTrenSetOut


class NilaiAnakOut(BaseModel):
    id: int
    kategori: str | None
    jenis_ujian: str
    mapel: str | None
    periode_id: int | None
    nilai: float
    nilai_sebelumnya: float | None
    tanggal: date
    catatan_guru: str | None


class RiwayatKlasifikasiOut(BaseModel):
    # Label waktu: "Ganjil 2026/2027" untuk hasil per periode, atau nama bulan untuk data lama.
    bulan: str
    klasifikasi: str


class TrenAnakOut(BaseModel):
    literasi: list[int]
    numerasi: list[int]
    kehadiran: list[int]
    # Data yang sama dengan tanggal awal minggu (untuk sumbu X grafik).
    titik: TitikTrenSetOut


class AnakOut(BaseModel):
    id: int
    nis: str | None
    nama: str
    kelas: str
    # Kosong bila sekolah belum menetapkan klasifikasi untuk siswa ini.
    klasifikasi: str | None
    literasi: int
    numerasi: int
    persen_kehadiran: int
    jumlah_terlambat: int
    tren: TrenAnakOut
    riwayat_klasifikasi: list[RiwayatKlasifikasiOut]
    nilai: list[NilaiAnakOut]
    wali_kelas: str | None
    tahun_ajaran: str
    # Periode yang dipakai untuk klasifikasi, rata-rata, tren, dan persen kehadiran.
    periode: str | None
    periode_id: int | None
    # Waktu lokal sekolah tanpa zona, agar aplikasi menampilkan tanggal yang sama dengan di sekolah.
    diperbarui: datetime | None


class KehadiranHariOut(BaseModel):
    tanggal: date
    status: str
    waktu: str | None
    catatan: str | None


class RiwayatItemOut(BaseModel):
    jenis: Literal["nilai", "kehadiran", "klasifikasi"]
    tanggal: date
    judul: str
    keterangan: str
