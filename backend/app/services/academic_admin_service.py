"""Pengelolaan data akademik oleh admin: periode, mata pelajaran, komponen nilai, aturan klasifikasi.

Prinsip data historis:
  * Periode yang sudah memiliki nilai, komponen, atau hasil klasifikasi tidak dapat dihapus.
  * Mata pelajaran/komponen yang sudah dipakai tidak dapat dihapus; gunakan nonaktifkan.
  * Mengganti periode aktif tidak mengubah atau menghapus data periode lain.
"""

from decimal import Decimal

from sqlalchemy import exists, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError, conflict, not_found
from app.models import (
    AturanKlasifikasi,
    Kelas,
    KlasifikasiSiswa,
    KomponenPenilaian,
    MapelGuru,
    MataPelajaran,
    Nilai,
    PengaturanSekolah,
    PeriodeAkademik,
    User,
)
from app.models.base import KategoriNilai, LogTipe
from app.schemas.academic import (
    AturanIn,
    AturanOut,
    CopyOut,
    KomponenIn,
    KomponenOut,
    MapelIn,
    MapelOut,
    PeriodeAdminOut,
    PeriodeIn,
    RecomputeOut,
)
from app.services import grading_service, log_service, periods


def _invalid(field: str, message: str, status: int = 422) -> AppError:
    return AppError(status, message, errors={field: message})


def _who(actor: User) -> str:
    return log_service.actor_name(actor)


# Periode


def list_periods(db: Session) -> list[PeriodeAdminOut]:
    grade_counts = dict(
        db.execute(
            select(Nilai.periode_id, func.count()).where(Nilai.periode_id.is_not(None)).group_by(Nilai.periode_id)
        ).all()
    )
    component_counts = dict(
        db.execute(
            select(KomponenPenilaian.periode_id, func.count()).group_by(KomponenPenilaian.periode_id)
        ).all()
    )
    with_results = set(db.scalars(select(KlasifikasiSiswa.periode_id).distinct()))
    with_rule = set(db.scalars(select(AturanKlasifikasi.periode_id)))
    result = []
    for p in periods.ordered_periods(db):
        grades, components = grade_counts.get(p.id, 0), component_counts.get(p.id, 0)
        result.append(
            PeriodeAdminOut(
                **periods.period_out(p).model_dump(),
                jumlah_nilai=grades,
                jumlah_komponen=components,
                punya_aturan=p.id in with_rule,
                dapat_dihapus=not p.aktif and not grades and not components and p.id not in with_results,
            )
        )
    return result


def _check_overlap(db: Session, body: PeriodeIn, except_id: int | None = None) -> None:
    stmt = select(PeriodeAkademik).where(
        PeriodeAkademik.tanggal_mulai <= body.tanggal_selesai,
        PeriodeAkademik.tanggal_selesai >= body.tanggal_mulai,
    )
    if except_id is not None:
        stmt = stmt.where(PeriodeAkademik.id != except_id)
    clash = db.scalar(stmt.limit(1))
    if clash is not None:
        raise _invalid(
            "tanggal_mulai", f"Rentang tanggal bertumpang tindih dengan {clash.label}.", status=409
        )


def _check_unique(db: Session, body: PeriodeIn, except_id: int | None = None) -> None:
    stmt = select(PeriodeAkademik.id).where(
        PeriodeAkademik.tahun_ajaran == body.tahun_ajaran, PeriodeAkademik.semester == body.semester
    )
    if except_id is not None:
        stmt = stmt.where(PeriodeAkademik.id != except_id)
    if db.scalar(stmt) is not None:
        raise _invalid("semester", "Semester ini sudah ada untuk tahun ajaran tersebut.", status=409)


def _commit_period(db: Session) -> None:
    """Pemeriksaan di atas bisa kalah balapan; constraint database yang memutuskan."""
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        text = str(exc.orig)
        if "tumpang_tindih" in text:
            raise _invalid("tanggal_mulai", "Rentang tanggal bertumpang tindih dengan periode lain.", 409) from None
        if "periode_memuat_nilai" in text:
            raise _invalid(
                "tanggal_mulai", "Ada nilai di periode ini yang tanggalnya di luar rentang baru.", 409
            ) from None
        raise _invalid("semester", "Semester ini sudah ada untuk tahun ajaran tersebut.", 409) from None


