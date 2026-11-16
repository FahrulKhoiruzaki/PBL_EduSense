from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin, get_settings_dep
from app.core.config import Settings
from app.core.database import get_db
from app.models import Admin, Guru
from app.models.base import UserRole
from app.schemas.admin import (
    AccountOut,
    ActiveIn,
    CredentialsOut,
    GuruAdminOut,
    GuruCreateIn,
    KelasAdminOut,
    KelasCreateIn,
    LogOut,
    MapelIn,
    MeOut,
    MoveIn,
    PasswordIn,
    SettingsIn,
    SettingsOut,
    SiswaAdminOut,
    SiswaIn,
    StaffIn,
    WaliIn,
)
from app.services import admin_service, log_service

router = APIRouter(prefix="/admin", tags=["admin"])


def _no_content() -> Response:
    return Response(status_code=204)


# Akun saya


@router.get("/me", response_model=MeOut)
def me(admin: Admin = Depends(get_current_admin)) -> MeOut:
    return MeOut(id=admin.id, nama=admin.nama, email=admin.user.email)


@router.put("/me/password", status_code=204)
def change_my_password(
    body: PasswordIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.change_own_password(db, admin.user, body.old_password, body.new_password)
    return _no_content()


# Guru


@router.get("/guru", response_model=list[GuruAdminOut])
def list_guru(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return admin_service.list_guru(db)


@router.post("/guru", response_model=CredentialsOut, status_code=201)
def create_guru(
    body: GuruCreateIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return admin_service.create_staff(db, admin.user, UserRole.GURU, body.nama, body.email)


@router.put("/guru/{account_id}", status_code=204)
def update_guru(
    account_id: int, body: StaffIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.update_staff(db, admin.user, Guru, account_id, body.nama, body.email)
    return _no_content()


@router.post("/guru/{account_id}/reset-password", response_model=CredentialsOut)
def reset_guru_password(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return admin_service.reset_password(db, admin.user, "guru", account_id)


@router.put("/guru/{account_id}/active", status_code=204)
def set_guru_active(
    account_id: int, body: ActiveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.set_active(db, admin.user, "guru", account_id, body.aktif)
    return _no_content()


@router.delete("/guru/{account_id}", status_code=204)
def delete_guru(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.delete_account(db, admin.user, "guru", account_id)
    return _no_content()


# Admin


@router.get("/admins", response_model=list[AccountOut])
def list_admins(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return admin_service.list_admins(db)


@router.post("/admins", response_model=CredentialsOut, status_code=201)
def create_admin(
    body: StaffIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return admin_service.create_staff(db, admin.user, UserRole.ADMIN, body.nama, body.email)


@router.put("/admins/{account_id}", status_code=204)
def update_admin(
    account_id: int, body: StaffIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.update_staff(db, admin.user, Admin, account_id, body.nama, body.email)
    return _no_content()


@router.post("/admins/{account_id}/reset-password", response_model=CredentialsOut)
def reset_admin_password(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return admin_service.reset_password(db, admin.user, "admin", account_id)


@router.put("/admins/{account_id}/active", status_code=204)
def set_admin_active(
    account_id: int, body: ActiveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.set_active(db, admin.user, "admin", account_id, body.aktif)
    return _no_content()


@router.delete("/admins/{account_id}", status_code=204)
def delete_admin(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.delete_account(db, admin.user, "admin", account_id)
    return _no_content()


# Siswa dan akun orang tua


@router.get("/siswa", response_model=list[SiswaAdminOut])
def list_siswa(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return admin_service.list_siswa(db)


@router.post("/siswa", response_model=CredentialsOut, status_code=201)
def create_siswa(
    body: SiswaIn,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
):
    return admin_service.create_siswa(
        db, admin.user, body.nama, body.kelas, body.nama_orang_tua, settings.parent_email_domain
    )


@router.post("/siswa/move", status_code=204)
def move_students(
    body: MoveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.move_students(db, admin.user, body.siswa_ids, body.kelas_tujuan)
    return _no_content()


@router.put("/siswa/{account_id}", status_code=204)
def update_siswa(
    account_id: int, body: SiswaIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.update_siswa(db, admin.user, account_id, body.nama, body.kelas, body.nama_orang_tua)
    return _no_content()


@router.post("/siswa/{account_id}/reset-password", response_model=CredentialsOut)
def reset_siswa_password(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
):
    return admin_service.reset_password(db, admin.user, "siswa", account_id)


@router.put("/siswa/{account_id}/active", status_code=204)
def set_siswa_active(
    account_id: int, body: ActiveIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.set_active(db, admin.user, "siswa", account_id, body.aktif)
    return _no_content()


@router.delete("/siswa/{account_id}", status_code=204)
def delete_siswa(
    account_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.delete_account(db, admin.user, "siswa", account_id)
    return _no_content()


# Kelas


@router.get("/classes", response_model=list[KelasAdminOut])
def list_classes(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return admin_service.list_classes(db)


@router.post("/classes", status_code=201)
def create_class(
    body: KelasCreateIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> dict[str, str]:
    admin_service.create_class(db, admin.user, body.kode)
    return {"kode": body.kode}


@router.delete("/classes/{kode}", status_code=204)
def delete_class(
    kode: str, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.delete_class(db, admin.user, kode)
    return _no_content()


@router.put("/classes/{kode}/wali", status_code=204)
def set_wali(
    kode: str, body: WaliIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.set_wali(db, admin.user, kode, body.guru_id)
    return _no_content()


@router.post("/classes/{kode}/mapel", status_code=204)
def add_mapel(
    kode: str, body: MapelIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.add_mapel(db, admin.user, kode, body.guru_id)
    return _no_content()


@router.delete("/classes/{kode}/mapel/{guru_id}", status_code=204)
def remove_mapel(
    kode: str, guru_id: int, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.remove_mapel(db, admin.user, kode, guru_id)
    return _no_content()


# Pengaturan dan log


@router.get("/settings", response_model=SettingsOut)
def get_settings(_: Admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    return admin_service.get_settings(db)


@router.put("/settings", status_code=204)
def save_settings(
    body: SettingsIn, admin: Admin = Depends(get_current_admin), db: Session = Depends(get_db)
) -> Response:
    admin_service.save_settings(db, admin.user, body.tahun_ajaran, body.batas_jam_terlambat)
    return _no_content()


@router.get("/logs", response_model=list[LogOut])
def list_logs(
    limit: int = Query(default=100, ge=1, le=1000),
    _: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return [
        LogOut(waktu=row.created_at, jenis=row.tipe.value, pesan=row.pesan)
        for row in log_service.recent(db, limit)
    ]
