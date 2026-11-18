"""Perhitungan nilai akhir dan klasifikasi Mahir / Cukup / Perlu Pendampingan.

Ini perhitungan berbasis ATURAN yang dapat dijelaskan, bukan machine learning.

Rumus (didokumentasikan juga di REVISION_REPORT.md):

1. Rata-rata komponen: semua nilai satu siswa pada satu komponen di satu periode dirata-rata.
   Nilai lama tanpa komponen dikelompokkan sebagai satu komponen tanpa bobot.
2. Nilai akhir per mapel: bila SEMUA komponen yang sudah dinilai untuk siswa itu memiliki bobot,
   nilai akhir = sum(rata_komponen * bobot) / sum(bobot) (bobot dinormalisasi, sehingga komponen
   yang belum dinilai tidak dihitung nol). Bila ada komponen tanpa bobot, nilai akhir = rata-rata
   biasa dari rata-rata komponen. Mapel tanpa nilai tidak punya nilai akhir (bukan nol).
3. Skor kategori (Literasi / Numerasi): langkah 2 hanya untuk komponen berkategori itu, per mapel,
   lalu dirata-rata antarmapel. Komponen tanpa kategori tidak ikut klasifikasi.
4. Skor akhir sesuai aturan periode yang ditetapkan admin:
     rata_rata -> (skor Literasi + skor Numerasi) / 2
     terendah  -> skor yang lebih rendah
   Kedua skor wajib ada; bila salah satu belum ada, siswa "belum lengkap" (tidak diklasifikasi).
5. Klasifikasi: skor_akhir >= batas_mahir -> Mahir; >= batas_cukup -> Cukup; selain itu Perlu
   Pendampingan. Tanpa aturan periode, klasifikasi tidak dihitung sama sekali.
Semua pembulatan dua desimal (ROUND_HALF_UP) agar sama dengan kolom numeric(5,2) di database.
"""

from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import (
    Absensi,
    AturanKlasifikasi,
    Kelas,
    KlasifikasiSiswa,
    KomponenPenilaian,
    MataPelajaran,
    Nilai,
    PeriodeAkademik,
    Siswa,
)
from app.models.base import KategoriNilai, Klasifikasi, StatusAbsensi
from app.schemas.academic import (
    AturanOut,
    DistribusiOut,
    JumlahKategoriOut,
    KelasDistribusiOut,
    KlasifikasiRingkasanOut,
    KehadiranRingkasOut,
    KomponenNilaiOut,
    KomponenRingkasOut,
    MapelKelasRingkasOut,
    MapelRaporOut,
    MapelRingkasOut,
    NilaiMapelSiswaOut,
    PerbandinganOut,
    PerkembanganMapelOut,
    RaporKelasOut,
    RaporOut,
    RekapOut,
    RekapSiswaOut,
    RingkasanRaporOut,
    RiwayatMapelOut,
    RiwayatPeriodeOut,
    SiswaRaporKelasOut,
    SiswaRaporOut,
)
from app.services import periods
from app.services.stats import trend_points

TWO_PLACES = Decimal("0.01")
ORDER = (Klasifikasi.MAHIR, Klasifikasi.CUKUP, Klasifikasi.PERLU_PENDAMPINGAN)
RANK = {Klasifikasi.PERLU_PENDAMPINGAN: 0, Klasifikasi.CUKUP: 1, Klasifikasi.MAHIR: 2}
NO_RULE_NOTE = (
    "Aturan klasifikasi periode ini belum ditetapkan admin, sehingga belum ada siswa yang "
    "diklasifikasi."
)
NO_PERIOD_NOTE = "Periode akademik aktif belum ditetapkan admin."


def q2(value: Decimal) -> Decimal:
    return value.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class Part:
    """Rata-rata satu komponen untuk satu siswa."""

    mapel_id: int | None
    komponen_id: int | None
    kategori: KategoriNilai | None
    bobot: Decimal | None
    average: Decimal


