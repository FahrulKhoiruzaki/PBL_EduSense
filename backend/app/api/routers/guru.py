from datetime import date, datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_guru, get_now
from app.api.guru_access import (
    accessible_classes,
    get_class,
    get_student,
    require_mapel,
    require_read,
    require_subject,
    taught_subject_ids,
)
from app.api.routers.notifications import notification_router
from app.core.database import get_db
from app.core.errors import AppError, not_found
from app.models import Guru, KomponenPenilaian, MataPelajaran, Nilai, Siswa
from app.models.base import UserRole
from app.schemas.guru import (
    AbsensiManualIn,
    AktivitasOut,
    FinishOut,
    KelasDetailOut,
    KelasRingkasOut,
    NilaiCreatedOut,
    NilaiIn,
)
from app.schemas.academic import (
    KlasifikasiRingkasanOut,
    MapelKelasOut,
    PeriodeOut,
    RaporKelasOut,
    RaporOut,
    RekapOut,
)
from app.schemas.parent import RiwayatItemOut
from app.services import grading_service, guru_service, notification_service, parent_service, periods

router = APIRouter(prefix="/guru", tags=["guru"])
router.include_router(notification_router(UserRole.GURU))


@router.get("/classes", response_model=list[KelasRingkasOut])
def list_classes(
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[KelasRingkasOut]:
    return guru_service.class_summaries(db, accessible_classes(db, guru), now.date())


@router.get("/classes/{kode}", response_model=KelasDetailOut)
def class_detail(
    kode: str,
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> KelasDetailOut:
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    periode = periods.resolve_period(db, periode_id)
    return guru_service.class_detail(db, kelas, now.date(), periode)


@router.put("/classes/{kode}/attendance/{siswa_id}", status_code=204)
def set_attendance(
    kode: str,
    siswa_id: int,
    body: AbsensiManualIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> Response:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    guru_service.set_manual_attendance(
        db, siswa=siswa, guru=guru, status=body.status, catatan=body.catatan, now=now
    )
    return Response(status_code=204)


@router.post("/classes/{kode}/attendance/finish", response_model=FinishOut)
def finish_attendance(
    kode: str,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> FinishOut:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    return FinishOut(jumlah_alpa=guru_service.finish_attendance(db, kelas, guru, now.date()))


def _component_for_grade(
    db: Session, guru: Guru, kelas, komponen_id: int, tanggal: date
) -> KomponenPenilaian:
    """Validasi komponen: aktif, mapel aktif dan berlaku untuk jenjang kelas, diajar guru ini,
    dan tanggal nilai berada di dalam periode komponen."""
    komponen = db.get(KomponenPenilaian, komponen_id)
    if komponen is None:
        raise AppError(422, "Komponen penilaian tidak ditemukan.",
                       errors={"komponen_id": "Pilih komponen penilaian yang tersedia."})
    require_subject(db, guru, kelas, komponen.mapel_id)
    if not komponen.aktif or not komponen.mapel.aktif:
        raise AppError(422, "Komponen penilaian ini sedang nonaktif.",
                       errors={"komponen_id": "Komponen penilaian ini sedang nonaktif."})
    if periods.class_level(kelas) not in komponen.mapel.tingkat:
        raise AppError(422, "Mata pelajaran ini tidak berlaku untuk jenjang kelas ini.",
                       errors={"komponen_id": "Mata pelajaran ini tidak berlaku untuk kelas ini."})
    periode = komponen.periode
    if not periode.contains(tanggal):
        message = (
            f"Tanggal harus di dalam {periode.label} "
            f"({periode.tanggal_mulai:%d-%m-%Y} s.d. {periode.tanggal_selesai:%d-%m-%Y})."
        )
        raise AppError(422, message, errors={"tanggal": message})
    return komponen


def _apply_grade(nilai: Nilai, body: NilaiIn, komponen: KomponenPenilaian) -> None:
    nilai.komponen_id = komponen.id
    nilai.jenis_ujian = (body.jenis_ujian or "").strip() or komponen.nama
    nilai.nilai = Decimal(str(round(body.nilai, 2)))
    nilai.tanggal = body.tanggal
    nilai.catatan_guru = (body.catatan_guru or "").strip() or None


@router.post("/classes/{kode}/grades", response_model=NilaiCreatedOut, status_code=201)
def create_grade(
    kode: str,
    body: NilaiIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> NilaiCreatedOut:
    kelas = get_class(db, kode)
    require_mapel(db, guru, kelas)
    siswa = get_student(db, kelas, body.siswa_id)
    komponen = _component_for_grade(db, guru, kelas, body.komponen_id, body.tanggal)

    nilai = Nilai(siswa_id=siswa.id, dicatat_oleh=guru.id)
    _apply_grade(nilai, body, komponen)
    db.add(nilai)
    db.flush()
    db.refresh(nilai)  # kolom periode/mapel/kategori diisi trigger database
    grading_service.recompute_for_grades(db, [(nilai.periode_id, siswa.id)])
    notification_service.notify(
        db,
        notification_service.wali_user_ids(db, kelas.wali_kelas_id, exclude_user_id=guru.user_id),
        "Nilai baru ditambahkan.",
        target="nilai",
        target_id=nilai.id,
    )
    notification_service.notify_parent_of_grade(db, siswa, komponen.mapel.nama, nilai.id)
    db.commit()
    return NilaiCreatedOut(id=nilai.id)


def _grade_for_update(db: Session, guru: Guru, grade_id: int):
    nilai = db.get(Nilai, grade_id)
    siswa = db.get(Siswa, nilai.siswa_id) if nilai else None
    if nilai is None or siswa is None:
        raise not_found("Nilai tidak ditemukan.")
    kelas = siswa.kelas
    require_subject(db, guru, kelas, nilai.mapel_id)
    return nilai, kelas


@router.put("/grades/{grade_id}", status_code=204)
def update_grade(
    grade_id: int,
    body: NilaiIn,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> Response:
    nilai, kelas = _grade_for_update(db, guru, grade_id)
    siswa = get_student(db, kelas, body.siswa_id)
    komponen = _component_for_grade(db, guru, kelas, body.komponen_id, body.tanggal)

    before = (nilai.periode_id, nilai.siswa_id)
    nilai.siswa_id = siswa.id
    _apply_grade(nilai, body, komponen)
    db.flush()
    db.refresh(nilai)
    grading_service.recompute_for_grades(db, [before, (nilai.periode_id, nilai.siswa_id)])
    db.commit()
    return Response(status_code=204)


@router.delete("/grades/{grade_id}", status_code=204)
def delete_grade(
    grade_id: int,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> Response:
    nilai, _ = _grade_for_update(db, guru, grade_id)
    affected = (nilai.periode_id, nilai.siswa_id)
    db.delete(nilai)
    db.flush()
    grading_service.recompute_for_grades(db, [affected])
    db.commit()
    return Response(status_code=204)


# Periode, mata pelajaran, rekap, dan klasifikasi


@router.get("/periods", response_model=list[PeriodeOut])
def list_periods(
    _: Guru = Depends(get_current_guru), db: Session = Depends(get_db)
) -> list[PeriodeOut]:
    return [periods.period_out(p) for p in periods.ordered_periods(db)]


@router.get("/classes/{kode}/subjects", response_model=list[MapelKelasOut])
def class_subjects(
    kode: str,
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> list[MapelKelasOut]:
    """Mapel aktif yang berlaku untuk jenjang kelas, dengan komponen periode yang dipilih.

    `boleh_input` menandai mapel yang diajar guru ini di kelas ini. Wali kelas melihat semua mapel
    kelasnya (mode lihat).
    """
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    periode = periods.resolve_period(db, periode_id)
    taught = taught_subject_ids(db, guru, kelas)
    level = periods.class_level(kelas)
    subjects = [
        m
        for m in db.scalars(select(MataPelajaran).order_by(MataPelajaran.urutan, MataPelajaran.nama))
        if level in m.tingkat and (m.aktif or m.id in taught)
    ]
    components: dict[int, list[KomponenPenilaian]] = {}
    if periode is not None:
        for k in db.scalars(
            select(KomponenPenilaian)
            .where(KomponenPenilaian.periode_id == periode.id)
            .order_by(KomponenPenilaian.urutan, KomponenPenilaian.id)
        ):
            components.setdefault(k.mapel_id, []).append(k)
    is_wali = kelas.wali_kelas_id == guru.id
    return [
        MapelKelasOut(
            mapel_id=m.id, kode=m.kode, nama=m.nama, jenis=m.jenis,
            boleh_input=m.id in taught and m.aktif,
            komponen=grading_service.component_summaries(components.get(m.id, [])),
        )
        for m in subjects
        if m.id in taught or is_wali
    ]


@router.get("/classes/{kode}/recap", response_model=RekapOut)
def class_recap(
    kode: str,
    mapel_id: int = Query(),
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> RekapOut:
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    periode = periods.resolve_period(db, periode_id)
    if periode is None:
        raise AppError(409, periods_note())
    mapel = db.get(MataPelajaran, mapel_id)
    if mapel is None:
        raise not_found("Mata pelajaran tidak ditemukan.")
    if kelas.wali_kelas_id != guru.id:
        require_subject(db, guru, kelas, mapel.id)
    return grading_service.recap(db, kelas, periode, mapel)


@router.get("/classes/{kode}/classification", response_model=KlasifikasiRingkasanOut)
def class_classification(
    kode: str,
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> KlasifikasiRingkasanOut:
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    return grading_service.summary(db, periods.resolve_period(db, periode_id), [kelas])


def _visible_subjects(db: Session, guru: Guru, kelas) -> set[int] | None:
    """Wali kelas memantau semua mapel kelasnya (lihat saja); guru mapel hanya mapel yang
    ditugaskan kepadanya di kelas itu."""
    return None if kelas.wali_kelas_id == guru.id else taught_subject_ids(db, guru, kelas)


@router.get("/classes/{kode}/report", response_model=RaporKelasOut)
def class_report(
    kode: str,
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> RaporKelasOut:
    """Rekap nilai akhir dan status kelengkapan semua siswa x mapel di kelas."""
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    return grading_service.class_report(
        db, kelas, periods.resolve_period(db, periode_id), _visible_subjects(db, guru, kelas)
    )


@router.get("/classes/{kode}/students/{siswa_id}/history", response_model=list[RiwayatItemOut])
def student_history(
    kode: str,
    siswa_id: int,
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[RiwayatItemOut]:
    """Riwayat nilai, kehadiran, dan klasifikasi siswa (sama dengan riwayat di portal orang tua);
    guru mapel hanya melihat nilai mapel yang diampunya."""
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    return parent_service.history(db, siswa, now.date(), _visible_subjects(db, guru, kelas))


@router.get("/classes/{kode}/students/{siswa_id}/report", response_model=RaporOut)
def student_report(
    kode: str,
    siswa_id: int,
    periode_id: int | None = Query(default=None),
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
) -> RaporOut:
    kelas = get_class(db, kode)
    require_read(db, guru, kelas)
    siswa = get_student(db, kelas, siswa_id)
    return grading_service.student_report(
        db, siswa, periods.resolve_period(db, periode_id), _visible_subjects(db, guru, kelas)
    )


def periods_note() -> str:
    return grading_service.NO_PERIOD_NOTE


@router.get("/activities", response_model=list[AktivitasOut])
def list_activities(
    guru: Guru = Depends(get_current_guru),
    db: Session = Depends(get_db),
    now: datetime = Depends(get_now),
) -> list[AktivitasOut]:
    return guru_service.recent_activities(db, accessible_classes(db, guru), now=now)
