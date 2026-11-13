from datetime import date, timedelta, tzinfo

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import not_found
from app.models import Absensi, Nilai, OrangTua, PengaturanSekolah, RiwayatKlasifikasi, Siswa
from app.models.base import KategoriNilai, StatusAbsensi
from app.schemas.parent import (
    AnakOut,
    KehadiranHariOut,
    NilaiAnakOut,
    RiwayatItemOut,
    RiwayatKlasifikasiOut,
    TrenAnakOut,
)
from app.services.guru_service import AUTO_ALPA_NOTE
from app.services.stats import (
    MONTHS_ID,
    PRESENT,
    STATUS_LABEL,
    academic_year_start,
    grade_rows,
    round_int,
    weekly_attendance_trend,
    weekly_grade_trend,
)

TREND_POINTS = 12
CLASSIFICATION_MONTHS = 6
GRADE_LIMIT = 300
HISTORY_LIMIT = 150
ATTENDANCE_WINDOW = timedelta(days=366)


def get_children(db: Session, ortu: OrangTua) -> list[Siswa]:
    return list(db.scalars(select(Siswa).where(Siswa.orang_tua_id == ortu.id).order_by(Siswa.id)))


def get_child(db: Session, ortu: OrangTua, siswa_id: int) -> Siswa:
    siswa = db.get(Siswa, siswa_id)
    # 404 (bukan 403) agar keberadaan siswa milik orang lain tidak terbuka.
    if siswa is None or siswa.orang_tua_id != ortu.id:
        raise not_found("Data anak tidak ditemukan.")
    return siswa


def _tahun_ajaran(db: Session) -> str:
    return db.scalar(select(PengaturanSekolah.tahun_ajaran)) or ""


def _month_label(periode: date, today: date) -> str:
    name = MONTHS_ID[periode.month - 1]
    return name if periode.year == today.year else f"{name} {periode.year}"


def _classification_history(db: Session, siswa: Siswa) -> list[RiwayatKlasifikasi]:
    rows = db.scalars(
        select(RiwayatKlasifikasi)
        .where(RiwayatKlasifikasi.siswa_id == siswa.id)
        .order_by(RiwayatKlasifikasi.periode.desc())
        .limit(CLASSIFICATION_MONTHS)
    ).all()
    return list(reversed(rows))


def child_overview(db: Session, siswa: Siswa, *, today: date, tz: tzinfo) -> AnakOut:
    tahun_ajaran = _tahun_ajaran(db)
    year_start = academic_year_start(tahun_ajaran, today)

    averages = dict(
        db.execute(
            select(Nilai.kategori, func.avg(Nilai.nilai))
            .where(Nilai.siswa_id == siswa.id)
            .group_by(Nilai.kategori)
        ).all()
    )
    present, late, total = db.execute(
        select(
            func.count(Absensi.id).filter(Absensi.status.in_(PRESENT)),
            func.count(Absensi.id).filter(Absensi.status == StatusAbsensi.TERLAMBAT),
            func.count(Absensi.id),
        ).where(Absensi.siswa_id == siswa.id, Absensi.tanggal >= year_start, Absensi.tanggal <= today)
    ).one()

    ids = [siswa.id]
    history = _classification_history(db, siswa)
    if not history and siswa.status_klasifikasi is not None:
        history_out = [
            RiwayatKlasifikasiOut(
                bulan=_month_label(today, today), klasifikasi=siswa.status_klasifikasi.value
            )
        ]
    else:
        history_out = [
            RiwayatKlasifikasiOut(
                bulan=_month_label(h.periode, today), klasifikasi=h.klasifikasi.value
            )
            for h in history
        ]

    last_change = max(
        filter(
            None,
            [
                siswa.updated_at,
                db.scalar(select(func.max(Nilai.updated_at)).where(Nilai.siswa_id == siswa.id)),
                db.scalar(select(func.max(Absensi.updated_at)).where(Absensi.siswa_id == siswa.id)),
            ],
        )
    )
    wali = siswa.kelas.wali

    return AnakOut(
        id=siswa.id,
        nis=siswa.nis,
        nama=siswa.nama,
        kelas=siswa.kelas.nama_kelas,
        klasifikasi=siswa.status_klasifikasi.value if siswa.status_klasifikasi else None,
        literasi=round_int(averages.get(KategoriNilai.LITERASI)),
        numerasi=round_int(averages.get(KategoriNilai.NUMERASI)),
        persen_kehadiran=round(present / total * 100) if total else 0,
        jumlah_terlambat=late,
        tren=TrenAnakOut(
            literasi=weekly_grade_trend(db, ids, KategoriNilai.LITERASI, TREND_POINTS),
            numerasi=weekly_grade_trend(db, ids, KategoriNilai.NUMERASI, TREND_POINTS),
            kehadiran=weekly_attendance_trend(db, ids, TREND_POINTS),
        ),
        riwayat_klasifikasi=history_out,
        nilai=[
            NilaiAnakOut(
                id=r.id,
                kategori=r.kategori.value,
                jenis_ujian=r.jenis_ujian,
                nilai=float(r.nilai),
                nilai_sebelumnya=float(r.prev) if r.prev is not None else None,
                tanggal=r.tanggal,
                catatan_guru=r.catatan_guru,
            )
            for r in grade_rows(db, ids, GRADE_LIMIT)
        ],
        wali_kelas=wali.nama if wali else None,
        tahun_ajaran=tahun_ajaran,
        diperbarui=last_change.astimezone(tz).replace(tzinfo=None),
    )