def final_score(parts: Iterable[Part]) -> Decimal | None:
    parts = list(parts)
    if not parts:
        return None
    if all(p.bobot is not None for p in parts):
        total_weight = sum((p.bobot for p in parts), Decimal(0))
        return q2(sum((p.average * p.bobot for p in parts), Decimal(0)) / total_weight)
    return q2(sum((p.average for p in parts), Decimal(0)) / len(parts))


def category_score(parts: Iterable[Part], kategori: KategoriNilai) -> Decimal | None:
    by_subject: dict[int | None, list[Part]] = defaultdict(list)
    for part in parts:
        if part.kategori is kategori:
            by_subject[part.mapel_id].append(part)
    scores = [final_score(group) for group in by_subject.values()]
    scores = [s for s in scores if s is not None]
    return q2(sum(scores, Decimal(0)) / len(scores)) if scores else None


def classify(
    literasi: Decimal | None, numerasi: Decimal | None, rule: AturanKlasifikasi | None
) -> tuple[Decimal | None, Klasifikasi | None]:
    if rule is None or literasi is None or numerasi is None:
        return None, None
    score = q2((literasi + numerasi) / 2) if rule.metode == "rata_rata" else min(literasi, numerasi)
    if score >= rule.batas_mahir:
        return score, Klasifikasi.MAHIR
    if score >= rule.batas_cukup:
        return score, Klasifikasi.CUKUP
    return score, Klasifikasi.PERLU_PENDAMPINGAN


def student_parts(
    db: Session, periode: PeriodeAkademik, siswa_ids: list[int] | None = None
) -> dict[int, list[Part]]:
    """Rata-rata per komponen untuk setiap siswa yang punya nilai di periode itu."""
    stmt = (
        select(
            Nilai.siswa_id,
            Nilai.mapel_id,
            Nilai.komponen_id,
            Nilai.kategori,
            KomponenPenilaian.bobot,
            func.avg(Nilai.nilai),
        )
        .outerjoin(KomponenPenilaian, KomponenPenilaian.id == Nilai.komponen_id)
        .where(Nilai.periode_id == periode.id)
        .group_by(
            Nilai.siswa_id, Nilai.mapel_id, Nilai.komponen_id, Nilai.kategori, KomponenPenilaian.bobot
        )
    )
    if siswa_ids is not None:
        stmt = stmt.where(Nilai.siswa_id.in_(siswa_ids))
    result: dict[int, list[Part]] = defaultdict(list)
    for siswa_id, mapel_id, komponen_id, kategori, bobot, average in db.execute(stmt):
        result[siswa_id].append(Part(mapel_id, komponen_id, kategori, bobot, Decimal(average)))
    return result


def get_rule(db: Session, periode: PeriodeAkademik) -> AturanKlasifikasi | None:
    return db.get(AturanKlasifikasi, periode.id)


def rule_out(rule: AturanKlasifikasi | None) -> AturanOut | None:
    if rule is None:
        return None
    return AturanOut(
        periode_id=rule.periode_id,
        metode=rule.metode,
        batas_mahir=float(rule.batas_mahir),
        batas_cukup=float(rule.batas_cukup),
        updated_at=rule.updated_at,
    )


