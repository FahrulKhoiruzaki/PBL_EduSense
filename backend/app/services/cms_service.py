import re
import unicodedata
from datetime import date

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.errors import AppError, not_found
from app.models import (
    Berita,
    Fasilitas,
    Faq,
    HalamanSitus,
    Kegiatan,
    KegiatanFoto,
    Pengumuman,
    ProfilSekolah,
    User,
)
from app.models.base import (
    BeritaKategori,
    FaqKategori,
    KegiatanKategori,
    KontenStatus,
    LogTipe,
)
from app.schemas.cms import (
    FaqAdminOut,
    FaqIn,
    FasilitasAdminOut,
    FasilitasIn,
    KegiatanAdminOut,
    KegiatanIn,
    PageOut,
    PostDetailOut,
    PostIn,
    PostOut,
    SchoolIn,
    SchoolOut,
)
from app.services import cms_pages, log_service

PENGUMUMAN = "Pengumuman"
MAX_SLUG = 80
SUMMARY_LENGTH = 160


def _log(db: Session, actor: User, message: str) -> None:
    log_service.record(db, actor, LogTipe.SISTEM, f"{log_service.actor_name(actor)} {message}")


def _commit(db: Session, conflict_message: str) -> None:
    """Dua permintaan bersamaan dengan judul sama lolos pemeriksaan awal; indeks unik yang memutuskan."""
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise AppError(409, conflict_message) from None


def slugify(text: str) -> str:
    folded = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", folded).strip("-")
    if len(slug) > MAX_SLUG:
        slug = slug[:MAX_SLUG].rsplit("-", 1)[0]
    return slug or "tanpa-judul"


def _unique_slug(db: Session, title: str, *models: type) -> str:
    base = slugify(title)
    for number in range(1, 1000):
        candidate = base if number == 1 else f"{base}-{number}"
        if not any(db.scalar(select(m.id).where(m.slug == candidate)) is not None for m in models):
            return candidate
    raise AppError(409, "Tidak dapat membuat tautan dari judul ini. Gunakan judul yang berbeda.")


def _summary(ringkasan: str, isi: str) -> str:
    ringkasan = ringkasan.strip()
    if ringkasan:
        return ringkasan
    flat = " ".join(isi.split())
    return flat if len(flat) <= SUMMARY_LENGTH else flat[:SUMMARY_LENGTH].rstrip() + "…"


# Teks halaman


def list_pages(db: Session) -> list[PageOut]:
    stored = dict(db.execute(select(HalamanSitus.kunci, HalamanSitus.isi)).all())
    return [
        PageOut(kunci=p.kunci, label=p.label, grup=p.grup, baris=p.baris, isi=stored.get(p.kunci, ""))
        for p in cms_pages.PAGES
    ]


def save_pages(db: Session, actor: User, values: dict[str, str]) -> None:
    unknown = {k: "Kunci teks tidak dikenal." for k in values if k not in cms_pages.BY_KEY}
    if unknown:
        raise AppError(422, "Data yang dikirim tidak valid.", errors=unknown)

    existing = {r.kunci: r for r in db.scalars(select(HalamanSitus).where(HalamanSitus.kunci.in_(values)))}
    changed = 0
    for key, text in values.items():
        text = text.strip()
        row = existing.get(key)
        if not text:
            # Teks kosong dihapus agar website menampilkan pesan "informasi belum tersedia".
            if row is not None:
                db.delete(row)
                changed += 1
        elif row is None:
            db.add(HalamanSitus(kunci=key, isi=text))
            changed += 1
        elif row.isi != text:
            row.isi = text
            changed += 1
    if changed:
        _log(db, actor, f"memperbarui {changed} teks halaman website.")
    db.commit()


# Profil dan kontak sekolah


def _school_row(db: Session) -> ProfilSekolah:
    row = db.scalar(select(ProfilSekolah))
    if row is None:
        row = ProfilSekolah(id=True)
        db.add(row)
    return row


def get_school(db: Session) -> SchoolOut:
    row = _school_row(db)
    db.flush()
    return SchoolOut.model_validate(row, from_attributes=True)


