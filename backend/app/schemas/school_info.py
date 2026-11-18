from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, Field, ValidationInfo, field_validator

from app.schemas.cms import Required

Jenis = Literal["Pembelajaran", "Kegiatan"]
KategoriKalender = Literal["Kegiatan", "Libur", "Ujian", "Rapat"]


class InformasiKelasIn(BaseModel):
    tingkat: Annotated[int, Field(ge=1, le=6)]
    jenis: Jenis
    judul: Annotated[Required, Field(max_length=150)]
    deskripsi: Annotated[str, Field(max_length=5000)] = ""
    urutan: Annotated[int | None, Field(ge=0, le=9999)] = None
    tampil: bool = True


class InformasiKelasOut(BaseModel):
    id: int
    tingkat: int
    jenis: str
    judul: str
    deskripsi: str
    urutan: int
    tampil: bool


class KalenderIn(BaseModel):
    judul: Annotated[Required, Field(max_length=150)]
    deskripsi: Annotated[str, Field(max_length=2000)] = ""
    kategori: KategoriKalender = "Kegiatan"
    tanggal_mulai: date
    tanggal_selesai: date | None = None
    tampil: bool = True

    @field_validator("tanggal_selesai")
    @classmethod
    def _not_before_start(cls, value: date | None, info: ValidationInfo) -> date | None:
        start = info.data.get("tanggal_mulai")
        if value is not None and start is not None and value < start:
            raise ValueError("Tanggal selesai tidak boleh sebelum tanggal mulai.")
        return value


class KalenderOut(BaseModel):
    id: int
    judul: str
    deskripsi: str
    kategori: str
    tanggal_mulai: date
    tanggal_selesai: date | None
    tampil: bool