def recompute(
    db: Session, periode: PeriodeAkademik, siswa_ids: Iterable[int] | None = None
) -> tuple[int, int]:
    """Menghitung ulang klasifikasi periode (seluruh siswa, atau sebagian). Tidak melakukan commit.

    Mengembalikan (jumlah siswa yang dihitung, jumlah yang terklasifikasi).
    """
    scope = None if siswa_ids is None else sorted(set(siswa_ids))
    if scope == []:
        return 0, 0
    rule = get_rule(db, periode)
    parts = student_parts(db, periode, scope)

    # Siswa dalam cakupan yang tidak lagi punya nilai di periode ini: hapus hasil lamanya.
    stale = delete(KlasifikasiSiswa).where(KlasifikasiSiswa.periode_id == periode.id)
    if scope is not None:
        stale = stale.where(KlasifikasiSiswa.siswa_id.in_(scope))
    if parts:
        stale = stale.where(KlasifikasiSiswa.siswa_id.not_in(list(parts)))
    db.execute(stale)

    classified = 0
    if parts:
        current_class = dict(
            db.execute(select(Siswa.id, Siswa.kelas_id).where(Siswa.id.in_(list(parts)))).all()
        )
        rows = []
        for siswa_id, student in parts.items():
            literasi = category_score(student, KategoriNilai.LITERASI)
            numerasi = category_score(student, KategoriNilai.NUMERASI)
            score, label = classify(literasi, numerasi, rule)
            classified += label is not None
            rows.append(
                {
                    "siswa_id": siswa_id,
                    "periode_id": periode.id,
                    "kelas_id": current_class.get(siswa_id),
                    "skor_literasi": literasi,
                    "skor_numerasi": numerasi,
                    "skor_akhir": score,
                    "klasifikasi": label,
                }
            )
        insert = pg_insert(KlasifikasiSiswa).values(rows)
        # Periode lama mempertahankan kelas saat itu (siswa mungkin sudah naik kelas sejak itu).
        kelas_value = (
            insert.excluded.kelas_id
            if periode.aktif
            else func.coalesce(KlasifikasiSiswa.kelas_id, insert.excluded.kelas_id)
        )
        db.execute(
            insert.on_conflict_do_update(
                index_elements=["siswa_id", "periode_id"],
                set_={
                    "kelas_id": kelas_value,
                    "skor_literasi": insert.excluded.skor_literasi,
                    "skor_numerasi": insert.excluded.skor_numerasi,
                    "skor_akhir": insert.excluded.skor_akhir,
                    "klasifikasi": insert.excluded.klasifikasi,
                    "dihitung_pada": func.now(),
                },
            )
        )

    if periode.aktif:
        sync_status_cache(db, periode, scope)
    return len(parts), classified


def sync_status_cache(db: Session, periode: PeriodeAkademik | None, scope: list[int] | None = None) -> None:
    """siswa.status_klasifikasi = klasifikasi pada periode aktif (kolom lama, dipakai API lama)."""
    stmt = select(Siswa)
    if scope is not None:
        stmt = stmt.where(Siswa.id.in_(scope))
    labels: dict[int, Klasifikasi | None] = {}
    if periode is not None:
        result_stmt = select(KlasifikasiSiswa.siswa_id, KlasifikasiSiswa.klasifikasi).where(
            KlasifikasiSiswa.periode_id == periode.id
        )
        if scope is not None:
            result_stmt = result_stmt.where(KlasifikasiSiswa.siswa_id.in_(scope))
        labels = dict(db.execute(result_stmt).all())
    for siswa in db.scalars(stmt):
        siswa.status_klasifikasi = labels.get(siswa.id)


def recompute_for_grades(db: Session, affected: Iterable[tuple[int | None, int]]) -> None:
    """Setelah nilai berubah: hitung ulang siswa terdampak di setiap periode terdampak."""
    by_period: dict[int, set[int]] = defaultdict(set)
    for periode_id, siswa_id in affected:
        if periode_id is not None:
            by_period[periode_id].add(siswa_id)
    for periode_id, siswa in by_period.items():
        recompute(db, db.get(PeriodeAkademik, periode_id), siswa)


# Ringkasan untuk chart


def _distribution(labels: list[Klasifikasi | None], tanpa_nilai: int = 0) -> DistribusiOut:
    counts = {k: 0 for k in ORDER}
    for label in labels:
        if label is not None:
            counts[label] += 1
    classified = sum(counts.values())
    return DistribusiOut(
        total_siswa=len(labels) + tanpa_nilai,
        terklasifikasi=classified,
        belum_lengkap=len(labels) - classified,
        tanpa_nilai=tanpa_nilai,
        kategori=[
            JumlahKategoriOut(
                klasifikasi=k.value,
                jumlah=counts[k],
                persen=round(counts[k] / classified * 100, 1) if classified else 0.0,
            )
            for k in ORDER
        ],
    )


