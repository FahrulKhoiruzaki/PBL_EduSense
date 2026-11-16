from datetime import date, datetime, time

from sqlalchemy import (
    ARRAY,
    BigInteger,
    Date,
    Float,
    ForeignKey,
    Identity,
    Numeric,
    Text,
    Time,
    UniqueConstraint,
    func,
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


class MapelGuru(Base):
    __tablename__ = "mapel_guru"
    __table_args__ = (UniqueConstraint("guru_id", "kelas_id"),)

    id: Mapped[int] = _pk()
    guru_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("guru.id", ondelete="CASCADE"))
    kelas_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("kelas.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = _now()


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
    __tablename__ = "nilai"

    id: Mapped[int] = _pk()
    siswa_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("siswa.id", ondelete="CASCADE"))
    kategori: Mapped[KategoriNilai] = mapped_column(pg_enum(KategoriNilai, "kategori_nilai"))
    jenis_ujian: Mapped[str] = mapped_column(Text)
    nilai: Mapped[float] = mapped_column(Numeric(5, 2))
    tanggal: Mapped[date] = mapped_column(Date)
    catatan_guru: Mapped[str | None] = mapped_column(Text)
    dicatat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("guru.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


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
