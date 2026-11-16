from datetime import date, datetime, timedelta

from sqlalchemy import and_, case, exists, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import Absensi, Guru, Kelas, Nilai, Siswa
from app.models.base import KategoriNilai, MetodeInput, StatusAbsensi
from app.schemas.guru import (
    AktivitasOut,
    KelasDetailOut,
    KelasRingkasOut,
    NilaiOut,
    SiswaKelasOut,
    TrenOut,
)
from app.services.notification_service import notify, notify_parents_of_attendance, wali_user_ids
from app.services.stats import (
    PRESENT,
    STATUS_LABEL,
    grade_rows,
    round_int,
    weekly_attendance_trend,
    weekly_grade_trend,
)

AUTO_ALPA_NOTE = "Otomatis: belum diabsen saat absensi diselesaikan."

# Siswa dianggap mengalami penurunan bila nilai terbarunya turun sekian poin dari nilai sebelumnya.
DECLINE_THRESHOLD = 5
TREND_POINTS = 6
GRADE_LIMIT = 300
ACTIVITY_WINDOW = timedelta(days=14)
ACTIVITY_LIMIT = 20


def class_summaries(db: Session, classes: list[Kelas], today: date) -> list[KelasRingkasOut]:
    if not classes:
        return []
    rows = db.execute(
        select(
            Siswa.kelas_id,
            func.count(func.distinct(Siswa.id)),
            func.count(Absensi.id).filter(Absensi.status.in_(PRESENT)),
        )
        .outerjoin(Absensi, and_(Absensi.siswa_id == Siswa.id, Absensi.tanggal == today))
        .where(Siswa.kelas_id.in_([k.id for k in classes]))
        .group_by(Siswa.kelas_id)
    ).all()
    counts = {kelas_id: (total, present) for kelas_id, total, present in rows}

    result = []
    for kelas in classes:
        total, present = counts.get(kelas.id, (0, 0))
        result.append(
            KelasRingkasOut(
                kelas=kelas.nama_kelas,
                jumlah_siswa=total,
                persen_hadir=round(present / total * 100) if total else 0,
            )
        )
    return result


def _declining_students(db: Session, student_ids: list[int]) -> set[int]:
    partition = [Nilai.siswa_id, Nilai.kategori]
    previous = func.lag(Nilai.nilai).over(partition_by=partition, order_by=[Nilai.tanggal, Nilai.id])
    recency = func.row_number().over(
        partition_by=partition, order_by=[Nilai.tanggal.desc(), Nilai.id.desc()]
    )
    ranked = (
        select(Nilai.siswa_id, Nilai.nilai, previous.label("prev"), recency.label("rn"))
        .where(Nilai.siswa_id.in_(student_ids))
        .subquery()
    )
    return set(
        db.scalars(
            select(ranked.c.siswa_id).where(
                ranked.c.rn == 1,
                ranked.c.prev.is_not(None),
                ranked.c.prev - ranked.c.nilai >= DECLINE_THRESHOLD,
            )
        )
    )


def class_detail(db: Session, kelas: Kelas, today: date) -> KelasDetailOut:
    students = list(db.scalars(select(Siswa).where(Siswa.kelas_id == kelas.id).order_by(Siswa.nama)))
    ids = [s.id for s in students]
    if not ids:
        return KelasDetailOut(
            siswa=[], nilai=[], rata_literasi=0, rata_numerasi=0,
            tren=TrenOut(literasi=[], numerasi=[], kehadiran=[]),
        )

    attendance = {
        siswa_id: (status, waktu)
        for siswa_id, status, waktu in db.execute(
            select(Absensi.siswa_id, Absensi.status, Absensi.waktu).where(
                Absensi.siswa_id.in_(ids), Absensi.tanggal == today
            )
        )
    }
    averages = {
        (siswa_id, kategori): avg
        for siswa_id, kategori, avg in db.execute(
            select(Nilai.siswa_id, Nilai.kategori, func.avg(Nilai.nilai))
            .where(Nilai.siswa_id.in_(ids))
            .group_by(Nilai.siswa_id, Nilai.kategori)
        )
    }
    declining = _declining_students(db, ids)

    siswa_out = []
    for s in students:
        status, waktu = attendance.get(s.id, (None, None))
        siswa_out.append(
            SiswaKelasOut(
                id=s.id,
                nama=s.nama,
                klasifikasi=s.status_klasifikasi.value if s.status_klasifikasi else None,
                status=status.value if status else None,
                waktu=str(waktu) if waktu else None,
                literasi=round_int(averages.get((s.id, KategoriNilai.LITERASI))),
                numerasi=round_int(averages.get((s.id, KategoriNilai.NUMERASI))),
                menurun=s.id in declining,
            )
        )

    grades = grade_rows(db, ids, GRADE_LIMIT)
    nilai_out = [
        NilaiOut(
            id=r.id,
            siswa_id=r.siswa_id,
            siswa=r.nama,
            kategori=r.kategori.value,
            jenis_ujian=r.jenis_ujian,
            nilai=float(r.nilai),
            nilai_sebelumnya=float(r.prev) if r.prev is not None else None,
            tanggal=r.tanggal,
            catatan_guru=r.catatan_guru,
        )
        for r in grades
    ]

    def class_average(category: KategoriNilai) -> int:
        return round_int(
            db.scalar(
                select(func.avg(Nilai.nilai)).where(
                    Nilai.siswa_id.in_(ids), Nilai.kategori == category
                )
            )
        )

    return KelasDetailOut(
        siswa=siswa_out,
        nilai=nilai_out,
        rata_literasi=class_average(KategoriNilai.LITERASI),
        rata_numerasi=class_average(KategoriNilai.NUMERASI),
        tren=TrenOut(
            literasi=weekly_grade_trend(db, ids, KategoriNilai.LITERASI, TREND_POINTS),
            numerasi=weekly_grade_trend(db, ids, KategoriNilai.NUMERASI, TREND_POINTS),
            kehadiran=weekly_attendance_trend(db, ids, TREND_POINTS),
        ),
    )