def summary(
    db: Session, periode: PeriodeAkademik | None, classes: list[Kelas] | None = None
) -> KlasifikasiRingkasanOut:
    """Distribusi klasifikasi satu periode; `classes` None = seluruh sekolah.

    Populasi: siswa yang punya hasil (berdasarkan kelas saat dihitung), ditambah untuk periode
    aktif siswa kelas itu yang belum punya nilai sama sekali. Tidak ada siswa yang dihitung ganda.
    """
    if periode is None:
        return KlasifikasiRingkasanOut(
            periode=None, aturan=None, ringkasan=_distribution([]), per_kelas=[],
            perbandingan=None, catatan=NO_PERIOD_NOTE,
        )

    class_ids = None if classes is None else [k.id for k in classes]
    stmt = select(KlasifikasiSiswa.siswa_id, KlasifikasiSiswa.kelas_id, KlasifikasiSiswa.klasifikasi).where(
        KlasifikasiSiswa.periode_id == periode.id
    )
    if class_ids is not None:
        stmt = stmt.where(KlasifikasiSiswa.kelas_id.in_(class_ids))
    results = db.execute(stmt).all()

    by_class: dict[int | None, list[Klasifikasi | None]] = defaultdict(list)
    for _, kelas_id, label in results:
        by_class[kelas_id].append(label)

    without_grades: dict[int, int] = defaultdict(int)
    if periode.aktif:
        have = {siswa_id for siswa_id, _, _ in results}
        members = select(Siswa.id, Siswa.kelas_id)
        if class_ids is not None:
            members = members.where(Siswa.kelas_id.in_(class_ids))
        for siswa_id, kelas_id in db.execute(members):
            if siswa_id not in have:
                without_grades[kelas_id] += 1

    names = dict(db.execute(select(Kelas.id, Kelas.nama_kelas)).all())
    per_class = [
        KelasDistribusiOut(
            kelas=names.get(kelas_id, "Tanpa kelas"),
            **_distribution(by_class.get(kelas_id, []), without_grades.get(kelas_id, 0)).model_dump(),
        )
        for kelas_id in set(by_class) | set(without_grades)
    ]
    per_class.sort(key=lambda row: row.kelas)

    rule = get_rule(db, periode)
    return KlasifikasiRingkasanOut(
        periode=periods.period_out(periode),
        aturan=rule_out(rule),
        ringkasan=_distribution([label for _, _, label in results], sum(without_grades.values())),
        per_kelas=per_class,
        perbandingan=_comparison(db, periode, results),
        catatan=NO_RULE_NOTE if rule is None else None,
    )


def _comparison(db: Session, periode: PeriodeAkademik, results) -> PerbandinganOut | None:
    """Membandingkan siswa yang sama dengan periode sebelumnya; None bila tidak ada pembanding."""
    previous = periods.previous_period(db, periode)
    if previous is None:
        return None
    now = {siswa_id: label for siswa_id, _, label in results if label is not None}
    if not now:
        return None
    before = dict(
        db.execute(
            select(KlasifikasiSiswa.siswa_id, KlasifikasiSiswa.klasifikasi).where(
                KlasifikasiSiswa.periode_id == previous.id,
                KlasifikasiSiswa.siswa_id.in_(list(now)),
                KlasifikasiSiswa.klasifikasi.is_not(None),
            )
        ).all()
    )
    cohort = [siswa_id for siswa_id in now if siswa_id in before]
    if not cohort:
        return None
    up = sum(RANK[now[s]] > RANK[before[s]] for s in cohort)
    down = sum(RANK[now[s]] < RANK[before[s]] for s in cohort)
    return PerbandinganOut(
        periode=periods.period_out(previous),
        sebelumnya=_distribution([before[s] for s in cohort]),
        sekarang=_distribution([now[s] for s in cohort]),
        dibandingkan=len(cohort),
        naik=up,
        turun=down,
        tetap=len(cohort) - up - down,
    )


# Rekap nilai satu mapel di satu kelas


