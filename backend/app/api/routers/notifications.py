from datetime import datetime

from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.api.deps import get_now, require_roles
from app.core.database import get_db
from app.core.errors import not_found
from app.models import User
from app.models.base import UserRole
from app.schemas.guru import NotifikasiOut
from app.services import notification_service


def notification_router(role: UserRole) -> APIRouter:
    """Notifikasi milik pengguna yang login; bentuk dan aturannya sama untuk guru dan orang tua."""
    router = APIRouter(prefix="/notifications")
    current_user = require_roles(role)

    @router.get("", response_model=list[NotifikasiOut])
    def list_notifications(
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
        now: datetime = Depends(get_now),
    ) -> list[NotifikasiOut]:
        return notification_service.list_notifications(db, user, now=now)

    @router.post("/read-all", status_code=204)
    def read_all(user: User = Depends(current_user), db: Session = Depends(get_db)) -> Response:
        notification_service.mark_all_read(db, user)
        return Response(status_code=204)

    @router.post("/{notification_id}/read", status_code=204)
    def read_one(
        notification_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
    ) -> Response:
        if not notification_service.mark_read(db, user, notification_id):
            raise not_found("Notifikasi tidak ditemukan.")
        return Response(status_code=204)

    return router
