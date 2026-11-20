from datetime import date, datetime, time

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    ForeignKey,
    Identity,
    Integer,
    SmallInteger,
    Text,
    Time,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import DateTime

from .base import (
    Base,
    BeritaKategori,
    FaqKategori,
    KegiatanKategori,
    KontenStatus,
    LogTipe,
    pg_enum,
)


def _pk() -> Mapped[int]:
    return mapped_column(BigInteger, Identity(always=True), primary_key=True)


def _now() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


class Pengumuman(Base):
    __tablename__ = "pengumuman"

    id: Mapped[int] = _pk()
    slug: Mapped[str] = mapped_column(Text, unique=True)
    judul: Mapped[str] = mapped_column(Text)
    ringkasan: Mapped[str] = mapped_column(Text, server_default="")
    isi: Mapped[str] = mapped_column(Text, server_default="")
    gambar_url: Mapped[str | None] = mapped_column(Text)
    tanggal: Mapped[date] = mapped_column(Date, server_default=func.current_date())
    status: Mapped[KontenStatus] = mapped_column(
        pg_enum(KontenStatus, "konten_status"), server_default="draft"
    )
    dibuat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class Berita(Base):
    __tablename__ = "berita"

    id: Mapped[int] = _pk()
    slug: Mapped[str] = mapped_column(Text, unique=True)
    kategori: Mapped[BeritaKategori] = mapped_column(
        pg_enum(BeritaKategori, "berita_kategori"), server_default="Berita"
    )
    judul: Mapped[str] = mapped_column(Text)
    ringkasan: Mapped[str] = mapped_column(Text, server_default="")
    isi: Mapped[str] = mapped_column(Text, server_default="")
    gambar_url: Mapped[str | None] = mapped_column(Text)
    tanggal: Mapped[date] = mapped_column(Date, server_default=func.current_date())
    status: Mapped[KontenStatus] = mapped_column(
        pg_enum(KontenStatus, "konten_status"), server_default="draft"
    )
    dibuat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class Kegiatan(Base):
    __tablename__ = "kegiatan"

    id: Mapped[int] = _pk()
    slug: Mapped[str] = mapped_column(Text, unique=True)
    kategori: Mapped[KegiatanKategori] = mapped_column(
        pg_enum(KegiatanKategori, "kegiatan_kategori")
    )
    judul: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    tanggal: Mapped[date] = mapped_column(Date, server_default=func.current_date())
    status: Mapped[KontenStatus] = mapped_column(
        pg_enum(KontenStatus, "konten_status"), server_default="draft"
    )
    dibuat_oleh: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()

    foto: Mapped[list["KegiatanFoto"]] = relationship(
        back_populates="kegiatan", order_by="KegiatanFoto.urutan, KegiatanFoto.id"
    )


class KegiatanFoto(Base):
    __tablename__ = "kegiatan_foto"

    id: Mapped[int] = _pk()
    kegiatan_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("kegiatan.id", ondelete="CASCADE")
    )
    url: Mapped[str] = mapped_column(Text)
    keterangan: Mapped[str | None] = mapped_column(Text)
    urutan: Mapped[int] = mapped_column(Integer, server_default=text("0"))

    kegiatan: Mapped[Kegiatan] = relationship(back_populates="foto")


class Fasilitas(Base):
    __tablename__ = "fasilitas"

    id: Mapped[int] = _pk()
    nama: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    gambar_url: Mapped[str | None] = mapped_column(Text)
    urutan: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    tampil: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class Faq(Base):
    __tablename__ = "faq"

    id: Mapped[int] = _pk()
    kategori: Mapped[FaqKategori] = mapped_column(pg_enum(FaqKategori, "faq_kategori"))
    pertanyaan: Mapped[str] = mapped_column(Text)
    jawaban: Mapped[str] = mapped_column(Text, server_default="")
    urutan: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    tampil: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class InformasiKelas(Base):
    __tablename__ = "informasi_kelas"

    id: Mapped[int] = _pk()
    tingkat: Mapped[int] = mapped_column(SmallInteger)
    jenis: Mapped[str] = mapped_column(Text)
    judul: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    urutan: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    tampil: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class KalenderAkademik(Base):
    __tablename__ = "kalender_akademik"

    id: Mapped[int] = _pk()
    judul: Mapped[str] = mapped_column(Text)
    deskripsi: Mapped[str] = mapped_column(Text, server_default="")
    kategori: Mapped[str] = mapped_column(Text)
    tanggal_mulai: Mapped[date] = mapped_column(Date)
    tanggal_selesai: Mapped[date | None] = mapped_column(Date)
    tampil: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()


class ProfilSekolah(Base):
    __tablename__ = "profil_sekolah"

    id: Mapped[bool] = mapped_column(Boolean, primary_key=True, server_default=text("true"))
    nama: Mapped[str] = mapped_column(Text, server_default="SDN 02 Pakunden")
    kota: Mapped[str] = mapped_column(Text, server_default="Blitar")
    npsn: Mapped[str | None] = mapped_column(Text)
    alamat: Mapped[str | None] = mapped_column(Text)
    akreditasi: Mapped[str | None] = mapped_column(Text)
    telepon: Mapped[str | None] = mapped_column(Text)
    email: Mapped[str | None] = mapped_column(Text)
    media_sosial: Mapped[str | None] = mapped_column(Text)
    whatsapp: Mapped[str | None] = mapped_column(Text)
    peta_url: Mapped[str | None] = mapped_column(Text)
    foto_url: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime] = _now()


class HalamanSitus(Base):
    __tablename__ = "halaman_situs"

    kunci: Mapped[str] = mapped_column(Text, primary_key=True)
    isi: Mapped[str] = mapped_column(Text, server_default="")
    updated_at: Mapped[datetime] = _now()


class PengaturanSekolah(Base):
    __tablename__ = "pengaturan_sekolah"

    id: Mapped[bool] = mapped_column(Boolean, primary_key=True, server_default=text("true"))
    tahun_ajaran: Mapped[str] = mapped_column(Text)
    batas_jam_terlambat: Mapped[time | None] = mapped_column(Time)
    updated_at: Mapped[datetime] = _now()


class LogAktivitas(Base):
    __tablename__ = "log_aktivitas"

    id: Mapped[int] = _pk()
    user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL")
    )
    tipe: Mapped[LogTipe] = mapped_column(pg_enum(LogTipe, "log_tipe"))
    pesan: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = _now()


class Notifikasi(Base):
    __tablename__ = "notifikasi"

    id: Mapped[int] = _pk()
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id", ondelete="CASCADE"))
    judul: Mapped[str] = mapped_column(Text)
    target: Mapped[str | None] = mapped_column(Text)
    target_id: Mapped[int | None] = mapped_column(BigInteger)
    dibaca: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
    created_at: Mapped[datetime] = _now()