def save_school(db: Session, actor: User, data: SchoolIn) -> SchoolOut:
    row = _school_row(db)
    for field, value in data.model_dump().items():
        setattr(row, field, value)
    _log(db, actor, "memperbarui profil dan kontak sekolah.")
    db.commit()
    return SchoolOut.model_validate(row, from_attributes=True)


def replace_school_photo(db: Session, actor: User, url: str) -> str | None:
    """Menyimpan alamat foto baru dan mengembalikan alamat lama (untuk dibersihkan pemanggil)."""
    row = _school_row(db)
    previous = row.foto_url
    row.foto_url = url
    _log(db, actor, "mengganti foto sekolah di beranda.")
    db.commit()
    return previous


# Berita dan pengumuman (dua tabel, satu daftar)


def _post_out(row: Pengumuman | Berita, kategori: str) -> PostDetailOut:
    return PostDetailOut(
        slug=row.slug,
        kategori=kategori,
        judul=row.judul,
        ringkasan=row.ringkasan,
        gambar_url=row.gambar_url,
        tanggal=row.tanggal,
        status=row.status.value,
        diperbarui=row.updated_at,
        isi=row.isi,
    )


def _find_post(db: Session, slug: str) -> tuple[Pengumuman | Berita, bool]:
    row = db.scalar(select(Berita).where(Berita.slug == slug))
    if row is not None:
        return row, False
    row = db.scalar(select(Pengumuman).where(Pengumuman.slug == slug))
    if row is None:
        raise not_found("Berita atau pengumuman tidak ditemukan.")
    return row, True


def list_posts(db: Session) -> list[PostOut]:
    items = [_post_out(r, PENGUMUMAN) for r in db.scalars(select(Pengumuman))]
    items += [_post_out(r, r.kategori.value) for r in db.scalars(select(Berita))]
    items.sort(key=lambda p: (p.tanggal, p.diperbarui), reverse=True)
    return [PostOut(**i.model_dump(exclude={"isi"})) for i in items]


def get_post(db: Session, slug: str) -> PostDetailOut:
    row, is_announcement = _find_post(db, slug)
    return _post_out(row, PENGUMUMAN if is_announcement else row.kategori.value)


def _post_values(data: PostIn, today: date) -> dict:
    return {
        "judul": data.judul,
        "ringkasan": _summary(data.ringkasan, data.isi),
        "isi": data.isi.strip(),
        "gambar_url": data.gambar_url,
        "tanggal": data.tanggal or today,
        "status": KontenStatus(data.status),
    }


def _noun(kategori: str) -> str:
    """Kata benda untuk log: kategori berita (Akademik, PPDB, ...) tetap disebut "berita"."""
    return "pengumuman" if kategori == PENGUMUMAN else "berita"


def create_post(db: Session, actor: User, data: PostIn, today: date) -> PostDetailOut:
    slug = _unique_slug(db, data.judul, Pengumuman, Berita)
    values = {**_post_values(data, today), "slug": slug, "dibuat_oleh": actor.id}
    if data.kategori == PENGUMUMAN:
        row = Pengumuman(**values)
    else:
        row = Berita(**values, kategori=BeritaKategori(data.kategori))
    db.add(row)
    _log(db, actor, f"membuat {_noun(data.kategori)} \"{data.judul}\".")
    _commit(db, "Judul ini sudah dipakai. Coba judul lain.")
    return get_post(db, slug)


def update_post(db: Session, actor: User, slug: str, data: PostIn, today: date) -> PostDetailOut:
    row, is_announcement = _find_post(db, slug)
    values = _post_values(data, today)
    # Tanggal yang tidak dikirim tetap seperti semula (bukan diganti hari ini).
    if data.tanggal is None:
        values["tanggal"] = row.tanggal

    wants_announcement = data.kategori == PENGUMUMAN
    if wants_announcement == is_announcement:
        for field, value in values.items():
            setattr(row, field, value)
        if not is_announcement:
            row.kategori = BeritaKategori(data.kategori)
    else:
        # Pengumuman dan berita tersimpan di tabel berbeda; pindahkan dengan slug yang sama.
        creator = row.dibuat_oleh
        db.execute(delete(type(row)).where(type(row).id == row.id))
        db.flush()
        values = {**values, "slug": slug, "dibuat_oleh": creator}
        if wants_announcement:
            db.add(Pengumuman(**values))
        else:
            db.add(Berita(**values, kategori=BeritaKategori(data.kategori)))
    _log(db, actor, f"memperbarui {_noun(data.kategori)} \"{data.judul}\".")
    _commit(db, "Perubahan tidak dapat disimpan karena bentrok dengan data lain.")
    db.expire_all()
    return get_post(db, slug)


