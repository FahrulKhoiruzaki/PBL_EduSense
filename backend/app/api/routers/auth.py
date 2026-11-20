import logging

from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_settings_dep
from app.core.config import Settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import create_access_token
from app.models import User
from app.models.base import UserRole
from app.schemas.auth import (
    ChangePasswordIn,
    ForgotPasswordIn,
    GuruOut,
    LoginIn,
    LoginOut,
    PengaturanOut,
    SessionOut,
    UserOut,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)


def _session(db: Session, user: User) -> SessionOut:
    guru = None
    if user.role is UserRole.GURU and user.guru_profile is not None:
        wali, mapel = auth_service.guru_assignments(db, user.guru_profile)
        guru = GuruOut(nip=user.guru_profile.nip, wali_kelas=wali, mapel=mapel)

    return SessionOut(
        user=UserOut(
            id=user.id,
            email=user.email,
            nama=auth_service.display_name(user),
            role=user.role.value,
            must_change_password=user.must_change_password,
        ),
        guru=guru,
        pengaturan=PengaturanOut(batas_jam_terlambat=auth_service.late_limit_text(db)),
    )


@router.post("/login", response_model=LoginOut)
def login(
    body: LoginIn,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
) -> LoginOut:
    user = auth_service.authenticate(db, body.email, body.password)
    token = create_access_token(
        user_id=user.id,
        role=user.role.value,
        version=user.token_version,
        secret=settings.secret_key,
        minutes=settings.access_token_minutes,
    )
    return LoginOut(token=token, **_session(db, user).model_dump())


@router.get("/me", response_model=SessionOut)
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> SessionOut:
    return _session(db, user)


@router.put("/password", status_code=204)
def set_password(
    body: ChangePasswordIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    # Tanpa password lama, hanya boleh untuk mengganti password sementara dari admin.
    if not user.must_change_password:
        raise AppError(
            403,
            "Password hanya dapat diganti tanpa password lama saat masih memakai password sementara.",
        )
    auth_service.change_password(db, user, body.new_password)
    return Response(status_code=204)


@router.post("/logout", status_code=204)
def logout(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> Response:
    auth_service.revoke_tokens(db, user)
    return Response(status_code=204)


@router.post("/forgot-password", status_code=202)
def forgot_password(body: ForgotPasswordIn, db: Session = Depends(get_db)) -> dict[str, str]:
    # Jawaban selalu sama agar daftar akun tidak bisa ditebak. Pengiriman email belum tersedia.
    user = auth_service.find_user_by_email(db, body.email)
    if user is not None and user.is_active:
        logger.info("Permintaan reset password untuk user id=%s (email belum terhubung)", user.id)
    return {"message": "Jika email terdaftar, tautan pemulihan akan dikirim."}
