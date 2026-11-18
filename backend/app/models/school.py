from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import (
    ARRAY,
    BigInteger,
    Boolean,
    Date,
    Float,
    ForeignKey,
    Identity,
    Integer,
    Numeric,
    SmallInteger,
    Text,
    Time,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import DateTime

from .base import (
    Base,
    Klasifikasi,
    KategoriNilai,
    MetodeInput,
    StatusAbsensi,
    pg_enum,
)
from .user import Guru, OrangTua


def _pk() -> Mapped[int]:
    return mapped_column(BigInteger, Identity(always=True), primary_key=True)


def _now() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


class Kelas(Base):
    __tablename__ = "kelas"

    id: Mapped[int] = _pk()
    nama_kelas: Mapped[str] = mapped_column(Text, unique=True)
    wali_kelas_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("guru.id", ondelete="SET NULL"), unique=True
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()

    wali: Mapped[Guru | None] = relationship()
    siswa: Mapped[list["Siswa"]] = relationship(back_populates="kelas")


class PeriodeAkademik(Base):
    """Satu semester dalam satu tahun ajaran. Rentang tanggal antarperiode tidak tumpang tindih."""

    __tablename__ = "periode_akademik"
    __table_args__ = (UniqueConstraint("tahun_ajaran", "semester"),)

    id: Mapped[int] = _pk()
    tahun_ajaran: Mapped[str] = mapped_column(Text)
    semester: Mapped[int] = mapped_column(SmallInteger)
    tanggal_mulai: Mapped[date] = mapped_column(Date)
    tanggal_selesai: Mapped[date] = mapped_column(Date)
    aktif: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()

    @property
    def semester_label(self) -> str:
        return SEMESTER_LABEL.get(self.semester, str(self.semester))

    @property
    def label(self) -> str:
        return f"Semester {self.semester_label} {self.tahun_ajaran}"

    def contains(self, day: date) -> bool:
        return self.tanggal_mulai <= day <= self.tanggal_selesai


SEMESTER_LABEL = {1: "Ganjil", 2: "Genap"}


class MataPelajaran(Base):
    __tablename__ = "mata_pelajaran"

    id: Mapped[int] = _pk()
    kode: Mapped[str] = mapped_column(Text, unique=True)
    nama: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    jenis: Mapped[str] = mapped_column(Text, server_default="umum")
    tingkat: Mapped[list[int]] = mapped_column(ARRAY(SmallInteger))
    aktif: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    urutan: Mapped[int] = mapped_column(Integer, server_default="0")
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class MapelGuru(Base):
    """Penugasan guru mata pelajaran di satu kelas.

    `mapel_id` NULL adalah penugasan lama (sebelum ada data mata pelajaran): memberi hak absensi
    kelas, tetapi tidak memberi hak input nilai sampai admin menetapkan mata pelajarannya.
    """

    __tablename__ = "mapel_guru"

    id: Mapped[int] = _pk()
    guru_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("guru.id", ondelete="CASCADE"))
    kelas_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("kelas.id", ondelete="CASCADE"))
    mapel_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("mata_pelajaran.id", ondelete="RESTRICT")
    )
    created_at: Mapped[datetime] = _now()

    mapel: Mapped[MataPelajaran | None] = relationship()


class KomponenPenilaian(Base):
    """Definisi penilaian (mis. Tugas, Kuis) untuk satu mapel di satu periode."""

    __tablename__ = "komponen_penilaian"

    id: Mapped[int] = _pk()
    periode_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("periode_akademik.id", ondelete="RESTRICT")
    )
    mapel_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("mata_pelajaran.id", ondelete="RESTRICT")
    )
    kategori: Mapped[KategoriNilai | None] = mapped_column(pg_enum(KategoriNilai, "kategori_nilai"))
    nama: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    bobot: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    aktif: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    urutan: Mapped[int] = mapped_column(Integer, server_default="0")
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()

    periode: Mapped[PeriodeAkademik] = relationship()
    mapel: Mapped[MataPelajaran] = relationship()


