from datetime import datetime

from fastapi import APIRouter, Depends, File, Request, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_guru, get_embedder, get_now, get_settings_dep
from app.api.guru_access import get_class, get_student, require_mapel, require_wali
from app.core.config import Settings
from app.core.database import get_db
from app.core.errors import AppError, conflict
from app.models import Guru, Siswa, WajahSiswa
from app.schemas.face import FaceEnrollOut, FaceScanOut, FaceStatusOut
from app.services import attendance_service
from app.services.face_service import find_best_match
from app.services.ml_service import FaceEmbedder, FaceError, InvalidImage, NoFaceDetected

router = APIRouter(prefix="/guru/classes", tags=["guru-face"])

IMAGE_ERROR = "Berkas harus berupa gambar JPEG, PNG, atau WebP yang valid."


def _read_upload(foto: UploadFile, request: Request, settings: Settings) -> bytes:
    declared = request.headers.get("content-length")
    # Toleransi kecil untuk pembungkus multipart.
    if declared and declared.isdigit() and int(declared) > settings.max_upload_bytes + 4096:
        raise AppError(413, "Ukuran foto terlalu besar.")

    data = foto.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise AppError(413, "Ukuran foto terlalu besar.")
    if not data:
        raise AppError(422, "Data yang dikirim tidak valid.", errors={"foto": IMAGE_ERROR})
    return data


def _embed(embedder: FaceEmbedder, data: bytes) -> list[float] | None:
    """Embedding wajah, atau None bila tidak ada wajah. Berkas bukan gambar -> 422."""
    try:
        return embedder.embed(data)
    except InvalidImage:
        raise AppError(422, "Data yang dikirim tidak valid.", errors={"foto": IMAGE_ERROR}) from None
    except NoFaceDetected:
        return None
    except FaceError:
        return None


def _photo_count(db: Session, siswa_id: int) -> int:
    return db.scalar(select(func.count()).select_from(WajahSiswa).where(WajahSiswa.siswa_id == siswa_id)) or 0


@router.post("/{kode}/attendance/face", response_model=FaceScanOut)
def scan_face(
    kode: str,
    request: Request,
    foto: UploadFile = File(...),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
    embedder: FaceEmbedder = Depends(get_embedder),
    now: datetime = Depends(get_now),
) -> FaceScanOut:
    """Mengenali wajah dan langsung mencatat hadir bila cocok.

    Hasil bisnis dikembalikan dengan status 200 dan field `hasil`, sehingga aplikasi dapat
    menampilkan layar yang sesuai tanpa menganggapnya galat jaringan.
    """
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    data = _read_upload(foto, request, settings)

    not_recognized = FaceScanOut(
        hasil="tidak_dikenali",
        kode="FaceNotRecognized",
        pesan="Wajah belum terdaftar. Minta wali kelas mendaftarkan wajah siswa.",
    )

    embedding = _embed(embedder, data)
    if embedding is None:
        return not_recognized

    match = find_best_match(
        db,
        embedding,
        model_version=embedder.model_version,
        threshold=settings.face_match_threshold,
    )
    if match is None:
        return not_recognized

    siswa = db.get(Siswa, match.siswa_id)
    if siswa is None:
        return not_recognized
    if siswa.kelas_id != kelas.id:
        # Identitas siswa kelas lain sengaja tidak dibuka.
        return FaceScanOut(
            hasil="kelas_lain",
            kode="FaceOtherClass",
            pesan="Siswa ini terdaftar di kelas lain.",
        )

    result = attendance_service.mark_present_by_face(
        db,
        siswa_id=siswa.id,
        guru_id=guru.id,
        now=now,
        late_limit=attendance_service.get_late_limit(db),
    )
    if isinstance(result, attendance_service.AlreadyPresent):
        return FaceScanOut(
            hasil="duplikat",
            kode="FaceDuplicate",
            pesan="Siswa sudah tercatat hadir hari ini.",
            siswa_id=siswa.id,
            nama=siswa.nama,
            kelas=kelas.nama_kelas,
            waktu=str(result.waktu) if result.waktu else None,
        )

    return FaceScanOut(
        hasil="cocok",
        siswa_id=siswa.id,
        nama=siswa.nama,
        kelas=kelas.nama_kelas,
        waktu=str(result.waktu),
        status=result.status.value,
    )


@router.post("/{kode}/students/{siswa_id}/face", response_model=FaceEnrollOut, status_code=201)
def enroll_face(
    kode: str,
    siswa_id: int,
    request: Request,
    foto: UploadFile = File(...),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
    embedder: FaceEmbedder = Depends(get_embedder),
) -> FaceEnrollOut:
    kelas = get_class(db, kode)
    require_wali(guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    data = _read_upload(foto, request, settings)

    embedding = _embed(embedder, data)
    if embedding is None:
        raise AppError(
            422,
            "Wajah tidak terdeteksi pada foto. Pastikan wajah terlihat jelas.",
            errors={"foto": "Wajah tidak terdeteksi."},
        )

    if _photo_count(db, siswa.id) >= settings.face_max_photos_per_student:
        raise conflict(
            f"Foto wajah siswa sudah mencapai batas {settings.face_max_photos_per_student}. "
            "Hapus pendaftaran wajah yang lama terlebih dahulu.",
            code="FaceLimitReached",
        )

    other = find_best_match(
        db,
        embedding,
        model_version=embedder.model_version,
        threshold=settings.face_match_threshold,
    )
    if other is not None and other.siswa_id != siswa.id:
        raise conflict(
            "Wajah ini sudah terdaftar atas nama siswa lain.", code="FaceAlreadyEnrolled"
        )

    db.add(
        WajahSiswa(
            siswa_id=siswa.id,
            embedding=embedding,
            model_version=embedder.model_version,
            didaftarkan_oleh=guru.id,
        )
    )
    db.commit()
    return FaceEnrollOut(
        siswa_id=siswa.id,
        jumlah_foto=_photo_count(db, siswa.id),
        model_version=embedder.model_version,
    )


@router.get("/{kode}/students/{siswa_id}/face", response_model=FaceStatusOut)
def face_status(
    kode: str,
    siswa_id: int,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
) -> FaceStatusOut:
    kelas = get_class(db, kode)
    require_wali(guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    return FaceStatusOut(
        siswa_id=siswa.id,
        jumlah_foto=_photo_count(db, siswa.id),
        maksimum=settings.face_max_photos_per_student,
    )


@router.delete("/{kode}/students/{siswa_id}/face", status_code=204)
def reset_face(
    kode: str,
    siswa_id: int,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> None:
    kelas = get_class(db, kode)
    require_wali(guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    for row in db.scalars(select(WajahSiswa).where(WajahSiswa.siswa_id == siswa.id)):
        db.delete(row)
    db.commit()