def attendance_days(db: Session, siswa: Siswa, *, today: date) -> list[KehadiranHariOut]:
    rows = db.execute(
        select(Absensi.tanggal, Absensi.status, Absensi.waktu, Absensi.catatan)
        .where(Absensi.siswa_id == siswa.id, Absensi.tanggal >= today - ATTENDANCE_WINDOW)
        .order_by(Absensi.tanggal)
    ).all()
    return [
        KehadiranHariOut(
            tanggal=tanggal,
            status=status.value,
            waktu=str(waktu) if waktu else None,
            catatan=None if catatan == AUTO_ALPA_NOTE else catatan,
        )
        for tanggal, status, waktu, catatan in rows
    ]


def history(db: Session, siswa: Siswa) -> list[RiwayatItemOut]:
    items: list[RiwayatItemOut] = []

    for r in grade_rows(db, [siswa.id], HISTORY_LIMIT):
        value = round_int(r.nilai)
        if r.catatan_guru:
            note = r.catatan_guru
        elif r.prev is None:
            note = "Nilai pertama untuk kategori ini."
        else:
            delta = round_int(r.nilai) - round_int(r.prev)
            note = (
                f"Naik {delta} poin dari nilai sebelumnya." if delta > 0
                else f"Turun {-delta} poin dari nilai sebelumnya." if delta < 0
                else "Sama dengan nilai sebelumnya."
            )
        items.append(
            RiwayatItemOut(
                jenis="nilai", tanggal=r.tanggal, judul=f"{r.kategori.value} {value}", keterangan=note
            )
        )

    attendance = db.execute(
        select(Absensi.tanggal, Absensi.status, Absensi.waktu, Absensi.catatan)
        .where(Absensi.siswa_id == siswa.id, Absensi.status != StatusAbsensi.HADIR)
        .order_by(Absensi.tanggal.desc())
        .limit(HISTORY_LIMIT)
    ).all()
    for tanggal, status, waktu, catatan in attendance:
        if catatan and catatan != AUTO_ALPA_NOTE:
            note = catatan
        elif status is StatusAbsensi.TERLAMBAT and waktu:
            note = f"Tiba pukul {waktu.strftime('%H:%M')}."
        else:
            note = ""
        items.append(
            RiwayatItemOut(jenis="kehadiran", tanggal=tanggal, judul=STATUS_LABEL[status], keterangan=note)
        )

    ordered = list(
        db.scalars(
            select(RiwayatKlasifikasi)
            .where(RiwayatKlasifikasi.siswa_id == siswa.id)
            .order_by(RiwayatKlasifikasi.periode)
        )
    )
    for index, row in enumerate(ordered):
        if index == 0:
            note = "Klasifikasi pertama yang tercatat."
        elif ordered[index - 1].klasifikasi == row.klasifikasi:
            note = "Tidak berubah dari bulan lalu."
        else:
            note = f"Berubah dari {ordered[index - 1].klasifikasi.value} pada bulan lalu."
        items.append(
            RiwayatItemOut(
                jenis="klasifikasi", tanggal=row.periode, judul=row.klasifikasi.value, keterangan=note
            )
        )

    items.sort(key=lambda i: i.tanggal, reverse=True)
    return items[:HISTORY_LIMIT]
