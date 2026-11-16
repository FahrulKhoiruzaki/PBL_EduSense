from typing import Literal

from pydantic import BaseModel


class FaceScanOut(BaseModel):
    hasil: Literal["cocok", "duplikat", "kelas_lain", "tidak_dikenali"]
    # Kode mesin-baca untuk hasil selain "cocok": FaceNotRecognized, FaceDuplicate, FaceOtherClass.
    kode: str | None = None
    pesan: str | None = None
    siswa_id: int | None = None
    nama: str | None = None
    kelas: str | None = None
    waktu: str | None = None
    status: str | None = None


class FaceEnrollOut(BaseModel):
    siswa_id: int
    jumlah_foto: int
    model_version: str


class FaceStatusOut(BaseModel):
    siswa_id: int
    jumlah_foto: int
    maksimum: int