def delete_post(db: Session, actor: User, slug: str) -> None:
    row, _ = _find_post(db, slug)
    title = row.judul
    db.execute(delete(type(row)).where(type(row).id == row.id))
    _log(db, actor, f"menghapus berita/pengumuman \"{title}\".")
    db.commit()


# Kegiatan dan galeri


def _kegiatan_out(row: Kegiatan) -> KegiatanAdminOut:
    return KegiatanAdminOut(
        slug=row.slug,
        kategori=row.kategori.value,
        judul=row.judul,
        deskripsi=row.deskripsi,
        tanggal=row.tanggal,
        status=row.status.value,
        foto_urls=[f.url for f in row.foto],
    )


def _get_kegiatan(db: Session, slug: str) -> Kegiatan:
    row = db.scalar(select(Kegiatan).options(selectinload(Kegiatan.foto)).where(Kegiatan.slug == slug))
    if row is None:
        raise not_found("Kegiatan tidak ditemukan.")
    return row


def _set_photos(db: Session, kegiatan_id: int, urls: list[str]) -> None:
    db.execute(delete(KegiatanFoto).where(KegiatanFoto.kegiatan_id == kegiatan_id))
    db.add_all(KegiatanFoto(kegiatan_id=kegiatan_id, url=url, urutan=i) for i, url in enumerate(urls))


def list_kegiatan(db: Session) -> list[KegiatanAdminOut]:
    rows = db.scalars(
        select(Kegiatan)
        .options(selectinload(Kegiatan.foto))
        .order_by(Kegiatan.tanggal.desc(), Kegiatan.id.desc())
    ).all()
    return [_kegiatan_out(r) for r in rows]


def create_kegiatan(db: Session, actor: User, data: KegiatanIn, today: date) -> KegiatanAdminOut:
    slug = _unique_slug(db, data.judul, Kegiatan)
    row = Kegiatan(
        slug=slug,
        kategori=KegiatanKategori(data.kategori),
        judul=data.judul,
        deskripsi=data.deskripsi.strip(),
        tanggal=data.tanggal or today,
        status=KontenStatus(data.status),
        dibuat_oleh=actor.id,
    )
    db.add(row)
    db.flush()
    _set_photos(db, row.id, data.foto_urls)
    _log(db, actor, f"membuat kegiatan \"{data.judul}\".")
    _commit(db, "Judul ini sudah dipakai. Coba judul lain.")
    return _kegiatan_out(_get_kegiatan(db, slug))


def update_kegiatan(
    db: Session, actor: User, slug: str, data: KegiatanIn, today: date
) -> KegiatanAdminOut:
    row = _get_kegiatan(db, slug)
    row.kategori = KegiatanKategori(data.kategori)
    row.judul = data.judul
    row.deskripsi = data.deskripsi.strip()
    row.tanggal = data.tanggal or row.tanggal
    row.status = KontenStatus(data.status)
    _set_photos(db, row.id, data.foto_urls)
    _log(db, actor, f"memperbarui kegiatan \"{data.judul}\".")
    db.commit()
    db.expire_all()
    return _kegiatan_out(_get_kegiatan(db, slug))


def delete_kegiatan(db: Session, actor: User, slug: str) -> None:
    row = _get_kegiatan(db, slug)
    title = row.judul
    db.execute(delete(Kegiatan).where(Kegiatan.id == row.id))
    _log(db, actor, f"menghapus kegiatan \"{title}\".")
    db.commit()


# Fasilitas


