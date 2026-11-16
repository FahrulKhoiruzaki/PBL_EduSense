from dataclasses import dataclass
from datetime import date, datetime, time

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import Absensi, PengaturanSekolah
from app.models.base import MetodeInput, StatusAbsensi
from app.services.notification_service import notify_parents_of_attendance

PRESENT = (StatusAbsensi.HADIR, StatusAbsensi.TERLAMBAT)


@dataclass(frozen=True)
class Recorded:
    waktu: time
    status: StatusAbsensi


@dataclass(frozen=True)
class AlreadyPresent:
    waktu: time | None


def get_late_limit(db: Session) -> time | None:
    return db.scalar(select(PengaturanSekolah.batas_jam_terlambat))


def mark_present_by_face(
    db: Session,
    *,
    siswa_id: int,
    guru_id: int,
    now: datetime,
    late_limit: time | None,
) -> Recorded | AlreadyPresent:
    """Mencatat hadir lewat wajah, aman terhadap pemindaian ganda yang bersamaan.

    Status Izin/Sakit/Alpa pada hari yang sama ditimpa (siswa terbukti hadir); status Hadir atau
    Terlambat yang sudah ada tidak diubah.
    """
    clock = now.time().replace(microsecond=0)
    status = (
        StatusAbsensi.TERLAMBAT
        if late_limit is not None and clock > late_limit
        else StatusAbsensi.HADIR
    )
    today: date = now.date()

    values = {
        "waktu": clock,
        "status": status,
        "metode_input": MetodeInput.FACE_RECOGNITION,
        "dicatat_oleh": guru_id,
        "catatan": None,
    }
    stmt = (
        pg_insert(Absensi)
        .values(siswa_id=siswa_id, tanggal=today, **values)
        .on_conflict_do_update(
            index_elements=["siswa_id", "tanggal"],
            set_=values,
            where=Absensi.status.notin_(PRESENT),
        )
        .returning(Absensi.id)
    )
    if db.execute(stmt).first() is not None:
        notify_parents_of_attendance(db, [(siswa_id, status)])
        db.commit()
        return Recorded(waktu=clock, status=status)

    db.rollback()
    existing = db.scalar(
        select(Absensi.waktu).where(Absensi.siswa_id == siswa_id, Absensi.tanggal == today)
    )
    return AlreadyPresent(waktu=existing)