def component_summaries(components: Iterable[KomponenPenilaian]) -> list[KomponenRingkasOut]:
    return [
        KomponenRingkasOut(
            id=k.id,
            nama=k.nama,
            kategori=k.kategori.value if k.kategori else None,
            bobot=float(k.bobot) if k.bobot is not None else None,
            aktif=k.aktif,
        )
        for k in components
    ]


def subject_components(
    db: Session, periode: PeriodeAkademik, mapel_id: int
) -> list[KomponenPenilaian]:
    return list(
        db.scalars(
            select(KomponenPenilaian)
            .where(KomponenPenilaian.periode_id == periode.id, KomponenPenilaian.mapel_id == mapel_id)
            .order_by(KomponenPenilaian.urutan, KomponenPenilaian.id)
        )
    )


# Kelengkapan penilaian. "Wajib" = komponen AKTIF mapel itu di periode itu (komponen nonaktif
# tidak wajib, tetapi nilainya tetap dihitung bila ada). Nilai akhir hanya untuk status lengkap.

LENGKAP, BELUM_LENGKAP, BELUM_DINILAI, TANPA_KOMPONEN = (
    "lengkap", "belum_lengkap", "belum_dinilai", "belum_ada_komponen",
)


@dataclass(frozen=True)
class SubjectResult:
    status: str
    filled: int
    required: int
    final: Decimal | None


def subject_result(
    mapel_id: int, components: list[KomponenPenilaian], averages: dict[int, Decimal]
) -> SubjectResult:
    """`averages`: komponen_id -> rata-rata nilai siswa (hanya komponen yang sudah dinilai)."""
    counted = [k for k in components if k.aktif or k.id in averages]
    graded = [k for k in counted if k.id in averages]
    if not components:
        status = TANPA_KOMPONEN
    elif not graded:
        status = BELUM_DINILAI
    elif any(k.aktif and k.id not in averages for k in components):
        status = BELUM_LENGKAP
    else:
        status = LENGKAP
    final = None
    if status == LENGKAP:
        final = final_score(Part(mapel_id, k.id, k.kategori, k.bobot, averages[k.id]) for k in graded)
    return SubjectResult(status, len(graded), len(counted), final)


def _method(components: list[KomponenPenilaian]) -> str:
    return "berbobot" if components and all(k.bobot is not None for k in components) else "rata_rata"


def period_components(
    db: Session, periode: PeriodeAkademik, mapel_ids: Iterable[int] | None = None
) -> dict[int, list[KomponenPenilaian]]:
    stmt = select(KomponenPenilaian).where(KomponenPenilaian.periode_id == periode.id)
    if mapel_ids is not None:
        stmt = stmt.where(KomponenPenilaian.mapel_id.in_(list(mapel_ids)))
    result: dict[int, list[KomponenPenilaian]] = defaultdict(list)
    for k in db.scalars(stmt.order_by(KomponenPenilaian.urutan, KomponenPenilaian.id)):
        result[k.mapel_id].append(k)
    return result


def component_averages(
    db: Session, periode: PeriodeAkademik, siswa_ids: list[int]
) -> dict[int, dict[int, tuple[Decimal, int]]]:
    """siswa_id -> komponen_id -> (rata-rata, jumlah nilai) pada periode itu."""
    result: dict[int, dict[int, tuple[Decimal, int]]] = defaultdict(dict)
    if not siswa_ids:
        return result
    for siswa_id, komponen_id, avg, count in db.execute(
        select(Nilai.siswa_id, Nilai.komponen_id, func.avg(Nilai.nilai), func.count())
        .where(
            Nilai.periode_id == periode.id,
            Nilai.siswa_id.in_(siswa_ids),
            Nilai.komponen_id.is_not(None),
        )
        .group_by(Nilai.siswa_id, Nilai.komponen_id)
    ):
        result[siswa_id][komponen_id] = (Decimal(avg), count)
    return result


def _plain(averages: dict[int, tuple[Decimal, int]]) -> dict[int, Decimal]:
    return {k: v[0] for k, v in averages.items()}