def create_period(db: Session, actor: User, body: PeriodeIn) -> PeriodeAdminOut:
    _check_unique(db, body)
    _check_overlap(db, body)
    periode = PeriodeAkademik(**body.model_dump())
    db.add(periode)
    db.flush()
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} menambahkan periode {periode.label}.")
    _commit_period(db)
    return next(p for p in list_periods(db) if p.id == periode.id)


def update_period(db: Session, actor: User, periode_id: int, body: PeriodeIn) -> PeriodeAdminOut:
    periode = periods.get_period(db, periode_id)
    identity_changed = (body.tahun_ajaran, body.semester) != (periode.tahun_ajaran, periode.semester)
    if identity_changed and _period_used(db, periode.id):
        raise _invalid(
            "tahun_ajaran",
            "Tahun ajaran dan semester tidak dapat diubah karena periode sudah memiliki data akademik.",
            409,
        )
    _check_unique(db, body, except_id=periode.id)
    _check_overlap(db, body, except_id=periode.id)
    outside = db.scalar(
        select(func.count()).select_from(Nilai).where(
            Nilai.periode_id == periode.id,
            (Nilai.tanggal < body.tanggal_mulai) | (Nilai.tanggal > body.tanggal_selesai),
        )
    )
    if outside:
        raise _invalid(
            "tanggal_mulai", f"{outside} nilai di periode ini akan berada di luar rentang tanggal baru.", 409
        )
    for key, value in body.model_dump().items():
        setattr(periode, key, value)
    if periode.aktif:
        _sync_settings(db, periode)
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} memperbarui periode {periode.label}.")
    _commit_period(db)
    return next(p for p in list_periods(db) if p.id == periode.id)


def _period_used(db: Session, periode_id: int) -> bool:
    return bool(
        db.scalar(select(exists().where(Nilai.periode_id == periode_id)))
        or db.scalar(select(exists().where(KomponenPenilaian.periode_id == periode_id)))
        or db.scalar(select(exists().where(KlasifikasiSiswa.periode_id == periode_id)))
    )


def _sync_settings(db: Session, periode: PeriodeAkademik) -> None:
    """Kolom lama pengaturan_sekolah.tahun_ajaran diselaraskan dengan periode aktif."""
    settings = db.get(PengaturanSekolah, True)
    if settings is not None:
        settings.tahun_ajaran = periode.tahun_ajaran


def activate_period(db: Session, actor: User, periode_id: int) -> PeriodeAdminOut:
    periode = periods.get_period(db, periode_id)
    if not periode.aktif:
        db.execute(update(PeriodeAkademik).where(PeriodeAkademik.aktif).values(aktif=False))
        db.flush()
        periode.aktif = True
        db.flush()
        _sync_settings(db, periode)
        # Kolom lama siswa.status_klasifikasi mengikuti hasil periode yang baru aktif.
        grading_service.sync_status_cache(db, periode)
        log_service.record(
            db, actor, LogTipe.SISTEM, f"{_who(actor)} menetapkan {periode.label} sebagai periode aktif."
        )
        db.commit()
    return next(p for p in list_periods(db) if p.id == periode.id)


def delete_period(db: Session, actor: User, periode_id: int) -> None:
    periode = periods.get_period(db, periode_id)
    if periode.aktif:
        raise conflict("Periode aktif tidak dapat dihapus. Aktifkan periode lain terlebih dahulu.")
    if _period_used(db, periode.id):
        raise conflict(
            "Periode ini sudah memiliki komponen, nilai, atau hasil klasifikasi sehingga tidak dapat "
            "dihapus. Data historis harus tetap tersimpan."
        )
    label = periode.label
    db.delete(periode)
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} menghapus periode {label}.")
    db.commit()


