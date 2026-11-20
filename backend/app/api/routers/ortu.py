from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_ortu, get_now
from app.api.routers.notifications import notification_router
from app.core.database import get_db
from app.models import OrangTua
from app.models.base import UserRole
from app.schemas.academic import PeriodeOut, RaporOut
from app.schemas.parent import AnakOut, KehadiranHariOut, RiwayatItemOut
from app.services import grading_service, parent_service, periods

router = APIRouter(prefix="/ortu", tags=["ortu"])
router.include_router(notification_router(UserRole.ORTU))


@router.get("/children", response_model=list[AnakOut])
def list_children(
    periode_id: int | None = Query(default=None),
    ortu: OrangTua = Depends(get_current_ortu),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[AnakOut]:
    """`periode_id` kosong = periode aktif."""
    periode = periods.get_period(db, periode_id) if periode_id is not None else None
    return [
        parent_service.child_overview(db, siswa, today=now.date(), tz=now.tzinfo, periode=periode)
        for siswa in parent_service.get_children(db, ortu)
    ]


@router.get("/periods", response_model=list[PeriodeOut])
def list_periods(
    _: OrangTua = Depends(get_current_ortu), db: Session = Depends(get_db)
) -> list[PeriodeOut]:
    """Semua periode akademik, terbaru dulu (untuk filter tahun ajaran dan semester)."""
    return [periods.period_out(p) for p in periods.ordered_periods(db)]


@router.get("/children/{siswa_id}/report", response_model=RaporOut)
def child_report(
    siswa_id: int,
    periode_id: int | None = Query(default=None),
    ortu: OrangTua = Depends(get_current_ortu),
    db: Session = Depends(get_db),
) -> RaporOut:
    """Rapor akademik anak: semua mapel, komponen, status kelengkapan, riwayat per periode."""
    siswa = parent_service.get_child(db, ortu, siswa_id)
    return grading_service.student_report(db, siswa, periods.resolve_period(db, periode_id))


@router.get("/children/{siswa_id}/attendance", response_model=list[KehadiranHariOut])
def child_attendance(
    siswa_id: int,
    ortu: OrangTua = Depends(get_current_ortu),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[KehadiranHariOut]:
    siswa = parent_service.get_child(db, ortu, siswa_id)
    return parent_service.attendance_days(db, siswa, today=now.date())


@router.get("/children/{siswa_id}/history", response_model=list[RiwayatItemOut])
def child_history(
    siswa_id: int,
    ortu: OrangTua = Depends(get_current_ortu),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[RiwayatItemOut]:
    return parent_service.history(db, parent_service.get_child(db, ortu, siswa_id), now.date())
