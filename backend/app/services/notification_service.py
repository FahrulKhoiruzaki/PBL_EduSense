from datetime import date, datetime

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.models import Guru, Notifikasi, OrangTua, Siswa, User
from app.models.base import KategoriNilai, StatusAbsensi
from app.schemas.guru import NotifikasiOut
from app.services.stats import STATUS_LABEL


def notify(
    db: Session,
    user_ids: list[int],
    judul: str,
    *,
    target: str | None = None,
    target_id: int | None = None,
) -> None:
    for user_id in dict.fromkeys(user_ids):
        db.add(Notifikasi(user_id=user_id, judul=judul, target=target, target_id=target_id))


def wali_user_ids(db: Session, wali_kelas_id: int | None, *, exclude_user_id: int) -> list[int]:
    """User id wali kelas, kecuali pelaku sendiri (tidak perlu diberi tahu soal aksinya sendiri)."""
    if wali_kelas_id is None:
        return []
    user_id = db.scalar(select(Guru.user_id).where(Guru.id == wali_kelas_id))
    return [user_id] if user_id is not None and user_id != exclude_user_id else []


def _first_name(full_name: str) -> str:
    return full_name.split()[0] if full_name.split() else full_name


def notify_parents_of_attendance(db: Session, entries: list[tuple[int, StatusAbsensi]]) -> None:
    """Satu notifikasi per siswa ke akun orang tuanya; `entries` = (siswa_id, status)."""
    if not entries:
        return
    status_by_student = dict(entries)
    rows = db.execute(
        select(Siswa.id, Siswa.nama, OrangTua.user_id)
        .join(OrangTua, OrangTua.id == Siswa.orang_tua_id)
        .where(Siswa.id.in_(status_by_student))
    ).all()
    for siswa_id, nama, user_id in rows:
        label = STATUS_LABEL[status_by_student[siswa_id]]
        db.add(
            Notifikasi(
                user_id=user_id,
                judul=f"Kehadiran {_first_name(nama)} hari ini tercatat: {label}.",
                target="kehadiran",
            )
        )


def notify_parent_of_grade(
    db: Session, siswa: Siswa, subject: KategoriNilai | str, nilai_id: int
) -> None:
    """`subject`: nama mata pelajaran (nilai berbasis komponen) atau kategori (perilaku lama)."""
    label = subject.value if isinstance(subject, KategoriNilai) else subject
    user_id = db.scalar(select(OrangTua.user_id).where(OrangTua.id == siswa.orang_tua_id))
    if user_id is None:
        return
    db.add(
        Notifikasi(
            user_id=user_id,
            judul=f"Nilai {label} baru untuk {_first_name(siswa.nama)}.",
            target="nilai",
            target_id=nilai_id,
        )
    )


def list_notifications(
    db: Session, user: User, *, now: datetime, limit: int = 50
) -> list[NotifikasiOut]:
    rows = db.scalars(
        select(Notifikasi)
        .where(Notifikasi.user_id == user.id)
        .order_by(Notifikasi.created_at.desc(), Notifikasi.id.desc())
        .limit(limit)
    ).all()
    today: date = now.date()
    return [
        NotifikasiOut(
            id=n.id,
            judul=n.judul,
            target=n.target,
            target_id=n.target_id,
            dibaca=n.dibaca,
            kelompok="hari_ini" if n.created_at.astimezone(now.tzinfo).date() == today else "sebelumnya",
            created_at=n.created_at,
        )
        for n in rows
    ]


def mark_read(db: Session, user: User, notification_id: int) -> bool:
    result = db.execute(
        update(Notifikasi)
        .where(Notifikasi.id == notification_id, Notifikasi.user_id == user.id)
        .values(dibaca=True)
    )
    db.commit()
    return result.rowcount > 0


def mark_all_read(db: Session, user: User) -> None:
    db.execute(
        update(Notifikasi)
        .where(Notifikasi.user_id == user.id, Notifikasi.dibaca.is_(False))
        .values(dibaca=True)
    )
    db.commit()