# Mata pelajaran


def _subject_usage(db: Session) -> set[int]:
    used = set(db.scalars(select(MapelGuru.mapel_id).where(MapelGuru.mapel_id.is_not(None))))
    used |= set(db.scalars(select(KomponenPenilaian.mapel_id)))
    used |= set(db.scalars(select(Nilai.mapel_id).where(Nilai.mapel_id.is_not(None))))
    return used


def _subject_out(m: MataPelajaran, used: set[int]) -> MapelOut:
    return MapelOut(
        id=m.id, kode=m.kode, nama=m.nama, deskripsi=m.deskripsi, jenis=m.jenis,
        tingkat=sorted(m.tingkat), aktif=m.aktif, urutan=m.urutan, dipakai=m.id in used,
    )


def list_subjects(db: Session) -> list[MapelOut]:
    used = _subject_usage(db)
    rows = db.scalars(
        select(MataPelajaran).order_by(MataPelajaran.jenis, MataPelajaran.urutan, MataPelajaran.nama)
    )
    return [_subject_out(m, used) for m in rows]


def get_subject(db: Session, mapel_id: int) -> MataPelajaran:
    mapel = db.get(MataPelajaran, mapel_id)
    if mapel is None:
        raise not_found("Mata pelajaran tidak ditemukan.")
    return mapel


def _check_subject_unique(db: Session, body: MapelIn, except_id: int | None = None) -> None:
    for field, clause, message in (
        ("kode", MataPelajaran.kode == body.kode, "Kode mata pelajaran sudah dipakai."),
        ("nama", func.lower(MataPelajaran.nama) == body.nama.lower(), "Nama mata pelajaran sudah ada."),
    ):
        stmt = select(MataPelajaran.id).where(clause)
        if except_id is not None:
            stmt = stmt.where(MataPelajaran.id != except_id)
        if db.scalar(stmt) is not None:
            raise _invalid(field, message, status=409)


def _commit_subject(db: Session) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _invalid("kode", "Kode atau nama mata pelajaran sudah dipakai.", 409) from None


def create_subject(db: Session, actor: User, body: MapelIn) -> MapelOut:
    _check_subject_unique(db, body)
    urutan = body.urutan
    if urutan is None:
        urutan = (db.scalar(select(func.max(MataPelajaran.urutan))) or 0) + 10
    mapel = MataPelajaran(
        kode=body.kode, nama=body.nama, deskripsi=body.deskripsi.strip(), jenis=body.jenis,
        tingkat=body.tingkat, urutan=urutan,
    )
    db.add(mapel)
    db.flush()
    jenis = "muatan lokal" if body.jenis == "muatan_lokal" else "mata pelajaran"
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} menambahkan {jenis} {mapel.nama}.")
    _commit_subject(db)
    return _subject_out(mapel, set())


def update_subject(db: Session, actor: User, mapel_id: int, body: MapelIn) -> MapelOut:
    mapel = get_subject(db, mapel_id)
    _check_subject_unique(db, body, except_id=mapel.id)
    removed_levels = set(mapel.tingkat) - set(body.tingkat)
    if removed_levels:
        _ensure_levels_not_assigned(db, mapel.id, removed_levels)
    mapel.kode, mapel.nama, mapel.deskripsi = body.kode, body.nama, body.deskripsi.strip()
    mapel.jenis, mapel.tingkat = body.jenis, body.tingkat
    if body.urutan is not None:
        mapel.urutan = body.urutan
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} memperbarui mata pelajaran {mapel.nama}.")
    _commit_subject(db)
    return _subject_out(mapel, _subject_usage(db))


def _ensure_levels_not_assigned(db: Session, mapel_id: int, levels: set[int]) -> None:
    classes = db.scalars(
        select(Kelas.nama_kelas)
        .join(MapelGuru, MapelGuru.kelas_id == Kelas.id)
        .where(MapelGuru.mapel_id == mapel_id)
        .distinct()
    ).all()
    blocked = sorted(code for code in classes if int(code[0]) in levels)
    if blocked:
        raise _invalid(
            "tingkat",
            f"Masih ada guru yang ditugaskan untuk mapel ini di kelas {', '.join(blocked)}. "
            "Lepaskan penugasannya terlebih dahulu.",
            409,
        )