def _float(value: Decimal | None) -> float | None:
    return float(value) if value is not None else None


def _mean(values: list[Decimal]) -> float | None:
    return float(q2(sum(values, Decimal(0)) / len(values))) if values else None


def recap(db: Session, kelas: Kelas, periode: PeriodeAkademik, mapel: MataPelajaran) -> RekapOut:
    components = subject_components(db, periode, mapel.id)
    students = list(db.scalars(select(Siswa).where(Siswa.kelas_id == kelas.id).order_by(Siswa.nama)))
    averages = component_averages(db, periode, [s.id for s in students])
    rows = []
    for siswa in students:
        own = _plain(averages.get(siswa.id, {}))
        result = subject_result(mapel.id, components, own)
        rows.append(
            RekapSiswaOut(
                siswa_id=siswa.id,
                nama=siswa.nama,
                nilai_komponen=[float(q2(own[k.id])) if k.id in own else None for k in components],
                nilai_akhir=_float(result.final),
                status=result.status,
                komponen_terisi=result.filled,
                komponen_wajib=result.required,
            )
        )
    return RekapOut(
        periode=periods.period_out(periode),
        mapel=MapelRingkasOut(id=mapel.id, kode=mapel.kode, nama=mapel.nama),
        komponen=component_summaries(components),
        metode=_method(components),
        siswa=rows,
        perkembangan=subject_progress(db, [s.id for s in students], mapel),
    )


def subject_progress(db: Session, siswa_ids: list[int], mapel: MataPelajaran) -> list[PerkembanganMapelOut]:
    """Rata-rata nilai akhir (siswa berstatus lengkap) per periode yang punya komponen mapel ini."""
    period_ids = set(
        db.scalars(select(KomponenPenilaian.periode_id).where(KomponenPenilaian.mapel_id == mapel.id))
    )
    result = []
    for periode in sorted(
        (p for p in periods.ordered_periods(db) if p.id in period_ids), key=lambda p: p.tanggal_mulai
    ):
        components = subject_components(db, periode, mapel.id)
        averages = component_averages(db, periode, siswa_ids)
        finals = [
            r.final
            for siswa_id in siswa_ids
            if (r := subject_result(mapel.id, components, _plain(averages.get(siswa_id, {})))).final
            is not None
        ]
        result.append(
            PerkembanganMapelOut(
                periode=periods.period_out(periode),
                rata_rata=_mean(finals),
                jumlah_lengkap=len(finals),
                jumlah_siswa=len(siswa_ids),
            )
        )
    return result


# Rapor (semua mata pelajaran)


def report_subjects(
    db: Session,
    level: int,
    components: dict[int, list[KomponenPenilaian]],
    graded_mapel_ids: set[int],
    only: set[int] | None,
) -> list[MataPelajaran]:
    """Mapel rapor: berlaku untuk jenjang kelas dan (aktif atau punya komponen di periode itu),
    ditambah mapel yang sudah ada nilainya. Termasuk muatan lokal. `only` membatasi (guru mapel)."""
    subjects = [
        m
        for m in db.scalars(select(MataPelajaran).order_by(MataPelajaran.urutan, MataPelajaran.nama))
        if (level in m.tingkat and (m.aktif or m.id in components)) or m.id in graded_mapel_ids
    ]
    return [m for m in subjects if only is None or m.id in only]


def _graded_subjects(components: dict[int, list[KomponenPenilaian]], own: dict[int, tuple]) -> set[int]:
    return {mapel_id for mapel_id, ks in components.items() if any(k.id in own for k in ks)}


REPORT_TREND_POINTS = 12


