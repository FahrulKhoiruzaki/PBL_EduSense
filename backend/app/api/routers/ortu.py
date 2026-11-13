from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_ortu, get_now
from app.api.routers.notifications import notification_router
from app.core.database import get_db
from app.models import OrangTua
from app.models.base import UserRole
from app.schemas.parent import AnakOut, KehadiranHariOut, RiwayatItemOut
from app.services import parent_service

router = APIRouter(prefix="/ortu", tags=["ortu"])
router.include_router(notification_router(UserRole.ORTU))


@router.get("/children", response_model=list[AnakOut])
def list_children(
    ortu: OrangTua = Depends(get_current_ortu),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[AnakOut]:
    return [
        parent_service.child_overview(db, siswa, today=now.date(), tz=now.tzinfo)
        for siswa in parent_service.get_children(db, ortu)
    ]


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
) -> list[RiwayatItemOut]:
    return parent_service.history(db, parent_service.get_child(db, ortu, siswa_id))