def set_subject_active(db: Session, actor: User, mapel_id: int, active: bool) -> None:
    mapel = get_subject(db, mapel_id)
    mapel.aktif = active
    action = "mengaktifkan" if active else "menonaktifkan"
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} {action} mata pelajaran {mapel.nama}.")
    db.commit()


def delete_subject(db: Session, actor: User, mapel_id: int) -> None:
    mapel = get_subject(db, mapel_id)
    if mapel.id in _subject_usage(db):
        raise conflict(
            "Mata pelajaran ini sudah dipakai (penugasan guru, komponen, atau nilai) sehingga tidak "
            "dapat dihapus. Nonaktifkan saja agar data historis tetap tersimpan."
        )
    name = mapel.nama
    db.delete(mapel)
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} menghapus mata pelajaran {name}.")
    db.commit()


# Komponen penilaian


def _component_out(k: KomponenPenilaian, grade_count: int) -> KomponenOut:
    return KomponenOut(
        id=k.id, periode_id=k.periode_id, mapel_id=k.mapel_id, mapel=k.mapel.nama,
        mapel_kode=k.mapel.kode, kategori=k.kategori.value if k.kategori else None, nama=k.nama,
        deskripsi=k.deskripsi, bobot=float(k.bobot) if k.bobot is not None else None,
        aktif=k.aktif, urutan=k.urutan, jumlah_nilai=grade_count,
    )


def _grade_counts(db: Session, ids: list[int]) -> dict[int, int]:
    if not ids:
        return {}
    return dict(
        db.execute(
            select(Nilai.komponen_id, func.count()).where(Nilai.komponen_id.in_(ids)).group_by(Nilai.komponen_id)
        ).all()
    )


def list_components(db: Session, periode_id: int | None, mapel_id: int | None) -> list[KomponenOut]:
    periode = periods.resolve_period(db, periode_id)
    if periode is None:
        return []
    stmt = (
        select(KomponenPenilaian)
        .join(MataPelajaran, MataPelajaran.id == KomponenPenilaian.mapel_id)
        .where(KomponenPenilaian.periode_id == periode.id)
        .order_by(MataPelajaran.urutan, MataPelajaran.nama, KomponenPenilaian.urutan, KomponenPenilaian.id)
    )
    if mapel_id is not None:
        stmt = stmt.where(KomponenPenilaian.mapel_id == mapel_id)
    rows = list(db.scalars(stmt))
    counts = _grade_counts(db, [k.id for k in rows])
    return [_component_out(k, counts.get(k.id, 0)) for k in rows]


def get_component(db: Session, komponen_id: int) -> KomponenPenilaian:
    komponen = db.get(KomponenPenilaian, komponen_id)
    if komponen is None:
        raise not_found("Komponen penilaian tidak ditemukan.")
    return komponen


def _check_weight(
    db: Session, periode_id: int, mapel_id: int, bobot: float | None, except_id: int | None = None
) -> None:
    """Total bobot komponen AKTIF satu mapel di satu periode tidak boleh melebihi 100."""
    if bobot is None:
        return
    stmt = select(func.coalesce(func.sum(KomponenPenilaian.bobot), 0)).where(
        KomponenPenilaian.periode_id == periode_id,
        KomponenPenilaian.mapel_id == mapel_id,
        KomponenPenilaian.aktif,
    )
    if except_id is not None:
        stmt = stmt.where(KomponenPenilaian.id != except_id)
    others = Decimal(db.scalar(stmt))
    if others + Decimal(str(bobot)) > 100:
        raise _invalid(
            "bobot",
            f"Total bobot komponen aktif mapel ini akan menjadi {others + Decimal(str(bobot)):g}; "
            f"maksimal 100 (sisa {100 - others:g}).",
        )