def attendance_summary(db: Session, siswa_id: int, periode: PeriodeAkademik | None) -> KehadiranRingkasOut:
    counts = dict(
        db.execute(
            periods.attendance_in(
                select(Absensi.status, func.count()).where(Absensi.siswa_id == siswa_id), periode
            ).group_by(Absensi.status)
        ).all()
    )
    get = lambda status: counts.get(status, 0)  # noqa: E731
    total = sum(counts.values())
    present = get(StatusAbsensi.HADIR) + get(StatusAbsensi.TERLAMBAT)
    return KehadiranRingkasOut(
        total=total, hadir=get(StatusAbsensi.HADIR), terlambat=get(StatusAbsensi.TERLAMBAT),
        izin=get(StatusAbsensi.IZIN), sakit=get(StatusAbsensi.SAKIT), alpa=get(StatusAbsensi.ALPA),
        persen_hadir=round(present / total * 100, 1) if total else None,
    )


def student_report(
    db: Session, siswa: Siswa, periode: PeriodeAkademik | None, only: set[int] | None = None
) -> RaporOut:
    level = periods.class_level(siswa.kelas)
    info = SiswaRaporOut(id=siswa.id, nama=siswa.nama, nis=siswa.nis, kelas=siswa.kelas.nama_kelas)
    history = _report_history(db, siswa, level, only)
    attendance = attendance_summary(db, siswa.id, periode)
    trends = trend_points(db, [siswa.id], REPORT_TREND_POINTS, periode)
    if periode is None:
        return RaporOut(
            siswa=info, periode=None, skor_literasi=None, skor_numerasi=None, klasifikasi=None,
            ringkasan=_report_summary([]), mapel=[], riwayat=history, nilai_tanpa_mapel=0,
            kehadiran=attendance, tren=trends, catatan=NO_PERIOD_NOTE,
        )

    components = period_components(db, periode)
    own = component_averages(db, periode, [siswa.id]).get(siswa.id, {})
    subjects = report_subjects(db, level, components, _graded_subjects(components, own), only)
    rows = []
    for m in subjects:
        ks = components.get(m.id, [])
        result = subject_result(m.id, ks, _plain(own))
        rows.append(
            MapelRaporOut(
                mapel_id=m.id, kode=m.kode, nama=m.nama, jenis=m.jenis, status=result.status,
                komponen_terisi=result.filled, komponen_wajib=result.required,
                nilai_akhir=_float(result.final), metode=_method(ks),
                komponen=[
                    KomponenNilaiOut(
                        id=k.id, nama=k.nama, kategori=k.kategori.value if k.kategori else None,
                        bobot=_float(k.bobot), aktif=k.aktif,
                        nilai=float(q2(own[k.id][0])) if k.id in own else None,
                        jumlah_nilai=own[k.id][1] if k.id in own else 0,
                    )
                    for k in ks
                    if k.aktif or k.id in own
                ],
            )
        )
    result_row = db.scalar(
        select(KlasifikasiSiswa).where(
            KlasifikasiSiswa.siswa_id == siswa.id, KlasifikasiSiswa.periode_id == periode.id
        )
    )
    legacy = db.scalar(
        select(func.count()).select_from(Nilai).where(
            Nilai.siswa_id == siswa.id, Nilai.periode_id == periode.id, Nilai.mapel_id.is_(None)
        )
    )
    rule = get_rule(db, periode)
    return RaporOut(
        siswa=info,
        periode=periods.period_out(periode),
        skor_literasi=_float(result_row.skor_literasi) if result_row else None,
        skor_numerasi=_float(result_row.skor_numerasi) if result_row else None,
        klasifikasi=result_row.klasifikasi.value if result_row and result_row.klasifikasi else None,
        ringkasan=_report_summary(rows),
        mapel=rows,
        riwayat=history,
        nilai_tanpa_mapel=legacy or 0,
        kehadiran=attendance,
        tren=trends,
        catatan=NO_RULE_NOTE if rule is None else None,
    )


def _report_summary(rows: list[MapelRaporOut]) -> RingkasanRaporOut:
    count = lambda status: sum(r.status == status for r in rows)  # noqa: E731
    finals = [Decimal(str(r.nilai_akhir)) for r in rows if r.nilai_akhir is not None]
    return RingkasanRaporOut(
        jumlah_mapel=len(rows), lengkap=count(LENGKAP), belum_lengkap=count(BELUM_LENGKAP),
        belum_dinilai=count(BELUM_DINILAI), belum_ada_komponen=count(TANPA_KOMPONEN),
        rata_rata_nilai_akhir=_mean(finals),
    )


