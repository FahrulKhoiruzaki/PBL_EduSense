from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models import Admin
from app.schemas.school_info import (
    InformasiKelasIn,
    InformasiKelasOut,
    KalenderIn,
    KalenderOut,
)
from app.services import school_info_service as service

router = APIRouter(
    prefix="/admin/cms", tags=["admin-cms"], dependencies=[Depends(get_current_admin)]
)


@router.get("/kelas", response_model=list[InformasiKelasOut])
def list_class_info(db: Session = Depends(get_db)):
    return service.list_class_info(db)


@router.post("/kelas", response_model=InformasiKelasOut, status_code=201)
def create_class_info(
    body: InformasiKelasIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.create_class_info(db, admin.user, body)


@router.put("/kelas/{item_id}", response_model=InformasiKelasOut)
def update_class_info(
    item_id: int,
    body: InformasiKelasIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return service.update_class_info(db, admin.user, item_id, body)


@router.delete("/kelas/{item_id}", status_code=204)
def delete_class_info(
    item_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    service.delete_class_info(db, admin.user, item_id)
    return Response(status_code=204)


@router.get("/kalender", response_model=list[KalenderOut])
def list_calendar(db: Session = Depends(get_db)):
    return service.list_calendar(db)


@router.post("/kalender", response_model=KalenderOut, status_code=201)
def create_event(
    body: KalenderIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.create_event(db, admin.user, body)


@router.put("/kalender/{item_id}", response_model=KalenderOut)
def update_event(
    item_id: int,
    body: KalenderIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return service.update_event(db, admin.user, item_id, body)


@router.delete("/kalender/{item_id}", status_code=204)
def delete_event(
    item_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    service.delete_event(db, admin.user, item_id)
    return Response(status_code=204)
