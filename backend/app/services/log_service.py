from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import LogAktivitas, User
from app.models.base import LogTipe
from app.services.auth_service import display_name


def record(db: Session, actor: User | None, tipe: LogTipe, pesan: str) -> None:
    """Menambah baris log; penyimpanan ikut transaksi pemanggil agar log dan perubahannya sepaket."""
    db.add(LogAktivitas(user_id=actor.id if actor else None, tipe=tipe, pesan=pesan))


def actor_name(actor: User) -> str:
    return display_name(actor)


def recent(db: Session, limit: int) -> list[LogAktivitas]:
    return list(
        db.scalars(
            select(LogAktivitas)
            .order_by(LogAktivitas.created_at.desc(), LogAktivitas.id.desc())
            .limit(limit)
        )
    )
