from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.core.database import get_db
from app.core.errors import not_found
from app.models import (
    Berita,
    Fasilitas,
    Faq,
    Guru,
    HalamanSitus,
    Kegiatan,
    Pengumuman,
    ProfilSekolah,
)
from app.models.base import KontenStatus
from app.services import school_info_service
from app.schemas.public import (
    FasilitasOut,
    FaqOut,
    GuruPublikOut,
    HalamanOut,
    InformasiDetailOut,
    InformasiKelasPublikOut,
    InformasiOut,
    KalenderPublikOut,
    KegiatanOut,
    SekolahOut,
)


def _fresh(response: Response) -> None:
    # Konten dikelola admin dan harus langsung tampil setelah diubah, jadi selalu divalidasi ulang.
    response.headers["Cache-Control"] = "no-cache"


router = APIRouter(prefix="/public", tags=["public"], dependencies=[Depends(_fresh)])

Limit = Query(100, ge=1, le=500, description="Jumlah maksimum data terbaru")


def _informasi(row: Pengumuman | Berita, kategori: str) -> InformasiDetailOut:
    return InformasiDetailOut(
        slug=row.slug,
        kategori=kategori,
        tanggal=row.tanggal,
        judul=row.judul,
        ringkasan=row.ringkasan,
        gambar_url=row.gambar_url,
        isi=row.isi,
    )


def _kegiatan(row: Kegiatan) -> KegiatanOut:
    fotos = [{"url": f.url} for f in row.foto]
    return KegiatanOut(
        slug=row.slug,
        kategori=row.kategori.value,
        tanggal=row.tanggal,
        judul=row.judul,
        deskripsi=row.deskripsi,
        gambar_url=fotos[0]["url"] if fotos else None,
        foto=fotos,
    )


@router.get("/informasi", response_model=list[InformasiOut])
def list_informasi(db: Session = Depends(get_db), limit: int = Limit) -> list[InformasiDetailOut]:
    pengumuman = db.scalars(
        select(Pengumuman)
        .where(Pengumuman.status == KontenStatus.TERBIT)
        .order_by(Pengumuman.tanggal.desc(), Pengumuman.id.desc())
        .limit(limit)
    ).all()
    berita = db.scalars(
        select(Berita)
        .where(Berita.status == KontenStatus.TERBIT)
        .order_by(Berita.tanggal.desc(), Berita.id.desc())
        .limit(limit)
    ).all()

    items = [_informasi(p, "Pengumuman") for p in pengumuman]
    items += [_informasi(b, b.kategori.value) for b in berita]
    items.sort(key=lambda i: i.tanggal, reverse=True)
    return items[:limit]


@router.get("/informasi/{slug}", response_model=InformasiDetailOut)
def get_informasi(slug: str, db: Session = Depends(get_db)) -> InformasiDetailOut:
    berita = db.scalar(
        select(Berita).where(Berita.slug == slug, Berita.status == KontenStatus.TERBIT)
    )
    if berita is not None:
        return _informasi(berita, berita.kategori.value)

    pengumuman = db.scalar(
        select(Pengumuman).where(Pengumuman.slug == slug, Pengumuman.status == KontenStatus.TERBIT)
    )
    if pengumuman is None:
        raise not_found("Informasi tidak ditemukan.")
    return _informasi(pengumuman, "Pengumuman")


@router.get("/kegiatan", response_model=list[KegiatanOut])
def list_kegiatan(db: Session = Depends(get_db), limit: int = Limit) -> list[KegiatanOut]:
    rows = db.scalars(
        select(Kegiatan)
        .options(selectinload(Kegiatan.foto))
        .where(Kegiatan.status == KontenStatus.TERBIT)
        .order_by(Kegiatan.tanggal.desc(), Kegiatan.id.desc())
        .limit(limit)
    ).all()
    return [_kegiatan(r) for r in rows]


@router.get("/kegiatan/{slug}", response_model=KegiatanOut)
def get_kegiatan(slug: str, db: Session = Depends(get_db)) -> KegiatanOut:
    row = db.scalar(
        select(Kegiatan)
        .options(selectinload(Kegiatan.foto))
        .where(Kegiatan.slug == slug, Kegiatan.status == KontenStatus.TERBIT)
    )
    if row is None:
        raise not_found("Kegiatan tidak ditemukan.")
    return _kegiatan(row)


@router.get("/fasilitas", response_model=list[FasilitasOut])
def list_fasilitas(db: Session = Depends(get_db)) -> list[Fasilitas]:
    return list(
        db.scalars(
            select(Fasilitas).where(Fasilitas.tampil.is_(True)).order_by(Fasilitas.urutan, Fasilitas.id)
        )
    )


@router.get("/faq", response_model=list[FaqOut])
def list_faq(db: Session = Depends(get_db)) -> list[FaqOut]:
    rows = db.scalars(select(Faq).where(Faq.tampil.is_(True)).order_by(Faq.urutan, Faq.id)).all()
    return [
        FaqOut(kategori=r.kategori.value, pertanyaan=r.pertanyaan, jawaban=r.jawaban) for r in rows
    ]


@router.get("/guru", response_model=list[GuruPublikOut])
def list_guru(db: Session = Depends(get_db)) -> list[Guru]:
    return list(db.scalars(select(Guru).where(Guru.tampil_publik.is_(True)).order_by(Guru.nama)))


@router.get("/sekolah", response_model=SekolahOut)
def get_sekolah(db: Session = Depends(get_db)) -> ProfilSekolah:
    row = db.scalar(select(ProfilSekolah))
    if row is None:
        raise not_found("Profil sekolah belum diisi.")
    return row


@router.get("/halaman", response_model=list[HalamanOut])
def list_halaman(db: Session = Depends(get_db)) -> list[HalamanSitus]:
    return list(
        db.scalars(
            select(HalamanSitus).where(func.btrim(HalamanSitus.isi) != "").order_by(HalamanSitus.kunci)
        )
    )


@router.get("/kelas", response_model=list[InformasiKelasPublikOut])
def list_informasi_kelas(
    tingkat: int | None = Query(None, ge=1, le=6), db: Session = Depends(get_db)
):
    return school_info_service.list_class_info(db, only_visible=True, tingkat=tingkat)


@router.get("/kalender", response_model=list[KalenderPublikOut])
def list_kalender(db: Session = Depends(get_db)):
    return school_info_service.list_calendar(db, only_visible=True)
