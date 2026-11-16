from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, File, Request, Response, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin, get_now, get_settings_dep
from app.core.config import Settings
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Admin
from app.schemas.cms import (
    FaqAdminOut,
    FaqIn,
    FasilitasAdminOut,
    FasilitasIn,
    KegiatanAdminOut,
    KegiatanIn,
    MediaOut,
    PageOut,
    PagesIn,
    PostDetailOut,
    PostIn,
    PostOut,
    SchoolIn,
    SchoolOut,
    SchoolPhotoOut,
)
from app.services import cms_service, media_service

router = APIRouter(
    prefix="/admin/cms", tags=["admin-cms"], dependencies=[Depends(get_current_admin)]
)

IMAGE_ERROR = "Berkas harus berupa gambar JPEG, PNG, atau WebP yang valid."


def _no_content() -> Response:
    return Response(status_code=204)


# Teks halaman


@router.get("/pages", response_model=list[PageOut])
def list_pages(db: Session = Depends(get_db)):
    return cms_service.list_pages(db)


@router.put("/pages", response_model=list[PageOut])
def save_pages(body: PagesIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    cms_service.save_pages(db, admin.user, body.halaman)
    return cms_service.list_pages(db)


# Profil dan kontak sekolah


@router.get("/school", response_model=SchoolOut)
def get_school(db: Session = Depends(get_db)):
    return cms_service.get_school(db)


@router.put("/school", response_model=SchoolOut)
def save_school(body: SchoolIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return cms_service.save_school(db, admin.user, body)


# Berita dan pengumuman


@router.get("/posts", response_model=list[PostOut])
def list_posts(db: Session = Depends(get_db)):
    return cms_service.list_posts(db)


@router.get("/posts/{slug}", response_model=PostDetailOut)
def get_post(slug: str, db: Session = Depends(get_db)):
    return cms_service.get_post(db, slug)


@router.post("/posts", response_model=PostDetailOut, status_code=201)
def create_post(
    body: PostIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
):
    return cms_service.create_post(db, admin.user, body, now.date())


@router.put("/posts/{slug}", response_model=PostDetailOut)
def update_post(
    slug: str,
    body: PostIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
):
    return cms_service.update_post(db, admin.user, slug, body, now.date())


@router.delete("/posts/{slug}", status_code=204)
def delete_post(slug: str, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    cms_service.delete_post(db, admin.user, slug)
    return _no_content()


# Kegiatan


@router.get("/kegiatan", response_model=list[KegiatanAdminOut])
def list_kegiatan(db: Session = Depends(get_db)):
    return cms_service.list_kegiatan(db)


@router.post("/kegiatan", response_model=KegiatanAdminOut, status_code=201)
def create_kegiatan(
    body: KegiatanIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
):
    return cms_service.create_kegiatan(db, admin.user, body, now.date())


@router.put("/kegiatan/{slug}", response_model=KegiatanAdminOut)
def update_kegiatan(
    slug: str,
    body: KegiatanIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
):
    return cms_service.update_kegiatan(db, admin.user, slug, body, now.date())


@router.delete("/kegiatan/{slug}", status_code=204)
def delete_kegiatan(slug: str, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    cms_service.delete_kegiatan(db, admin.user, slug)
    return _no_content()


# Fasilitas


@router.get("/fasilitas", response_model=list[FasilitasAdminOut])
def list_fasilitas(db: Session = Depends(get_db)):
    return cms_service.list_fasilitas(db)


@router.post("/fasilitas", response_model=FasilitasAdminOut, status_code=201)
def create_fasilitas(
    body: FasilitasIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return cms_service.create_fasilitas(db, admin.user, body)


@router.put("/fasilitas/{item_id}", response_model=FasilitasAdminOut)
def update_fasilitas(
    item_id: int,
    body: FasilitasIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return cms_service.update_fasilitas(db, admin.user, item_id, body)


@router.delete("/fasilitas/{item_id}", status_code=204)
def delete_fasilitas(item_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    cms_service.delete_fasilitas(db, admin.user, item_id)
    return _no_content()


# FAQ


@router.get("/faq", response_model=list[FaqAdminOut])
def list_faq(db: Session = Depends(get_db)):
    return cms_service.list_faq(db)


@router.post("/faq", response_model=FaqAdminOut, status_code=201)
def create_faq(body: FaqIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return cms_service.create_faq(db, admin.user, body)


@router.put("/faq/{item_id}", response_model=FaqAdminOut)
def update_faq(
    item_id: int, body: FaqIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return cms_service.update_faq(db, admin.user, item_id, body)


@router.delete("/faq/{item_id}", status_code=204)
def delete_faq(item_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    cms_service.delete_faq(db, admin.user, item_id)
    return _no_content()


# Unggah gambar


def _read_image(request: Request, file: UploadFile, settings: Settings) -> bytes:
    declared = request.headers.get("content-length")
    # Toleransi kecil untuk pembungkus multipart.
    if declared and declared.isdigit() and int(declared) > settings.max_media_bytes + 4096:
        raise AppError(413, "Ukuran gambar terlalu besar.")
    data = file.file.read(settings.max_media_bytes + 1)
    if len(data) > settings.max_media_bytes:
        raise AppError(413, "Ukuran gambar terlalu besar.")
    return data


@router.post("/media", response_model=MediaOut, status_code=201)
def upload_media(
    request: Request,
    file: UploadFile = File(...),
    settings: Settings = Depends(get_settings_dep),
):
    data = _read_image(request, file, settings)
    url = media_service.save_media(Path(settings.media_dir), data) if data else None
    if url is None:
        raise AppError(422, "Data yang dikirim tidak valid.", errors={"file": IMAGE_ERROR})
    return MediaOut(url=url, ukuran=len(data))


@router.post("/school/photo", response_model=SchoolPhotoOut, status_code=201)
def replace_school_photo(
    request: Request,
    file: UploadFile = File(...),
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
):
    """Mengganti foto beranda. Foto lama baru dihapus setelah yang baru tersimpan; bila gagal, foto lama tetap."""
    media_dir = Path(settings.media_dir)
    data = _read_image(request, file, settings)
    url = media_service.save_media(media_dir, data) if data else None
    if url is None:
        raise AppError(422, "Data yang dikirim tidak valid.", errors={"file": IMAGE_ERROR})
    try:
        previous = cms_service.replace_school_photo(db, admin.user, url)
    except Exception:
        db.rollback()
        media_service.delete_media(media_dir, url)
        raise
    media_service.delete_media(media_dir, previous)
    return SchoolPhotoOut(foto_url=url, ukuran=len(data))