class AturanKlasifikasi(Base):
    """Aturan klasifikasi satu periode. Tidak ada nilai bawaan; ditetapkan admin."""

    __tablename__ = "aturan_klasifikasi"

    periode_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("periode_akademik.id", ondelete="CASCADE"), primary_key=True
    )
    metode: Mapped[str] = mapped_column(Text)
    batas_mahir: Mapped[Decimal] = mapped_column(Numeric(5, 2))
    batas_cukup: Mapped[Decimal] = mapped_column(Numeric(5, 2))
    diubah_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL")
    )
    updated_at: Mapped[datetime] = _now()


class Siswa(Base):
    __tablename__ = "siswa"

    id: Mapped[int] = _pk()
    nis: Mapped[str | None] = mapped_column(Text)
    nama: Mapped[str] = mapped_column(Text)
    kelas_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("kelas.id", ondelete="RESTRICT"))
    orang_tua_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("orang_tua.id", ondelete="RESTRICT")
    )
    status_klasifikasi: Mapped[Klasifikasi | None] = mapped_column(
        pg_enum(Klasifikasi, "klasifikasi")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()

    kelas: Mapped[Kelas] = relationship(back_populates="siswa")
    orang_tua: Mapped[OrangTua] = relationship()


class RiwayatKlasifikasi(Base):
    __tablename__ = "riwayat_klasifikasi"
    __table_args__ = (UniqueConstraint("siswa_id", "periode"),)

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    periode: Mapped[date] = mapped_column(Date)
    klasifikasi: Mapped[Klasifikasi] = mapped_column(pg_enum(Klasifikasi, "klasifikasi"))
    created_at: Mapped[datetime] = _now()


class Absensi(Base):
    __tablename__ = "absensi"
    __table_args__ = (UniqueConstraint("siswa_id", "tanggal"),)

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    tanggal: Mapped[date] = mapped_column(Date)
    waktu: Mapped[time | None] = mapped_column(Time)
    status: Mapped[StatusAbsensi] = mapped_column(pg_enum(StatusAbsensi, "status_absensi"))
    metode_input: Mapped[MetodeInput] = mapped_column(
        pg_enum(MetodeInput, "metode_input"), server_default="manual"
    )
    catatan: Mapped[str | None] = mapped_column(Text)
    dicatat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("guru.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class Nilai(Base):
    """Hasil penilaian siswa.

    `periode_id`, `mapel_id`, dan `kategori` diisi trigger database dari komponennya. Nilai lama
    (sebelum ada komponen) hanya memiliki `kategori` dan periodenya dipetakan dari tanggal.
    """

    __tablename__ = "nilai"

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    kategori: Mapped[KategoriNilai | None] = mapped_column(pg_enum(KategoriNilai, "kategori_nilai"))
    jenis_ujian: Mapped[str] = mapped_column(Text)
    nilai: Mapped[float] = mapped_column(Numeric(5, 2))
    tanggal: Mapped[date] = mapped_column(Date)
    catatan_guru: Mapped[str | None] = mapped_column(Text)
    dicatat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("guru.id", ondelete="SET NULL")
    )
    periode_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("periode_akademik.id", ondelete="RESTRICT")
    )
    mapel_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("mata_pelajaran.id", ondelete="RESTRICT")
    )
    komponen_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("komponen_penilaian.id", ondelete="RESTRICT")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class KlasifikasiSiswa(Base):
    """Hasil klasifikasi siswa untuk satu periode, beserta skor sumbernya.

    Baris ada untuk setiap siswa yang memiliki nilai di periode itu. `klasifikasi` NULL berarti
    datanya belum lengkap (siswa tidak dimasukkan ke kategori mana pun).
    """

    __tablename__ = "klasifikasi_siswa"
    __table_args__ = (UniqueConstraint("siswa_id", "periode_id"),)

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    periode_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("periode_akademik.id", ondelete="RESTRICT")
    )
    kelas_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("kelas.id", ondelete="SET NULL")
    )
    skor_literasi: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    skor_numerasi: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    skor_akhir: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    klasifikasi: Mapped[Klasifikasi | None] = mapped_column(pg_enum(Klasifikasi, "klasifikasi"))
    dihitung_pada: Mapped[datetime] = _now()


class WajahSiswa(Base):
    __tablename__ = "wajah_siswa"

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    embedding: Mapped[list[float]] = mapped_column(ARRAY(Float(53)))
    model_version: Mapped[str] = mapped_column(Text)
    didaftarkan_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("guru.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()

    siswa: Mapped[Siswa] = relationship()
