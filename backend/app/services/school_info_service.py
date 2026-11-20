"""Informasi per kelas dan kalender akademik: satu modul, dua daftar yang dikelola admin."""

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.errors import not_found
from app.models import InformasiKelas, KalenderAkademik, User
from app.models.base import LogTipe
from app.schemas.school_info import InformasiKelasIn, InformasiKelasOut, KalenderIn, KalenderOut
from app.services import log_service


def _log(db: Session, actor: User, message: str) -> None:
    log_service.record(db, actor, LogTipe.SISTEM, f"{log_service.actor_name(actor)} {message}")


# Informasi kelas


def _next_order(db: Session, tingkat: int, jenis: str) -> int:
    top = db.scalar(
        select(func.max(InformasiKelas.urutan)).where(
            InformasiKelas.tingkat == tingkat, InformasiKelas.jenis == jenis
        )
    )
    return (top or 0) + 1


def list_class_info(db: Session, *, only_visible: bool = False, tingkat: int | None = None):
    query = select(InformasiKelas).order_by(
        InformasiKelas.tingkat, InformasiKelas.jenis, InformasiKelas.urutan, InformasiKelas.id
    )
    if only_visible:
        query = query.where(InformasiKelas.tampil.is_(True))
    if tingkat is not None:
        query = query.where(InformasiKelas.tingkat == tingkat)
    return list(db.scalars(query))


def _get_class_info(db: Session, item_id: int) -> InformasiKelas:
    row = db.get(InformasiKelas, item_id)
    if row is None:
        raise not_found("Informasi kelas tidak ditemukan.")
    return row


def create_class_info(db: Session, actor: User, data: InformasiKelasIn) -> InformasiKelasOut:
    row = InformasiKelas(
        tingkat=data.tingkat,
        jenis=data.jenis,
        judul=data.judul,
        deskripsi=data.deskripsi.strip(),
        urutan=data.urutan if data.urutan is not None else _next_order(db, data.tingkat, data.jenis),
        tampil=data.tampil,
    )
    db.add(row)
    _log(db, actor, f"menambahkan informasi kelas {data.tingkat} \"{data.judul}\".")
    db.commit()
    return InformasiKelasOut.model_validate(row, from_attributes=True)


def update_class_info(
    db: Session, actor: User, item_id: int, data: InformasiKelasIn
) -> InformasiKelasOut:
    row = _get_class_info(db, item_id)
    moved = (row.tingkat, row.jenis) != (data.tingkat, data.jenis)
    row.tingkat = data.tingkat
    row.jenis = data.jenis
    row.judul = data.judul
    row.deskripsi = data.deskripsi.strip()
    row.tampil = data.tampil
    if data.urutan is not None:
        row.urutan = data.urutan
    elif moved:
        # Pindah kelas/jenis: taruh di akhir daftar tujuan, bukan di urutan lama yang tak relevan.
        row.urutan = _next_order(db, data.tingkat, data.jenis)
    _log(db, actor, f"memperbarui informasi kelas {data.tingkat} \"{data.judul}\".")
    db.commit()
    return InformasiKelasOut.model_validate(row, from_attributes=True)


def delete_class_info(db: Session, actor: User, item_id: int) -> None:
    row = _get_class_info(db, item_id)
    label = f"kelas {row.tingkat} \"{row.judul}\""
    db.execute(delete(InformasiKelas).where(InformasiKelas.id == row.id))
    _log(db, actor, f"menghapus informasi {label}.")
    db.commit()


# Kalender akademik


def list_calendar(db: Session, *, only_visible: bool = False):
    query = select(KalenderAkademik).order_by(KalenderAkademik.tanggal_mulai, KalenderAkademik.id)
    if only_visible:
        query = query.where(KalenderAkademik.tampil.is_(True))
    return list(db.scalars(query))


def _get_event(db: Session, item_id: int) -> KalenderAkademik:
    row = db.get(KalenderAkademik, item_id)
    if row is None:
        raise not_found("Kegiatan kalender tidak ditemukan.")
    return row


def _apply_event(row: KalenderAkademik, data: KalenderIn) -> None:
    row.judul = data.judul
    row.deskripsi = data.deskripsi.strip()
    row.kategori = data.kategori
    row.tanggal_mulai = data.tanggal_mulai
    # Kegiatan satu hari disimpan tanpa tanggal selesai.
    row.tanggal_selesai = (
        None if data.tanggal_selesai == data.tanggal_mulai else data.tanggal_selesai
    )
    row.tampil = data.tampil


def create_event(db: Session, actor: User, data: KalenderIn) -> KalenderOut:
    row = KalenderAkademik()
    _apply_event(row, data)
    db.add(row)
    _log(db, actor, f"menambahkan kalender akademik \"{data.judul}\".")
    db.commit()
    return KalenderOut.model_validate(row, from_attributes=True)


def update_event(db: Session, actor: User, item_id: int, data: KalenderIn) -> KalenderOut:
    row = _get_event(db, item_id)
    _apply_event(row, data)
    _log(db, actor, f"memperbarui kalender akademik \"{data.judul}\".")
    db.commit()
    return KalenderOut.model_validate(row, from_attributes=True)


def delete_event(db: Session, actor: User, item_id: int) -> None:
    row = _get_event(db, item_id)
    title = row.judul
    db.execute(delete(KalenderAkademik).where(KalenderAkademik.id == row.id))
    _log(db, actor, f"menghapus kalender akademik \"{title}\".")
    db.commit()
