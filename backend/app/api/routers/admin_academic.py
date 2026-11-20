"""Endpoint admin untuk data akademik: periode, mata pelajaran, komponen nilai, klasifikasi."""

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.api.guru_access import get_class
from app.core.database import get_db
from app.models import Admin
from app.schemas.academic import (
    AturanIn,
    AturanOut,
    CopyOut,
    KlasifikasiRingkasanOut,
    KomponenCopyIn,
    KomponenIn,
    KomponenOut,
    MapelIn,
    MapelOut,
    PeriodeAdminOut,
    PeriodeIn,
    RecomputeOut,
)
from app.schemas.admin import ActiveIn
from app.services import academic_admin_service as service
from app.services import grading_service, periods

router = APIRouter(prefix="/admin/academic", tags=["admin-akademik"])


def _no_content() -> Response:
    return Response(status_code=204)


# Periode


@router.get("/periods", response_model=list[PeriodeAdminOut])
def list_periods(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.list_periods(db)


@router.post("/periods", response_model=PeriodeAdminOut, status_code=201)
def create_period(body: PeriodeIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.create_period(db, admin.user, body)


@router.put("/periods/{periode_id}", response_model=PeriodeAdminOut)
def update_period(
    periode_id: int, body: PeriodeIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.update_period(db, admin.user, periode_id, body)


@router.post("/periods/{periode_id}/activate", response_model=PeriodeAdminOut)
def activate_period(periode_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.activate_period(db, admin.user, periode_id)


@router.delete("/periods/{periode_id}", status_code=204)
def delete_period(periode_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    service.delete_period(db, admin.user, periode_id)
    return _no_content()


@router.get("/periods/{periode_id}/rule", response_model=AturanOut | None)
def get_rule(periode_id: int, _: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.get_rule(db, periode_id)


@router.put("/periods/{periode_id}/rule", response_model=AturanOut)
def save_rule(
    periode_id: int, body: AturanIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.save_rule(db, admin.user, periode_id, body)


@router.post("/periods/{periode_id}/recompute", response_model=RecomputeOut)
def recompute(periode_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.recompute_period(db, admin.user, periode_id)


# Mata pelajaran


@router.get("/subjects", response_model=list[MapelOut])
def list_subjects(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.list_subjects(db)


@router.post("/subjects", response_model=MapelOut, status_code=201)
def create_subject(body: MapelIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.create_subject(db, admin.user, body)


@router.put("/subjects/{mapel_id}", response_model=MapelOut)
def update_subject(
    mapel_id: int, body: MapelIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.update_subject(db, admin.user, mapel_id, body)


@router.put("/subjects/{mapel_id}/active", status_code=204)
def set_subject_active(
    mapel_id: int, body: ActiveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    service.set_subject_active(db, admin.user, mapel_id, body.aktif)
    return _no_content()


@router.delete("/subjects/{mapel_id}", status_code=204)
def delete_subject(mapel_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    service.delete_subject(db, admin.user, mapel_id)
    return _no_content()


# Komponen penilaian


@router.get("/components", response_model=list[KomponenOut])
def list_components(
    periode_id: int | None = Query(default=None),
    mapel_id: int | None = Query(default=None),
    _: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return service.list_components(db, periode_id, mapel_id)


@router.post("/components", response_model=KomponenOut, status_code=201)
def create_component(body: KomponenIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return service.create_component(db, admin.user, body)


@router.post("/components/copy", response_model=CopyOut)
def copy_components(
    body: KomponenCopyIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.copy_components(db, admin.user, body.dari_periode_id, body.ke_periode_id)


@router.put("/components/{komponen_id}", response_model=KomponenOut)
def update_component(
    komponen_id: int, body: KomponenIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return service.update_component(db, admin.user, komponen_id, body)


@router.put("/components/{komponen_id}/active", status_code=204)
def set_component_active(
    komponen_id: int, body: ActiveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    service.set_component_active(db, admin.user, komponen_id, body.aktif)
    return _no_content()


@router.delete("/components/{komponen_id}", status_code=204)
def delete_component(komponen_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    service.delete_component(db, admin.user, komponen_id)
    return _no_content()


# Ringkasan klasifikasi (chart dashboard admin)


@router.get("/classification", response_model=KlasifikasiRingkasanOut)
def classification_summary(
    periode_id: int | None = Query(default=None),
    kelas: str | None = Query(default=None, max_length=10),
    _: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    periode = periods.resolve_period(db, periode_id)
    classes = [get_class(db, kelas)] if kelas else None
    return grading_service.summary(db, periode, classes)