def _next_order(db: Session, model: type[Fasilitas] | type[Faq]) -> int:
    return (db.scalar(select(func.max(model.urutan))) or 0) + 1


def _fasilitas_out(row: Fasilitas) -> FasilitasAdminOut:
    return FasilitasAdminOut.model_validate(row, from_attributes=True)


def list_fasilitas(db: Session) -> list[FasilitasAdminOut]:
    rows = db.scalars(select(Fasilitas).order_by(Fasilitas.urutan, Fasilitas.id))
    return [_fasilitas_out(r) for r in rows]


def _get_fasilitas(db: Session, item_id: int) -> Fasilitas:
    row = db.get(Fasilitas, item_id)
    if row is None:
        raise not_found("Fasilitas tidak ditemukan.")
    return row


def create_fasilitas(db: Session, actor: User, data: FasilitasIn) -> FasilitasAdminOut:
    row = Fasilitas(
        nama=data.nama,
        deskripsi=data.deskripsi.strip(),
        gambar_url=data.gambar_url,
        urutan=data.urutan if data.urutan is not None else _next_order(db, Fasilitas),
        tampil=data.tampil,
    )
    db.add(row)
    _log(db, actor, f"menambahkan fasilitas \"{data.nama}\".")
    db.commit()
    return _fasilitas_out(row)


def update_fasilitas(db: Session, actor: User, item_id: int, data: FasilitasIn) -> FasilitasAdminOut:
    row = _get_fasilitas(db, item_id)
    row.nama = data.nama
    row.deskripsi = data.deskripsi.strip()
    row.gambar_url = data.gambar_url
    row.tampil = data.tampil
    if data.urutan is not None:
        row.urutan = data.urutan
    _log(db, actor, f"memperbarui fasilitas \"{data.nama}\".")
    db.commit()
    return _fasilitas_out(row)


def delete_fasilitas(db: Session, actor: User, item_id: int) -> None:
    row = _get_fasilitas(db, item_id)
    name = row.nama
    db.execute(delete(Fasilitas).where(Fasilitas.id == row.id))
    _log(db, actor, f"menghapus fasilitas \"{name}\".")
    db.commit()


# FAQ


def _faq_out(row: Faq) -> FaqAdminOut:
    return FaqAdminOut(
        id=row.id,
        kategori=row.kategori.value,
        pertanyaan=row.pertanyaan,
        jawaban=row.jawaban,
        urutan=row.urutan,
        tampil=row.tampil,
    )


def list_faq(db: Session) -> list[FaqAdminOut]:
    return [_faq_out(r) for r in db.scalars(select(Faq).order_by(Faq.urutan, Faq.id))]


def _get_faq(db: Session, item_id: int) -> Faq:
    row = db.get(Faq, item_id)
    if row is None:
        raise not_found("Pertanyaan tidak ditemukan.")
    return row


def create_faq(db: Session, actor: User, data: FaqIn) -> FaqAdminOut:
    row = Faq(
        kategori=FaqKategori(data.kategori),
        pertanyaan=data.pertanyaan,
        jawaban=data.jawaban,
        urutan=data.urutan if data.urutan is not None else _next_order(db, Faq),
        tampil=data.tampil,
    )
    db.add(row)
    _log(db, actor, f"menambahkan FAQ \"{data.pertanyaan}\".")
    db.commit()
    return _faq_out(row)


def update_faq(db: Session, actor: User, item_id: int, data: FaqIn) -> FaqAdminOut:
    row = _get_faq(db, item_id)
    row.kategori = FaqKategori(data.kategori)
    row.pertanyaan = data.pertanyaan
    row.jawaban = data.jawaban
    row.tampil = data.tampil
    if data.urutan is not None:
        row.urutan = data.urutan
    _log(db, actor, f"memperbarui FAQ \"{data.pertanyaan}\".")
    db.commit()
    return _faq_out(row)


def delete_faq(db: Session, actor: User, item_id: int) -> None:
    row = _get_faq(db, item_id)
    question = row.pertanyaan
    db.execute(delete(Faq).where(Faq.id == row.id))
    _log(db, actor, f"menghapus FAQ \"{question}\".")
    db.commit()