def set_manual_attendance(
    db: Session,
    *,
    siswa: Siswa,
    guru: Guru,
    status: StatusAbsensi,
    catatan: str | None,
    now: datetime,
) -> None:
    """Mencatat absensi manual hari ini; selalu menimpa catatan yang ada (keputusan guru).

    Jam datang hanya ada untuk Hadir/Terlambat. Bila siswa sudah punya jam datang (misalnya dari
    scan wajah), jam itu dipertahankan.
    """
    clock = now.time().replace(microsecond=0)
    values = {
        "status": status,
        "metode_input": MetodeInput.MANUAL,
        "dicatat_oleh": guru.id,
        "catatan": (catatan or "").strip() or None,
    }
    insert = pg_insert(Absensi).values(
        siswa_id=siswa.id,
        tanggal=now.date(),
        waktu=clock if status in PRESENT else None,
        **values,
    )
    keep_arrival = case(
        (insert.excluded.status.in_(PRESENT), func.coalesce(Absensi.waktu, insert.excluded.waktu)),
        else_=None,
    )
    previous = db.scalar(
        select(Absensi.status).where(Absensi.siswa_id == siswa.id, Absensi.tanggal == now.date())
    )
    db.execute(
        insert.on_conflict_do_update(
            index_elements=["siswa_id", "tanggal"],
            set_={**values, "waktu": keep_arrival},
        )
    )
    if previous != status:
        notify_parents_of_attendance(db, [(siswa.id, status)])
    db.commit()


def finish_attendance(db: Session, kelas: Kelas, guru: Guru, today: date) -> int:
    """Menutup absensi hari ini: siswa yang belum punya catatan dicatat Alpa. Aman dipanggil ulang."""
    missing = list(
        db.scalars(
            select(Siswa.id).where(
                Siswa.kelas_id == kelas.id,
                ~exists().where(and_(Absensi.siswa_id == Siswa.id, Absensi.tanggal == today)),
            )
        )
    )
    inserted: list[int] = []
    if missing:
        inserted = list(
            db.execute(
                pg_insert(Absensi)
                .values(
                    [
                        {
                            "siswa_id": siswa_id,
                            "tanggal": today,
                            "status": StatusAbsensi.ALPA,
                            "metode_input": MetodeInput.MANUAL,
                            "dicatat_oleh": guru.id,
                            "catatan": AUTO_ALPA_NOTE,
                        }
                        for siswa_id in missing
                    ]
                )
                .on_conflict_do_nothing(index_elements=["siswa_id", "tanggal"])
                .returning(Absensi.siswa_id)
            ).scalars()
        )
        notify_parents_of_attendance(db, [(siswa_id, StatusAbsensi.ALPA) for siswa_id in inserted])
    notify(
        db,
        wali_user_ids(db, kelas.wali_kelas_id, exclude_user_id=guru.user_id),
        f"Absensi Kelas {kelas.nama_kelas} selesai.",
        target="absensi",
    )
    db.commit()
    return len(inserted)


def recent_activities(
    db: Session, classes: list[Kelas], *, now: datetime
) -> list[AktivitasOut]:
    if not classes:
        return []
    since = now - ACTIVITY_WINDOW
    class_ids = [k.id for k in classes]

    absensi_rows = db.execute(
        select(Siswa.nama, Absensi.status, Absensi.metode_input, Absensi.updated_at)
        .join(Siswa, Siswa.id == Absensi.siswa_id)
        .where(
            Siswa.kelas_id.in_(class_ids),
            Absensi.updated_at >= since,
            (Absensi.catatan.is_(None)) | (Absensi.catatan != AUTO_ALPA_NOTE),
        )
        .order_by(Absensi.updated_at.desc())
        .limit(ACTIVITY_LIMIT)
    ).all()
    nilai_rows = db.execute(
        select(Siswa.nama, Nilai.id, Nilai.kategori, Nilai.created_at, Nilai.updated_at)
        .join(Siswa, Siswa.id == Nilai.siswa_id)
        .where(Siswa.kelas_id.in_(class_ids), Nilai.updated_at >= since)
        .order_by(Nilai.updated_at.desc())
        .limit(ACTIVITY_LIMIT)
    ).all()

    items = [
        AktivitasOut(
            judul=f"Absensi {nama} tercatat: {STATUS_LABEL[status]}"
            if metode is MetodeInput.MANUAL
            else f"Absensi {nama} tercatat",
            target="absensi",
            target_id=None,
            created_at=when,
        )
        for nama, status, metode, when in absensi_rows
    ]
    items += [
        AktivitasOut(
            judul=(
                f"Nilai {kategori.value} {nama} "
                + ("diperbarui" if updated > created else "ditambahkan")
            ),
            target="nilai",
            target_id=nilai_id,
            created_at=updated,
        )
        for nama, nilai_id, kategori, created, updated in nilai_rows
    ]
    items.sort(key=lambda i: i.created_at, reverse=True)
    return items[:ACTIVITY_LIMIT]