def _check_component_name(db: Session, body: KomponenIn, except_id: int | None = None) -> None:
    stmt = select(KomponenPenilaian.id).where(
        KomponenPenilaian.periode_id == body.periode_id,
        KomponenPenilaian.mapel_id == body.mapel_id,
        func.lower(KomponenPenilaian.nama) == body.nama.lower(),
    )
    if except_id is not None:
        stmt = stmt.where(KomponenPenilaian.id != except_id)
    if db.scalar(stmt) is not None:
        raise _invalid("nama", "Komponen dengan nama ini sudah ada untuk mapel dan periode tersebut.", 409)


def _commit_component(db: Session) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _invalid("nama", "Komponen dengan nama ini sudah ada untuk mapel dan periode tersebut.", 409) from None


def create_component(db: Session, actor: User, body: KomponenIn) -> KomponenOut:
    periode = periods.get_period(db, body.periode_id)
    mapel = get_subject(db, body.mapel_id)
    if not mapel.aktif:
        raise _invalid("mapel_id", "Mata pelajaran ini sedang nonaktif.")
    _check_component_name(db, body)
    _check_weight(db, periode.id, mapel.id, body.bobot)
    urutan = body.urutan
    if urutan is None:
        urutan = (
            db.scalar(
                select(func.max(KomponenPenilaian.urutan)).where(
                    KomponenPenilaian.periode_id == periode.id, KomponenPenilaian.mapel_id == mapel.id
                )
            )
            or 0
        ) + 10
    komponen = KomponenPenilaian(
        periode_id=periode.id, mapel_id=mapel.id,
        kategori=KategoriNilai(body.kategori) if body.kategori else None,
        nama=body.nama, deskripsi=body.deskripsi.strip(),
        bobot=Decimal(str(body.bobot)) if body.bobot is not None else None, urutan=urutan,
    )
    db.add(komponen)
    db.flush()
    log_service.record(
        db, actor, LogTipe.SISTEM,
        f"{_who(actor)} menambahkan komponen {komponen.nama} untuk {mapel.nama} ({periode.label}).",
    )
    _commit_component(db)
    return _component_out(komponen, 0)


def update_component(db: Session, actor: User, komponen_id: int, body: KomponenIn) -> KomponenOut:
    komponen = get_component(db, komponen_id)
    graded = _grade_counts(db, [komponen.id]).get(komponen.id, 0)
    if graded and (body.periode_id, body.mapel_id) != (komponen.periode_id, komponen.mapel_id):
        raise _invalid(
            "mapel_id",
            "Komponen yang sudah memiliki nilai tidak dapat dipindah ke mapel atau periode lain.",
            409,
        )
    periods.get_period(db, body.periode_id)
    get_subject(db, body.mapel_id)
    _check_component_name(db, body, except_id=komponen.id)
    if komponen.aktif:
        _check_weight(db, body.periode_id, body.mapel_id, body.bobot, except_id=komponen.id)
    affects_scores = (
        komponen.kategori != (KategoriNilai(body.kategori) if body.kategori else None)
        or komponen.bobot != (Decimal(str(body.bobot)) if body.bobot is not None else None)
    )
    komponen.periode_id, komponen.mapel_id = body.periode_id, body.mapel_id
    komponen.kategori = KategoriNilai(body.kategori) if body.kategori else None
    komponen.nama, komponen.deskripsi = body.nama, body.deskripsi.strip()
    komponen.bobot = Decimal(str(body.bobot)) if body.bobot is not None else None
    if body.urutan is not None:
        komponen.urutan = body.urutan
    db.flush()
    if affects_scores and graded:
        grading_service.recompute(db, komponen.periode)
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} memperbarui komponen {komponen.nama}.")
    _commit_component(db)
    db.refresh(komponen)
    return _component_out(komponen, graded)


