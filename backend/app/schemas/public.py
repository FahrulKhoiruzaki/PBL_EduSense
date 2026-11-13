from datetime import date

from pydantic import BaseModel, ConfigDict


class _Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class InformasiOut(_Out):
    slug: str
    kategori: str
    tanggal: date
    judul: str
    ringkasan: str
    gambar_url: str | None = None


class InformasiDetailOut(InformasiOut):
    isi: str


class FotoOut(_Out):
    url: str


class KegiatanOut(_Out):
    slug: str
    kategori: str
    tanggal: date
    judul: str
    deskripsi: str
    gambar_url: str | None = None
    foto: list[FotoOut] = []


class FasilitasOut(_Out):
    id: int
    nama: str
    deskripsi: str
    gambar_url: str | None = None


class FaqOut(_Out):
    kategori: str
    pertanyaan: str
    jawaban: str


class GuruPublikOut(_Out):
    nama: str
    jabatan: str | None = None
    foto_url: str | None = None


class SekolahOut(_Out):
    nama: str
    kota: str
    npsn: str | None = None
    alamat: str | None = None
    akreditasi: str | None = None
    telepon: str | None = None
    email: str | None = None
    media_sosial: str | None = None
    whatsapp: str | None = None
    peta_url: str | None = None
    foto_url: str | None = None


class HalamanOut(_Out):
    kunci: str
    isi: str


class InformasiKelasPublikOut(_Out):
    id: int
    tingkat: int
    jenis: str
    judul: str
    deskripsi: str


class KalenderPublikOut(_Out):
    id: int
    judul: str
    deskripsi: str
    kategori: str
    tanggal_mulai: date
    tanggal_selesai: date | None = None
