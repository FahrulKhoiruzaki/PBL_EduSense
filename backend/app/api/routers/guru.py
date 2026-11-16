from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_guru, get_now
from app.api.guru_access import (
    accessible_classes,
    get_class,
    get_student,
    require_mapel,
    require_read,
)
from app.api.routers.notifications import notification_router
from app.core.database import get_db
from app.core.errors import not_found
from app.models import Guru, Nilai, Siswa
from app.models.base import UserRole
from app.schemas.guru import (
    AbsensiManualIn,
    AktivitasOut,
    FinishOut,
    KelasDetailOut,
    KelasRingkasOut,
    NilaiCreatedOut,
    NilaiIn,
)
from app.services import guru_service, notification_service

router = APIRouter(prefix="/guru", tags=["guru"])
router.include_router(notification_router(UserRole.GURU))


@router.get("/classes", response_model=list[KelasRingkasOut])
def list_classes(
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[KelasRingkasOut]:
    return guru_service.class_summaries(db, accessible_classes(db, guru), now.date())


@router.get("/classes/{kode}", response_model=KelasDetailOut)
def class_detail(
    kode: str,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> KelasDetailOut:
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    return guru_service.class_detail(db, kelas, now.date())


@router.put("/classes/{kode}/attendance/{siswa_id}", status_code=204)
def set_attendance(
    kode: str,
    siswa_id: int,
    body: AbsensiManualIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> Response:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    guru_service.set_manual_attendance(
        db, siswa=siswa, guru=guru, status=body.status, catatan=body.catatan, now=now
    )
    return Response(status_code=204)


@router.post("/classes/{kode}/attendance/finish", response_model=FinishOut)
def finish_attendance(
    kode: str,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> FinishOut:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    return FinishOut(jumlah_alpa=guru_service.finish_attendance(db, kelas, guru, now.date()))


@router.post("/classes/{kode}/grades", response_model=NilaiCreatedOut, status_code=201)
def create_grade(
    kode: str,
    body: NilaiIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> NilaiCreatedOut:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    siswa = get_student(db, kelas, body.siswa_id)

    nilai = Nilai(
        siswa_id=siswa.id,
        kategori=body.kategori,
        jenis_ujian=body.jenis_ujian.strip(),
        nilai=Decimal(str(round(body.nilai, 2))),
        tanggal=body.tanggal,
        catatan_guru=(body.catatan_guru or "").strip() or None,
        dicatat_oleh=guru.id,
    )
    db.add(nilai)
    db.flush()
    notification_service.notify(
        db,
        notification_service.wali_user_ids(db, kelas.wali_kelas_id, exclude_user_id=guru.user_id),
        "Nilai baru ditambahkan.",
        target="nilai",
        target_id=nilai.id,
    )
    notification_service.notify_parent_of_grade(db, siswa, body.kategori, nilai.id)
    db.commit()
    return NilaiCreatedOut(id=nilai.id)


def _grade_for_update(db: Session, guru: Guru, grade_id: int):
    nilai = db.get(Nilai, grade_id)
    siswa = db.get(Siswa, nilai.siswa_id) if nilai else None
    if nilai is None or siswa is None:
        raise not_found("Nilai tidak ditemukan.")
    kelas = siswa.kelas
    require_mapel(db, guru, kelas)
    return nilai, kelas


@router.put("/grades/{grade_id}", status_code=204)
def update_grade(
    grade_id: int,
    body: NilaiIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> Response:
    nilai, kelas = _grade_for_update(db, guru, grade_id)
    siswa = get_student(db, kelas, body.siswa_id)

    nilai.siswa_id = siswa.id
    nilai.kategori = body.kategori
    nilai.jenis_ujian = body.jenis_ujian.strip()
    nilai.nilai = Decimal(str(round(body.nilai, 2)))
    nilai.tanggal = body.tanggal
    nilai.catatan_guru = (body.catatan_guru or "").strip() or None
    db.commit()
    return Response(status_code=204)


@router.delete("/grades/{grade_id}", status_code=204)
def delete_grade(
    grade_id: int,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> Response:
    nilai, _ = _grade_for_update(db, guru, grade_id)
    db.delete(nilai)
    db.commit()
    return Response(status_code=204)


@router.get("/activities", response_model=list[AktivitasOut])
def list_activities(
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[AktivitasOut]:
    return guru_service.recent_activities(db, accessible_classes(db, guru), now=now)
