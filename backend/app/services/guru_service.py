from datetime import date, datetime, timedelta
from decimal import Decimal

from sqlalchemy import and_, case, exists, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import (
    Absensi,
    Guru,
    Kelas,
    KlasifikasiSiswa,
    MataPelajaran,
    Nilai,
    PeriodeAkademik,
    Siswa,
)
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
from app.services.periods import grades_in, period_out
from app.services.stats import (
    PRESENT,
    trend_points,
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


def _declining_students(
    db: Session, student_ids: list[int], periode: PeriodeAkademik | None
) -> set[int]:
    """Nilai terbaru turun >= DECLINE_THRESHOLD dari nilai sebelumnya pada komponen yang sama."""
    partition = [Nilai.siswa_id, Nilai.komponen_id, Nilai.kategori]
    previous = func.lag(Nilai.nilai).over(partition_by=partition, order_by=[Nilai.tanggal, Nilai.id])
    recency = func.row_number().over(
        partition_by=partition, order_by=[Nilai.tanggal.desc(), Nilai.id.desc()]
    )
    stmt = select(Nilai.siswa_id, Nilai.nilai, previous.label("prev"), recency.label("rn")).where(
        Nilai.siswa_id.in_(student_ids)
    )
    ranked = grades_in(stmt, periode).subquery()
    return set(
        db.scalars(
            select(ranked.c.siswa_id).where(
                ranked.c.rn == 1,
                ranked.c.prev.is_not(None),
                ranked.c.prev - ranked.c.nilai >= DECLINE_THRESHOLD,
            )
        )
    )


def _category_scores(
    db: Session, ids: list[int], periode: PeriodeAkademik | None
) -> tuple[dict[tuple[int, KategoriNilai], Decimal], dict[int, str | None]]:
    """Skor Literasi/Numerasi per siswa dan klasifikasinya untuk periode yang ditampilkan.

    Dengan periode: skor dan klasifikasi diambil dari hasil perhitungan periode itu (rumus yang
    sama dengan chart klasifikasi). Tanpa periode (belum ditetapkan admin): rata-rata semua nilai
    dan klasifikasi lama di kolom siswa.
    """
    if periode is None:
        averages = {
            (siswa_id, kategori): avg
            for siswa_id, kategori, avg in db.execute(
                select(Nilai.siswa_id, Nilai.kategori, func.avg(Nilai.nilai))
                .where(Nilai.siswa_id.in_(ids), Nilai.kategori.is_not(None))
                .group_by(Nilai.siswa_id, Nilai.kategori)
            )
        }
        labels = {
            siswa_id: label.value if label else None
            for siswa_id, label in db.execute(
                select(Siswa.id, Siswa.status_klasifikasi).where(Siswa.id.in_(ids))
            )
        }
        return averages, labels

    scores: dict[tuple[int, KategoriNilai], Decimal] = {}
    labels: dict[int, str | None] = {}
    for row in db.scalars(
        select(KlasifikasiSiswa).where(
            KlasifikasiSiswa.periode_id == periode.id, KlasifikasiSiswa.siswa_id.in_(ids)
        )
    ):
        if row.skor_literasi is not None:
            scores[(row.siswa_id, KategoriNilai.LITERASI)] = row.skor_literasi
        if row.skor_numerasi is not None:
            scores[(row.siswa_id, KategoriNilai.NUMERASI)] = row.skor_numerasi
        labels[row.siswa_id] = row.klasifikasi.value if row.klasifikasi else None
    return scores, labels


def nilai_out(r) -> NilaiOut:
    return NilaiOut(
        id=r.id,
        siswa_id=r.siswa_id,
        siswa=r.nama,
        kategori=r.kategori.value if r.kategori else None,
        jenis_ujian=r.jenis_ujian,
        periode_id=r.periode_id,
        mapel_id=r.mapel_id,
        mapel=r.mapel,
        komponen_id=r.komponen_id,
        komponen=r.komponen,
        nilai=float(r.nilai),
        nilai_sebelumnya=float(r.prev) if r.prev is not None else None,
        tanggal=r.tanggal,
        catatan_guru=r.catatan_guru,
    )


def class_detail(
    db: Session, kelas: Kelas, today: date, periode: PeriodeAkademik | None
) -> KelasDetailOut:
    students = list(db.scalars(select(Siswa).where(Siswa.kelas_id == kelas.id).order_by(Siswa.nama)))
    ids = [s.id for s in students]
    if not ids:
        return KelasDetailOut(
            periode=period_out(periode), siswa=[], nilai=[], rata_literasi=0, rata_numerasi=0,
            tren=TrenOut(literasi=[], numerasi=[], kehadiran=[], titik=trend_points(db, [], 0, periode)),
        )

    attendance = {
        siswa_id: (status, waktu)
        for siswa_id, status, waktu in db.execute(
            select(Absensi.siswa_id, Absensi.status, Absensi.waktu).where(
                Absensi.siswa_id.in_(ids), Absensi.tanggal == today
            )
        )
    }
    scores, labels = _category_scores(db, ids, periode)
    declining = _declining_students(db, ids, periode)

    siswa_out = []
    for s in students:
        status, waktu = attendance.get(s.id, (None, None))
        siswa_out.append(
            SiswaKelasOut(
                id=s.id,
                nama=s.nama,
                klasifikasi=labels.get(s.id),
                status=status.value if status else None,
                waktu=str(waktu) if waktu else None,
                literasi=round_int(scores.get((s.id, KategoriNilai.LITERASI))),
                numerasi=round_int(scores.get((s.id, KategoriNilai.NUMERASI))),
                menurun=s.id in declining,
            )
        )

    def class_average(category: KategoriNilai) -> int:
        values = [v for (_, k), v in scores.items() if k is category]
        return round_int(sum(values) / len(values)) if values else 0

    return KelasDetailOut(
        periode=period_out(periode),
        siswa=siswa_out,
        nilai=[nilai_out(r) for r in grade_rows(db, ids, GRADE_LIMIT, periode)],
        rata_literasi=class_average(KategoriNilai.LITERASI),
        rata_numerasi=class_average(KategoriNilai.NUMERASI),
        tren=TrenOut(
            literasi=weekly_grade_trend(db, ids, KategoriNilai.LITERASI, TREND_POINTS, periode),
            numerasi=weekly_grade_trend(db, ids, KategoriNilai.NUMERASI, TREND_POINTS, periode),
            kehadiran=weekly_attendance_trend(db, ids, TREND_POINTS, periode),
            titik=trend_points(db, ids, TREND_POINTS, periode),
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
        select(
            Siswa.nama, Nilai.id, Nilai.kategori, MataPelajaran.nama, Nilai.created_at, Nilai.updated_at
        )
        .join(Siswa, Siswa.id == Nilai.siswa_id)
        .outerjoin(MataPelajaran, MataPelajaran.id == Nilai.mapel_id)
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
                f"Nilai {mapel or kategori.value} {nama} "
                + ("diperbarui" if updated > created else "ditambahkan")
            ),
            target="nilai",
            target_id=nilai_id,
            created_at=updated,
        )
        for nama, nilai_id, kategori, mapel, created, updated in nilai_rows
    ]
    items.sort(key=lambda i: i.created_at, reverse=True)
    return items[:ACTIVITY_LIMIT]