def set_component_active(db: Session, actor: User, komponen_id: int, active: bool) -> None:
    """Menonaktifkan: guru tidak dapat lagi memasukkan nilai baru ke komponen ini. Nilai yang
    sudah ada tetap tersimpan dan tetap dihitung (data historis tidak berubah)."""
    komponen = get_component(db, komponen_id)
    if active and not komponen.aktif:
        _check_weight(db, komponen.periode_id, komponen.mapel_id,
                      float(komponen.bobot) if komponen.bobot is not None else None,
                      except_id=komponen.id)
    komponen.aktif = active
    action = "mengaktifkan" if active else "menonaktifkan"
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} {action} komponen {komponen.nama}.")
    db.commit()


def delete_component(db: Session, actor: User, komponen_id: int) -> None:
    komponen = get_component(db, komponen_id)
    if _grade_counts(db, [komponen.id]):
        raise conflict(
            "Komponen ini sudah memiliki nilai siswa sehingga tidak dapat dihapus. Nonaktifkan saja."
        )
    name = komponen.nama
    db.delete(komponen)
    log_service.record(db, actor, LogTipe.SISTEM, f"{_who(actor)} menghapus komponen {name}.")
    db.commit()


def copy_components(db: Session, actor: User, source_id: int, target_id: int) -> CopyOut:
    if source_id == target_id:
        raise _invalid("ke_periode_id", "Periode asal dan tujuan harus berbeda.")
    source, target = periods.get_period(db, source_id), periods.get_period(db, target_id)
    existing = {
        (mapel_id, nama.lower())
        for mapel_id, nama in db.execute(
            select(KomponenPenilaian.mapel_id, KomponenPenilaian.nama).where(
                KomponenPenilaian.periode_id == target.id
            )
        )
    }
    copied = skipped = 0
    for k in db.scalars(
        select(KomponenPenilaian).where(KomponenPenilaian.periode_id == source.id).order_by(KomponenPenilaian.id)
    ):
        if (k.mapel_id, k.nama.lower()) in existing:
            skipped += 1
            continue
        db.add(KomponenPenilaian(
            periode_id=target.id, mapel_id=k.mapel_id, kategori=k.kategori, nama=k.nama,
            deskripsi=k.deskripsi, bobot=k.bobot, aktif=k.aktif, urutan=k.urutan,
        ))
        copied += 1
    log_service.record(
        db, actor, LogTipe.SISTEM,
        f"{_who(actor)} menyalin {copied} komponen dari {source.label} ke {target.label}.",
    )
    db.commit()
    return CopyOut(disalin=copied, dilewati=skipped)


# Aturan klasifikasi


def get_rule(db: Session, periode_id: int) -> AturanOut | None:
    return grading_service.rule_out(grading_service.get_rule(db, periods.get_period(db, periode_id)))


def save_rule(db: Session, actor: User, periode_id: int, body: AturanIn) -> AturanOut:
    periode = periods.get_period(db, periode_id)
    rule = db.get(AturanKlasifikasi, periode.id)
    if rule is None:
        rule = AturanKlasifikasi(periode_id=periode.id)
        db.add(rule)
    rule.metode = body.metode
    rule.batas_mahir = Decimal(str(body.batas_mahir))
    rule.batas_cukup = Decimal(str(body.batas_cukup))
    rule.diubah_oleh = actor.id
    db.flush()
    grading_service.recompute(db, periode)
    log_service.record(
        db, actor, LogTipe.SISTEM,
        f"{_who(actor)} menetapkan aturan klasifikasi {periode.label}: metode {body.metode}, "
        f"Mahir >= {body.batas_mahir:g}, Cukup >= {body.batas_cukup:g}.",
    )
    db.commit()
    db.refresh(rule)
    return grading_service.rule_out(rule)


def recompute_period(db: Session, actor: User, periode_id: int) -> RecomputeOut:
    periode = periods.get_period(db, periode_id)
    counted, classified = grading_service.recompute(db, periode)
    log_service.record(
        db, actor, LogTipe.SISTEM, f"{_who(actor)} menghitung ulang klasifikasi {periode.label}."
    )
    db.commit()
    return RecomputeOut(dihitung=counted, terklasifikasi=classified)