def _report_history(
    db: Session, siswa: Siswa, level: int, only: set[int] | None
) -> list[RiwayatPeriodeOut]:
    """Setiap periode yang punya nilai siswa (berkomponen), terlama dulu."""
    period_ids = set(
        db.scalars(
            select(Nilai.periode_id).where(Nilai.siswa_id == siswa.id, Nilai.komponen_id.is_not(None)).distinct()
        )
    )
    labels = dict(
        db.execute(
            select(KlasifikasiSiswa.periode_id, KlasifikasiSiswa.klasifikasi).where(
                KlasifikasiSiswa.siswa_id == siswa.id
            )
        ).all()
    )
    history = []
    for periode in sorted(
        (p for p in periods.ordered_periods(db) if p.id in period_ids), key=lambda p: p.tanggal_mulai
    ):
        components = period_components(db, periode)
        own = _plain(component_averages(db, periode, [siswa.id]).get(siswa.id, {}))
        graded = {mapel_id for mapel_id, ks in components.items() if any(k.id in own for k in ks)}
        subjects = [
            m
            for m in db.scalars(
                select(MataPelajaran).where(MataPelajaran.id.in_(graded or {0}))
                .order_by(MataPelajaran.urutan, MataPelajaran.nama)
            )
            if only is None or m.id in only
        ]
        label = labels.get(periode.id)
        history.append(
            RiwayatPeriodeOut(
                periode=periods.period_out(periode),
                klasifikasi=label.value if label else None,
                mapel=[
                    RiwayatMapelOut(
                        mapel_id=m.id, nama=m.nama, status=(r := subject_result(m.id, components[m.id], own)).status,
                        nilai_akhir=_float(r.final),
                    )
                    for m in subjects
                ],
            )
        )
    return history


def class_report(
    db: Session, kelas: Kelas, periode: PeriodeAkademik | None, only: set[int] | None = None
) -> RaporKelasOut:
    if periode is None:
        return RaporKelasOut(periode=None, mapel=[], siswa=[], catatan=NO_PERIOD_NOTE)
    students = list(db.scalars(select(Siswa).where(Siswa.kelas_id == kelas.id).order_by(Siswa.nama)))
    components = period_components(db, periode)
    averages = component_averages(db, periode, [s.id for s in students])
    graded: set[int] = set()
    for own in averages.values():
        graded |= _graded_subjects(components, own)
    subjects = report_subjects(db, periods.class_level(kelas), components, graded, only)
    results = {
        (s.id, m.id): subject_result(m.id, components.get(m.id, []), _plain(averages.get(s.id, {})))
        for s in students
        for m in subjects
    }
    summaries = []
    for m in subjects:
        column = [results[(s.id, m.id)] for s in students]
        summaries.append(
            MapelKelasRingkasOut(
                id=m.id, kode=m.kode, nama=m.nama, jenis=m.jenis,
                lengkap=sum(r.status == LENGKAP for r in column),
                belum_lengkap=sum(r.status == BELUM_LENGKAP for r in column),
                belum_dinilai=sum(r.status in (BELUM_DINILAI, TANPA_KOMPONEN) for r in column),
                rata_rata=_mean([r.final for r in column if r.final is not None]),
            )
        )
    return RaporKelasOut(
        periode=periods.period_out(periode),
        mapel=summaries,
        siswa=[
            SiswaRaporKelasOut(
                siswa_id=s.id,
                nama=s.nama,
                nilai=[
                    NilaiMapelSiswaOut(
                        mapel_id=m.id, status=(r := results[(s.id, m.id)]).status,
                        komponen_terisi=r.filled, komponen_wajib=r.required, nilai_akhir=_float(r.final),
                    )
                    for m in subjects
                ],
            )
            for s in students
        ],
        catatan=NO_RULE_NOTE if get_rule(db, periode) is None else None,
    )
