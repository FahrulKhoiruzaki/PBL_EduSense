import re
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, BeforeValidator, Field

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")

Kategori = Literal["Pengumuman", "Berita", "Akademik", "PPDB", "Kegiatan"]
KegiatanKategoriT = Literal[
    "Akademik", "Ekstrakurikuler", "Upacara", "Kegiatan Siswa", "Sosial", "Acara Sekolah"
]
FaqKategoriT = Literal["Umum", "PPDB", "Keuangan", "Akademik", "Kegiatan"]
Status = Literal["draft", "terbit", "arsip"]


def _required(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Kolom ini wajib diisi.")
    return value


def _blank_to_none(value: object) -> object:
    return None if isinstance(value, str) and not value.strip() else value


def _image_url(value: str | None) -> str | None:
    """Hanya gambar unggahan sendiri atau tautan http(s); skema lain (javascript:, data:) ditolak."""
    if value is None:
        return None
    value = value.strip()
    if value.startswith("/media/") or re.match(r"^https?://\S+$", value):
        return value
    raise ValueError("Gunakan gambar yang diunggah atau tautan yang diawali http:// atau https://.")


def _email(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if not _EMAIL.match(value):
        raise ValueError("Format email tidak valid.")
    return value


def _whatsapp(value: str | None) -> str | None:
    """Menyimpan nomor dalam format internasional tanpa tanda (62812...), siap untuk wa.me."""
    if value is None:
        return None
    digits = re.sub(r"[\s\-().]", "", value.strip()).removeprefix("+")
    if not digits.isdigit():
        raise ValueError("Nomor WhatsApp hanya boleh berisi angka.")
    if digits.startswith("0"):
        digits = "62" + digits[1:]
    if not 8 <= len(digits) <= 15:
        raise ValueError("Nomor WhatsApp harus 8 sampai 15 angka.")
    return digits


def _max_length(limit: int):
    def check(value: str | None) -> str | None:
        if value is not None and len(value) > limit:
            raise ValueError(f"Maksimal {limit} karakter.")
        return value

    return AfterValidator(check)


def optional_text(limit: int, *extra: AfterValidator):
    """Teks opsional: kosong menjadi None, lalu dicek panjang dan aturan tambahan."""
    return Annotated[str | None, BeforeValidator(_blank_to_none), _max_length(limit), *extra]


Required = Annotated[str, AfterValidator(_required)]
ImageUrl = optional_text(500, AfterValidator(_image_url))


class PageOut(BaseModel):
    kunci: str
    label: str
    grup: str
    baris: int
    isi: str


class PagesIn(BaseModel):
    halaman: dict[str, Annotated[str, Field(max_length=20000)]] = Field(max_length=100)


class SchoolIn(BaseModel):
    nama: Annotated[Required, Field(max_length=120)]
    kota: Annotated[Required, Field(max_length=80)]
    npsn: optional_text(20) = None
    alamat: optional_text(300) = None
    akreditasi: optional_text(20) = None
    telepon: optional_text(40) = None
    email: optional_text(254, AfterValidator(_email)) = None
    media_sosial: optional_text(200) = None
    whatsapp: optional_text(30, AfterValidator(_whatsapp)) = None
    peta_url: ImageUrl = None


class SchoolOut(BaseModel):
    nama: str
    kota: str
    npsn: str | None
    alamat: str | None
    akreditasi: str | None
    telepon: str | None
    email: str | None
    media_sosial: str | None
    whatsapp: str | None
    peta_url: str | None
    foto_url: str | None = None


class PostIn(BaseModel):
    judul: Annotated[Required, Field(max_length=200)]
    kategori: Kategori
    ringkasan: Annotated[str, Field(max_length=500)] = ""
    isi: Annotated[str, Field(max_length=50000)] = ""
    gambar_url: ImageUrl = None
    tanggal: date | None = None
    status: Status = "draft"


class PostOut(BaseModel):
    slug: str
    kategori: str
    judul: str
    ringkasan: str
    gambar_url: str | None
    tanggal: date
    status: str
    diperbarui: datetime


class PostDetailOut(PostOut):
    isi: str


class KegiatanIn(BaseModel):
    judul: Annotated[Required, Field(max_length=200)]
    kategori: KegiatanKategoriT
    deskripsi: Annotated[str, Field(max_length=20000)] = ""
    tanggal: date | None = None
    status: Status = "draft"
    foto_urls: list[Annotated[str, Field(max_length=500), AfterValidator(_image_url)]] = Field(
        default_factory=list, max_length=20
    )


class KegiatanAdminOut(BaseModel):
    slug: str
    kategori: str
    judul: str
    deskripsi: str
    tanggal: date
    status: str
    foto_urls: list[str]


class FasilitasIn(BaseModel):
    nama: Annotated[Required, Field(max_length=120)]
    deskripsi: Annotated[str, Field(max_length=2000)] = ""
    gambar_url: ImageUrl = None
    urutan: Annotated[int | None, Field(ge=0, le=9999)] = None
    tampil: bool = True


class FasilitasAdminOut(BaseModel):
    id: int
    nama: str
    deskripsi: str
    gambar_url: str | None
    urutan: int
    tampil: bool


class FaqIn(BaseModel):
    kategori: FaqKategoriT
    pertanyaan: Annotated[Required, Field(max_length=300)]
    jawaban: Annotated[Required, Field(max_length=5000)]
    urutan: Annotated[int | None, Field(ge=0, le=9999)] = None
    tampil: bool = True


class FaqAdminOut(BaseModel):
    id: int
    kategori: str
    pertanyaan: str
    jawaban: str
    urutan: int
    tampil: bool


class MediaOut(BaseModel):
    url: str
    ukuran: int


class SchoolPhotoOut(BaseModel):
    foto_url: str
    ukuran: int
