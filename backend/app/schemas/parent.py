from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel


class NilaiAnakOut(BaseModel):
    id: int
    kategori: str
    jenis_ujian: str
    nilai: float
    nilai_sebelumnya: float | None
    tanggal: date
    catatan_guru: str | None


class RiwayatKlasifikasiOut(BaseModel):
    bulan: str
    klasifikasi: str


class TrenAnakOut(BaseModel):
    literasi: list[int]
    numerasi: list[int]
    kehadiran: list[int]


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
