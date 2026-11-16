from collections.abc import Callable
from datetime import datetime

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.database import get_db
from app.core.errors import forbidden, unauthorized
from app.core.security import decode_access_token
from app.models import Admin, Guru, OrangTua, User
from app.models.base import UserRole
from app.services.ml_service import FaceEmbedder

_bearer = HTTPBearer(auto_error=False)


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


def get_now(request: Request) -> datetime:
    return request.app.state.clock()


def get_embedder(request: Request) -> FaceEmbedder:
    return request.app.state.embedder


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings_dep),
) -> User:
    if credentials is None:
        raise unauthorized()
    try:
        claims = decode_access_token(credentials.credentials, settings.secret_key)
        user_id = int(claims["sub"])
        version = int(claims["ver"])
    except (jwt.PyJWTError, ValueError, KeyError):
        raise unauthorized() from None

    user = db.get(User, user_id)
    if user is None or not user.is_active or user.token_version != version:
        raise unauthorized()
    return user


def require_roles(*roles: UserRole) -> Callable[..., User]:
    def dependency(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise forbidden()
        return user

    return dependency


def get_current_guru(user: User = Depends(require_roles(UserRole.GURU))) -> Guru:
    if user.guru_profile is None:
        raise forbidden("Profil guru tidak ditemukan.")
    return user.guru_profile


def get_current_ortu(user: User = Depends(require_roles(UserRole.ORTU))) -> OrangTua:
    if user.ortu_profile is None:
        raise forbidden("Profil orang tua tidak ditemukan.")
    return user.ortu_profile


def get_current_admin(user: User = Depends(require_roles(UserRole.ADMIN))) -> Admin:
    if user.admin_profile is None:
        raise forbidden("Profil admin tidak ditemukan.")
    return user.admin_profile
