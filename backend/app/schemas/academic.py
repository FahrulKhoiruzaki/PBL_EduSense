"""Skema API akademik: periode, mata pelajaran, komponen nilai, aturan dan ringkasan klasifikasi."""

import re
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, Field, model_validator

_ACADEMIC_YEAR = re.compile(r"^(\d{4})/(\d{4})$")
_SUBJECT_CODE = re.compile(r"^[A-Z0-9]{2,12}$")

JenisMapel = Literal["umum", "muatan_lokal"]
KategoriLabel = Literal["Literasi", "Numerasi"]
MetodeKlasifikasi = Literal["rata_rata", "terendah"]


def _academic_year(value: str) -> str:
    value = value.strip()
    match = _ACADEMIC_YEAR.match(value)
    if not match or int(match.group(2)) != int(match.group(1)) + 1:
        raise ValueError("Gunakan format seperti 2026/2027.")
    return value


def _required_text(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Kolom ini wajib diisi.")
    return value


def _subject_code(value: str) -> str:
    value = value.strip().upper()
    if not _SUBJECT_CODE.match(value):
        raise ValueError("Gunakan 2-12 huruf kapital/angka tanpa spasi, mis. BIN atau BJAWA.")
    return value


def _levels(value: list[int]) -> list[int]:
    levels = sorted(set(value))
    if not levels:
        raise ValueError("Pilih minimal satu jenjang kelas.")
    if any(level < 1 or level > 6 for level in levels):
        raise ValueError("Jenjang kelas hanya 1 sampai 6.")
    return levels


AcademicYear = Annotated[str, AfterValidator(_academic_year)]
RequiredText = Annotated[str, Field(max_length=120), AfterValidator(_required_text)]


# Periode


class PeriodeOut(BaseModel):
    id: int
    tahun_ajaran: str
    semester: int
    semester_label: str
    label: str
    tanggal_mulai: date
    tanggal_selesai: date
    aktif: bool


class PeriodeAdminOut(PeriodeOut):
    jumlah_nilai: int
    jumlah_komponen: int
    punya_aturan: bool
    # Periode tanpa transaksi akademik dan tidak aktif boleh dihapus.
    dapat_dihapus: bool


class PeriodeIn(BaseModel):
    tahun_ajaran: AcademicYear
    semester: Literal[1, 2]
    tanggal_mulai: date
    tanggal_selesai: date

    @model_validator(mode="after")
    def _range(self) -> "PeriodeIn":
        if self.tanggal_selesai <= self.tanggal_mulai:
            raise ValueError("Tanggal selesai harus setelah tanggal mulai.")
        return self


# Mata pelajaran


class MapelOut(BaseModel):
    id: int
    kode: str
    nama: str
    deskripsi: str
    jenis: JenisMapel
    tingkat: list[int]
    aktif: bool
    urutan: int
    # Sudah dipakai penugasan, komponen, atau nilai: tidak dapat dihapus, hanya dinonaktifkan.
    dipakai: bool


class MapelIn(BaseModel):
    kode: Annotated[str, Field(max_length=12), AfterValidator(_subject_code)]
    nama: RequiredText
    deskripsi: str = Field(default="", max_length=1000)
    jenis: JenisMapel = "umum"
    tingkat: Annotated[list[int], Field(max_length=6), AfterValidator(_levels)] = [1, 2, 3, 4, 5, 6]
    urutan: int | None = Field(default=None, ge=0, le=10_000)


# Komponen penilaian


class KomponenRingkasOut(BaseModel):
    id: int
    nama: str
    kategori: KategoriLabel | None
    bobot: float | None
    aktif: bool


class KomponenOut(KomponenRingkasOut):
    periode_id: int
    mapel_id: int
    mapel: str
    mapel_kode: str
    deskripsi: str
    urutan: int
    jumlah_nilai: int


class KomponenIn(BaseModel):
    periode_id: int
    mapel_id: int
    kategori: KategoriLabel | None = None
    nama: RequiredText
    deskripsi: str = Field(default="", max_length=1000)
    bobot: float | None = Field(default=None, gt=0, le=100)
    urutan: int | None = Field(default=None, ge=0, le=10_000)


class KomponenCopyIn(BaseModel):
    dari_periode_id: int
    ke_periode_id: int


class CopyOut(BaseModel):
    disalin: int
    dilewati: int


# Aturan klasifikasi


class AturanOut(BaseModel):
    periode_id: int
    metode: MetodeKlasifikasi
    batas_mahir: float
    batas_cukup: float
    updated_at: datetime


class AturanIn(BaseModel):
    metode: MetodeKlasifikasi
    batas_mahir: float = Field(ge=0, le=100)
    batas_cukup: float = Field(ge=0, le=100)

    @model_validator(mode="after")
    def _order(self) -> "AturanIn":
        if self.batas_cukup >= self.batas_mahir:
            raise ValueError("Batas Cukup harus lebih rendah dari batas Mahir.")
        return self


class RecomputeOut(BaseModel):
    dihitung: int
    terklasifikasi: int


# Ringkasan klasifikasi (chart)


class JumlahKategoriOut(BaseModel):
    klasifikasi: Literal["Mahir", "Cukup", "Perlu Pendampingan"]
    jumlah: int
    # Persen dari siswa yang terklasifikasi (bukan dari seluruh siswa), satu desimal.
    persen: float


class DistribusiOut(BaseModel):
    total_siswa: int
    terklasifikasi: int
    # Punya nilai di periode ini tetapi belum memenuhi syarat (mis. hanya Literasi).
    belum_lengkap: int
    # Belum punya nilai sama sekali di periode ini (hanya dihitung untuk periode aktif).
    tanpa_nilai: int
    kategori: list[JumlahKategoriOut]


class KelasDistribusiOut(DistribusiOut):
    kelas: str


class PerbandinganOut(BaseModel):
    periode: PeriodeOut
    # Distribusi siswa yang sama pada periode sebelumnya (kohort yang sama, agar sebanding).
    sebelumnya: DistribusiOut
    sekarang: DistribusiOut
    dibandingkan: int
    naik: int
    turun: int
    tetap: int


class KlasifikasiRingkasanOut(BaseModel):
    periode: PeriodeOut | None
    aturan: AturanOut | None
    ringkasan: DistribusiOut
    per_kelas: list[KelasDistribusiOut]
    perbandingan: PerbandinganOut | None
    catatan: str | None


# Guru: mapel per kelas dan rekap


class MapelKelasOut(BaseModel):
    mapel_id: int
    kode: str
    nama: str
    jenis: JenisMapel
    # True bila guru ditugaskan mengajar mapel ini di kelas tersebut.
    boleh_input: bool
    komponen: list[KomponenRingkasOut]


class MapelRingkasOut(BaseModel):
    id: int
    kode: str
    nama: str


# Status kelengkapan penilaian satu mapel untuk satu siswa di satu periode:
#   lengkap            semua komponen AKTIF sudah dinilai -> nilai akhir tersedia
#   belum_lengkap      sebagian komponen aktif sudah dinilai -> nilai akhir TIDAK ditampilkan
#   belum_dinilai      belum ada nilai sama sekali
#   belum_ada_komponen admin belum menetapkan komponen mapel ini di periode itu
StatusPenilaian = Literal["lengkap", "belum_lengkap", "belum_dinilai", "belum_ada_komponen"]


class RekapSiswaOut(BaseModel):
    siswa_id: int
    nama: str
    # Rata-rata nilai per komponen, urut sama dengan `komponen`; None bila belum ada nilai.
    nilai_komponen: list[float | None]
    # Hanya terisi bila status "lengkap"; selain itu None (bukan nol, bukan nilai sementara).
    nilai_akhir: float | None
    status: StatusPenilaian
    komponen_terisi: int
    komponen_wajib: int


class PerkembanganMapelOut(BaseModel):
    """Rata-rata nilai akhir kelas untuk satu mapel di satu periode (siswa berstatus lengkap)."""

    periode: PeriodeOut
    rata_rata: float | None
    jumlah_lengkap: int
    jumlah_siswa: int


class RekapOut(BaseModel):
    periode: PeriodeOut
    mapel: MapelRingkasOut
    komponen: list[KomponenRingkasOut]
    # "berbobot" bila semua komponen yang dinilai punya bobot; selain itu "rata_rata".
    metode: Literal["berbobot", "rata_rata"]
    siswa: list[RekapSiswaOut]
    # Periode yang punya komponen mapel ini, terlama dulu (siswa = anggota kelas saat ini).
    perkembangan: list[PerkembanganMapelOut]


# Titik tren berlabel waktu (untuk sumbu X grafik)


class TitikTrenOut(BaseModel):
    # Senin awal minggu (ISO). Nilai = rata-rata nilai minggu itu, atau persen hadir untuk kehadiran.
    tanggal: date
    nilai: float
    # Jumlah nilai (atau catatan absensi) yang membentuk titik ini.
    jumlah: int


class TitikTrenSetOut(BaseModel):
    literasi: list[TitikTrenOut]
    numerasi: list[TitikTrenOut]
    kehadiran: list[TitikTrenOut]


# Rapor siswa (semua mata pelajaran)


class KomponenNilaiOut(KomponenRingkasOut):
    # Rata-rata nilai siswa pada komponen ini; None bila belum dinilai.
    nilai: float | None
    jumlah_nilai: int


class MapelRaporOut(BaseModel):
    mapel_id: int
    kode: str
    nama: str
    jenis: JenisMapel
    status: StatusPenilaian
    komponen_terisi: int
    komponen_wajib: int
    nilai_akhir: float | None
    metode: Literal["berbobot", "rata_rata"]
    komponen: list[KomponenNilaiOut]


class RingkasanRaporOut(BaseModel):
    jumlah_mapel: int
    lengkap: int
    belum_lengkap: int
    belum_dinilai: int
    belum_ada_komponen: int
    # Rata-rata nilai akhir mapel berstatus lengkap pada periode ini saja; None bila belum ada.
    rata_rata_nilai_akhir: float | None


class SiswaRaporOut(BaseModel):
    id: int
    nama: str
    nis: str | None
    kelas: str


class RiwayatMapelOut(BaseModel):
    mapel_id: int
    nama: str
    status: StatusPenilaian
    nilai_akhir: float | None


class RiwayatPeriodeOut(BaseModel):
    periode: PeriodeOut
    klasifikasi: str | None
    mapel: list[RiwayatMapelOut]


class KehadiranRingkasOut(BaseModel):
    # Catatan absensi siswa pada periode rapor (tanpa periode: semua catatan).
    total: int
    hadir: int
    terlambat: int
    izin: int
    sakit: int
    alpa: int
    # (hadir + terlambat) / total x 100, satu desimal; None bila belum ada catatan.
    persen_hadir: float | None


class RaporOut(BaseModel):
    siswa: SiswaRaporOut
    # None = belum ada periode aktif dan tidak ada periode yang diminta.
    periode: PeriodeOut | None
    skor_literasi: float | None
    skor_numerasi: float | None
    klasifikasi: str | None
    ringkasan: RingkasanRaporOut
    mapel: list[MapelRaporOut]
    # Semua periode yang punya nilai siswa ini, terlama dulu (mapel dibatasi sama seperti `mapel`).
    riwayat: list[RiwayatPeriodeOut]
    # Nilai lama tanpa mata pelajaran pada periode ini (tidak masuk rapor per mapel).
    nilai_tanpa_mapel: int
    kehadiran: KehadiranRingkasOut
    # Tren mingguan siswa pada periode rapor (titik berlabel tanggal awal minggu).
    tren: TitikTrenSetOut
    catatan: str | None


class NilaiMapelSiswaOut(BaseModel):
    mapel_id: int
    status: StatusPenilaian
    komponen_terisi: int
    komponen_wajib: int
    nilai_akhir: float | None


class SiswaRaporKelasOut(BaseModel):
    siswa_id: int
    nama: str
    nilai: list[NilaiMapelSiswaOut]  # urut sama dengan `mapel`


class MapelKelasRingkasOut(MapelRingkasOut):
    jenis: JenisMapel
    lengkap: int
    belum_lengkap: int
    belum_dinilai: int
    # Rata-rata nilai akhir siswa berstatus lengkap; None bila belum ada.
    rata_rata: float | None


class RaporKelasOut(BaseModel):
    periode: PeriodeOut | None
    mapel: list[MapelKelasRingkasOut]
    siswa: list[SiswaRaporKelasOut]
    catatan: str | None
