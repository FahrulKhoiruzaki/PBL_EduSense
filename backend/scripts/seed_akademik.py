"""Data demo akademik: periode, mapel (+ contoh muatan lokal), kelas 1-6, siswa, nilai, absensi.

    python -m scripts.seed_akademik

IDEMPOTEN dan TIDAK MENGHAPUS apa pun: setiap baris dicari dulu dengan kunci alaminya (tahun ajaran
+ semester, kode mapel, kode kelas, email, NIS, nama komponen) dan hanya dibuat bila belum ada.
Nilai hanya ditambahkan untuk pasangan (siswa, komponen) yang belum punya nilai; absensi memakai
ON CONFLICT DO NOTHING. Menjalankan ulang tidak menimpa data yang sudah diubah pengguna.

Semua data FIKTIF dan hanya untuk development/pengujian (menolak berjalan bila ENVIRONMENT=production).
Tanggal periode, bobot komponen, contoh muatan lokal, dan aturan klasifikasi di sini adalah
CONTOH DEMO, bukan ketetapan sekolah. Aturan klasifikasi demo hanya dibuat bila periode itu belum
punya aturan.
"""

import random
import sys
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.database import build_engine, build_session_factory
from app.models import (
    Absensi,
    AturanKlasifikasi,
    Guru,
    Kelas,
    KomponenPenilaian,
    MapelGuru,
    MataPelajaran,
    Nilai,
    OrangTua,
    PengaturanSekolah,
    PeriodeAkademik,
    Siswa,
    User,
)
from app.models.base import KategoriNilai, MetodeInput, StatusAbsensi, UserRole
from app.services import grading_service
from app.services.auth_service import create_user, find_user_by_email

DOMAIN = "sdn02.test"
DEMO_PASSWORD = "Password123"
L, N = KategoriNilai.LITERASI, KategoriNilai.NUMERASI

# Contoh aturan untuk DEMO saja (bukan ketetapan sekolah); tidak menimpa aturan yang sudah ada.
DEMO_RULE = ("rata_rata", Decimal(80), Decimal(65))

# Template mapel umum sama dengan migrasi 005; dibuat ulang bila tidak ada (mis. database lama).
SUBJECTS = [
    ("PABP", "Pendidikan Agama dan Budi Pekerti", "umum", (1, 2, 3, 4, 5, 6), True, 10),
    ("PP", "Pendidikan Pancasila", "umum", (1, 2, 3, 4, 5, 6), True, 20),
    ("BIN", "Bahasa Indonesia", "umum", (1, 2, 3, 4, 5, 6), True, 30),
    ("MTK", "Matematika", "umum", (1, 2, 3, 4, 5, 6), True, 40),
    ("IPAS", "Ilmu Pengetahuan Alam dan Sosial", "umum", (3, 4, 5, 6), True, 50),
    ("SBD", "Seni dan Budaya", "umum", (1, 2, 3, 4, 5, 6), True, 60),
    ("PJOK", "Pendidikan Jasmani, Olahraga, dan Kesehatan", "umum", (1, 2, 3, 4, 5, 6), True, 70),
    ("BING", "Bahasa Inggris", "umum", (1, 2, 3, 4, 5, 6), False, 80),
    # Contoh muatan lokal untuk DEMO; daftar resmi ditetapkan sekolah lewat menu admin.
    ("BJAWA", "Bahasa Jawa", "muatan_lokal", (1, 2, 3, 4, 5, 6), True, 90),
]
DEMO_LOCAL_NOTE = "Contoh muatan lokal (data demo). Sesuaikan dengan ketetapan sekolah."

# (nama komponen, kategori, bobot demo). Literasi dari Bahasa Indonesia, Numerasi dari Matematika;
# mapel lain tidak masuk klasifikasi. Bobot hanya contoh untuk menguji perhitungan berbobot.
COMPONENTS = {
    "BIN": [("Tugas", L, 30), ("Ulangan Harian", L, 30), ("Asesmen Sumatif", L, 40)],
    "MTK": [("Tugas", N, 30), ("Ulangan Harian", N, 30), ("Asesmen Sumatif", N, 40)],
    "IPAS": [("Tugas", None, None), ("Proyek", None, None)],
    "PP": [("Tugas", None, None)],
    "SBD": [("Karya", None, None)],
    "PJOK": [("Praktik", None, None)],
    "PABP": [("Tugas", None, None)],
    "BJAWA": [("Tugas", None, None), ("Ulangan Harian", None, None)],
}
GRADES_PER_COMPONENT = {"BIN": 2, "MTK": 2}  # lainnya satu nilai per komponen

CLASSES = ["1A", "2A", "3A", "4A", "5A", "5B", "6A"]
CORE = ("BIN", "MTK", "PP", "SBD", "IPAS")


@dataclass(frozen=True)
class GuruSpec:
    key: str
    nama: str
    jabatan: str
    wali: str | None
    # (kelas, kode mapel)
    teaches: tuple[tuple[str, str], ...]


def _core(kelas: str, *codes: str) -> tuple[tuple[str, str], ...]:
    level = int(kelas[0])
    return tuple((kelas, c) for c in codes if c != "IPAS" or level >= 3)


# Guru demo tambahan; akun rina/andi/sari dibuat seeder utama (scripts.seed) dan dipakai bila ada.
GURU = [
    GuruSpec("wati", "Bu Wati Handayani", "Wali Kelas 1A", "1A", _core("1A", *CORE)),
    GuruSpec("joko", "Pak Joko Susilo", "Wali Kelas 2A", "2A", _core("2A", *CORE)),
    GuruSpec("lina", "Bu Lina Marlina", "Wali Kelas 3A", "3A", _core("3A", *CORE)),
    GuruSpec("bayu", "Pak Bayu Saputra", "Wali Kelas 4A", "4A", _core("4A", *CORE)),
    GuruSpec("dewi", "Bu Dewi Anggraini", "Wali Kelas 6A", "6A", _core("6A", *CORE)),
    GuruSpec("agus", "Pak Agus Firmansyah", "Guru PJOK", None, tuple((k, "PJOK") for k in CLASSES)),
    GuruSpec("nur", "Bu Nur Hidayah", "Guru Pendidikan Agama", None, tuple((k, "PABP") for k in CLASSES)),
    GuruSpec("maya", "Bu Maya Sari", "Guru Muatan Lokal", None, tuple((k, "BJAWA") for k in CLASSES)),
]
# Penugasan mapel untuk guru dari seeder utama (wali 5A/5B tetap hanya melihat kelasnya sendiri).
EXISTING_TEACHES = {
    "andi": (("5A", "BIN"), ("5A", "MTK"), ("5A", "SBD"), ("5B", "BIN"), ("5B", "MTK"), ("5B", "SBD")),
    "rina": (("5B", "IPAS"), ("5B", "PP")),
    "sari": (("5A", "IPAS"), ("5A", "PP")),
}


@dataclass(frozen=True)
class Profile:
    """Pola nilai/absensi siswa demo. `trend` = perubahan rata-rata per semester."""

    literasi: int
    numerasi: int
    trend: int = 0
    hadir: float = 0.9
    no_grades_now: bool = False      # belum punya nilai di periode aktif
    no_attendance_now: bool = False  # belum punya absensi di periode aktif
    numerasi_only_now: bool = False  # data periode aktif belum lengkap (hanya Numerasi)
    drop_last: bool = False          # nilai terbaru turun tajam (penanda "menurun")


HIGH, GOOD, MID, LOWMID, LOW = (
    Profile(90, 88, hadir=0.97), Profile(82, 80), Profile(74, 71, hadir=0.88),
    Profile(68, 64, hadir=0.85), Profile(56, 54, hadir=0.65),
)
UP, DOWN = Profile(60, 62, trend=9, hadir=0.9), Profile(84, 82, trend=-10, hadir=0.75, drop_last=True)

FIRST = ["Aditya", "Bunga", "Cahyo", "Dinda", "Fajar", "Gita", "Hana", "Irfan", "Jihan", "Kevin",
         "Laras", "Mira", "Naufal", "Oktavia", "Putra", "Rani", "Satria", "Tiara", "Umar", "Vina",
         "Wahyu", "Yusuf", "Zahra", "Alya", "Bagas", "Citra", "Danu", "Elsa", "Farel", "Galih",
         "Indah", "Johan", "Kirana", "Lutfi", "Melati", "Nanda", "Raka", "Salma", "Tegar", "Wulan",
         "Yoga", "Zaki"]
LAST = ["Pratama", "Lestari", "Nugroho", "Wibowo", "Rahmawati", "Saputra", "Kurniawan", "Puspita",
        "Hidayat", "Maharani", "Setiawan", "Permata", "Santoso", "Utami"]
# Siswa tambahan: 7 per kelas baru, 3 lagi untuk 5A/5B (yang sudah punya 4 dari seeder utama).
NEW_CLASS_PROFILES = [HIGH, GOOD, MID, LOWMID, LOW, UP, DOWN]
EXTRA_5_PROFILES = [GOOD, UP, LOWMID]
SPECIAL = {
    ("3A", 4): Profile(56, 54, hadir=0.7, no_grades_now=True),
    ("2A", 3): Profile(68, 64, no_attendance_now=True),
    ("1A", 6): Profile(70, 70, numerasi_only_now=True),
}
# Profil siswa seeder utama (berdasarkan NIS) agar pola lamanya tetap terlihat.
BASE_PROFILES = {
    "2024001": Profile(80, 73, trend=2, hadir=0.80),
    "2024002": HIGH,
    "2024003": Profile(64, 58, trend=-6, hadir=0.60, drop_last=True),
    "2024004": Profile(81, 72, hadir=0.88),
    "2024005": Profile(74, 77, trend=4, hadir=0.85),
    "2024006": Profile(86, 84, trend=3, hadir=0.95),
    "2024007": LOW,
    "2024008": Profile(78, 81, hadir=0.90),
}
SIBLINGS = {("4A", 0): ("2A", 0)}  # siswa 4A pertama adik-kakak dengan siswa 2A pertama


def school_year_start(today: date) -> int:
    return today.year if today.month >= 7 else today.year - 1


def demo_periods(today: date) -> list[tuple[str, int, date, date]]:
    """Tiga periode yang sudah berjalan + semester berikutnya. Tanggal hanya contoh demo."""
    y = school_year_start(today)

    def ganjil(start: int):
        return (f"{start}/{start + 1}", 1, date(start, 7, 13), date(start, 12, 20))

    def genap(start: int):
        return (f"{start}/{start + 1}", 2, date(start + 1, 1, 5), date(start + 1, 6, 20))

    return [ganjil(y - 1), genap(y - 1), ganjil(y), genap(y)]


def school_days(start: date, end: date) -> list[date]:
    days, cursor = [], start
    while cursor <= end:
        if cursor.weekday() < 5:
            days.append(cursor)
        cursor += timedelta(days=1)
    return days


class Report:
    def __init__(self) -> None:
        self.counts: dict[str, int] = {}
        self.notes: list[str] = []

    def add(self, key: str, n: int = 1) -> None:
        self.counts[key] = self.counts.get(key, 0) + n


# Data master


def ensure_periods(db: Session, today: date, r: Report) -> list[PeriodeAkademik]:
    result = []
    for tahun, semester, start, end in demo_periods(today):
        periode = db.scalar(
            select(PeriodeAkademik).where(
                PeriodeAkademik.tahun_ajaran == tahun, PeriodeAkademik.semester == semester
            )
        )
        if periode is None:
            clash = db.scalar(
                select(PeriodeAkademik).where(
                    PeriodeAkademik.tanggal_mulai <= end, PeriodeAkademik.tanggal_selesai >= start
                )
            )
            if clash is not None:
                r.notes.append(
                    f"Periode {tahun} semester {semester} dilewati: bertumpang tindih dengan {clash.label}."
                )
                continue
            periode = PeriodeAkademik(tahun_ajaran=tahun, semester=semester, tanggal_mulai=start,
                                      tanggal_selesai=end)
            db.add(periode)
            db.flush()
            r.add("periode")
        result.append(periode)

    if db.scalar(select(PeriodeAkademik).where(PeriodeAkademik.aktif)) is None:
        started = [p for p in result if p.tanggal_mulai <= today]
        if started:
            current = max(started, key=lambda p: p.tanggal_mulai)
            current.aktif = True
            db.flush()
            db.get(PengaturanSekolah, True).tahun_ajaran = current.tahun_ajaran
            r.notes.append(f"{current.label} ditetapkan sebagai periode aktif.")
    return result


def ensure_subjects(db: Session, r: Report) -> dict[str, MataPelajaran]:
    subjects = {}
    for kode, nama, jenis, tingkat, aktif, urutan in SUBJECTS:
        mapel = db.scalar(select(MataPelajaran).where(MataPelajaran.kode == kode))
        if mapel is None:
            mapel = db.scalar(select(MataPelajaran).where(func.lower(MataPelajaran.nama) == nama.lower()))
        if mapel is None:
            mapel = MataPelajaran(
                kode=kode, nama=nama, jenis=jenis, tingkat=list(tingkat), aktif=aktif, urutan=urutan,
                deskripsi=DEMO_LOCAL_NOTE if jenis == "muatan_lokal" else "Template awal.",
            )
            db.add(mapel)
            db.flush()
            r.add("mapel")
        subjects[kode] = mapel
    return subjects


def ensure_classes(db: Session, r: Report) -> dict[str, Kelas]:
    classes = {}
    for code in CLASSES:
        kelas = db.scalar(select(Kelas).where(Kelas.nama_kelas == code))
        if kelas is None:
            kelas = Kelas(nama_kelas=code)
            db.add(kelas)
            db.flush()
            r.add("kelas")
        classes[code] = kelas
    return classes


def guru_by_key(db: Session, key: str) -> Guru | None:
    user = find_user_by_email(db, f"{key}@{DOMAIN}")
    return user.guru_profile if user is not None and user.role is UserRole.GURU else None


def ensure_teachers(
    db: Session, classes: dict[str, Kelas], subjects: dict[str, MataPelajaran], r: Report
) -> None:
    plan: list[tuple[Guru, tuple[tuple[str, str], ...]]] = []
    for spec in GURU:
        guru = guru_by_key(db, spec.key)
        if guru is None:
            user = create_user(
                db, role=UserRole.GURU, email=f"{spec.key}@{DOMAIN}", nama=spec.nama,
                password=DEMO_PASSWORD, must_change_password=False, commit=False,
            )
            guru = user.guru_profile
            guru.jabatan, guru.tampil_publik = spec.jabatan, True
            r.add("guru")
        if spec.wali and classes[spec.wali].wali_kelas_id is None:
            # Satu guru hanya wali satu kelas (UNIQUE): lewati bila guru sudah wali kelas lain.
            if db.scalar(select(Kelas.id).where(Kelas.wali_kelas_id == guru.id)) is None:
                classes[spec.wali].wali_kelas_id = guru.id
        plan.append((guru, spec.teaches))
    for key, teaches in EXISTING_TEACHES.items():
        guru = guru_by_key(db, key)
        if guru is not None:
            plan.append((guru, teaches))
    db.flush()

    for guru, teaches in plan:
        for code, kode in teaches:
            kelas, mapel = classes[code], subjects[kode]
            if int(code[0]) not in mapel.tingkat:
                continue
            exists = db.scalar(select(MapelGuru.id).where(
                MapelGuru.guru_id == guru.id, MapelGuru.kelas_id == kelas.id,
                MapelGuru.mapel_id == mapel.id,
            ))
            if exists is None:
                db.add(MapelGuru(guru_id=guru.id, kelas_id=kelas.id, mapel_id=mapel.id))
                r.add("penugasan")
    db.flush()


def _nis(code: str, index: int) -> str:
    """NIS demo deterministik: 26 + tingkat + rombel (A=1, B=2) + urutan."""
    return f"26{code[0]}{ord(code[1]) - 64}{index:02d}"


def ensure_students(db: Session, classes: dict[str, Kelas], r: Report) -> dict[int, Profile]:
    """Melengkapi siswa tiap kelas; mengembalikan profil nilai per id siswa demo."""
    rng = random.Random(2027)
    names = iter(rng.sample([f"{f} {last}" for f in FIRST for last in LAST], 200))
    profiles: dict[int, Profile] = {}
    parents: dict[tuple[str, int], OrangTua] = {}

    for code in CLASSES:
        if code in ("5A", "5B"):
            plan = [(i + 4, p) for i, p in enumerate(EXTRA_5_PROFILES)]
        else:
            plan = list(enumerate(NEW_CLASS_PROFILES))
        for index, profile in plan:
            nis, name = _nis(code, index), next(names)
            profile = SPECIAL.get((code, index), profile)
            siswa = db.scalar(select(Siswa).where(Siswa.nis == nis))
            if siswa is None:
                sibling = SIBLINGS.get((code, index))
                parent = parents.get(sibling) if sibling else None
                if parent is None:
                    parent = _ensure_parent(db, nis, name, r)
                siswa = Siswa(nis=nis, nama=name, kelas_id=classes[code].id, orang_tua_id=parent.id)
                db.add(siswa)
                db.flush()
                r.add("siswa")
            parents[(code, index)] = siswa.orang_tua
            profiles[siswa.id] = profile

    for nis, profile in BASE_PROFILES.items():
        siswa = db.scalar(select(Siswa).where(Siswa.nis == nis))
        if siswa is not None:
            profiles[siswa.id] = profile
    return profiles


def _ensure_parent(db: Session, nis: str, child: str, r: Report) -> OrangTua:
    email = f"ortu.{nis}@{DOMAIN}"
    user = find_user_by_email(db, email)
    if user is not None:
        return user.ortu_profile
    user = create_user(
        db, role=UserRole.ORTU, email=email, nama=f"Keluarga {child.split()[-1]}",
        password=DEMO_PASSWORD, must_change_password=False, commit=False,
    )
    r.add("orang_tua")
    return user.ortu_profile


# Data transaksi


def ensure_components(
    db: Session, periods: list[PeriodeAkademik], subjects: dict[str, MataPelajaran], r: Report
) -> dict[tuple[int, str], list[KomponenPenilaian]]:
    result: dict[tuple[int, str], list[KomponenPenilaian]] = {}
    for periode in periods:
        for kode, specs in COMPONENTS.items():
            mapel = subjects[kode]
            rows = []
            for order, (nama, kategori, bobot) in enumerate(specs, start=1):
                komponen = db.scalar(select(KomponenPenilaian).where(
                    KomponenPenilaian.periode_id == periode.id,
                    KomponenPenilaian.mapel_id == mapel.id,
                    func.lower(KomponenPenilaian.nama) == nama.lower(),
                ))
                if komponen is None:
                    komponen = KomponenPenilaian(
                        periode_id=periode.id, mapel_id=mapel.id, kategori=kategori, nama=nama,
                        bobot=Decimal(bobot) if bobot else None, urutan=order * 10,
                        deskripsi="Komponen demo.",
                    )
                    db.add(komponen)
                    db.flush()
                    r.add("komponen")
                rows.append(komponen)
            result[(periode.id, kode)] = rows
    return result


def _score(rng: random.Random, base: int, trend: int, step: int, frac: float) -> Decimal:
    value = base + trend * step + trend * 0.3 * frac + rng.uniform(-4, 4)
    return Decimal(max(0, min(100, round(value))))


def seed_grades(
    db: Session,
    periods: list[PeriodeAkademik],
    components: dict[tuple[int, str], list[KomponenPenilaian]],
    profiles: dict[int, Profile],
    today: date,
    tz,
    r: Report,
) -> None:
    active = db.scalar(select(PeriodeAkademik).where(PeriodeAkademik.aktif))
    started = sorted((p for p in periods if p.tanggal_mulai < today), key=lambda p: p.tanggal_mulai)
    students = {s.id: s for s in db.scalars(select(Siswa).where(Siswa.id.in_(list(profiles))))}
    graded = set(
        db.execute(select(Nilai.siswa_id, Nilai.komponen_id).where(Nilai.komponen_id.is_not(None))).all()
    )
    teachers = {
        (kelas_id, mapel_id): guru_id
        for guru_id, kelas_id, mapel_id in db.execute(
            select(MapelGuru.guru_id, MapelGuru.kelas_id, MapelGuru.mapel_id)
            .where(MapelGuru.mapel_id.is_not(None))
        )
    }

    for step, periode in enumerate(started):
        is_current = active is not None and periode.id == active.id
        last_day = min(periode.tanggal_selesai, today - timedelta(days=1))
        days = school_days(periode.tanggal_mulai + timedelta(days=7), last_day)
        if not days:
            continue
        semesters_ago = step - (len(started) - 1)  # 0 = periode terbaru, negatif = lebih lama
        for siswa_id, profile in profiles.items():
            siswa = students[siswa_id]
            level = int(siswa.kelas.nama_kelas[0])
            if is_current and profile.no_grades_now:
                continue
            rng = random.Random(f"{siswa.nis}-{periode.id}")
            for kode in COMPONENTS:
                if is_current and profile.numerasi_only_now and kode != "MTK":
                    continue
                rows = components[(periode.id, kode)]
                if level not in rows[0].mapel.tingkat:
                    continue
                base = profile.numerasi if kode == "MTK" else profile.literasi
                count = GRADES_PER_COMPONENT.get(kode, 1)
                for c_index, komponen in enumerate(rows):
                    if (siswa_id, komponen.id) in graded:
                        continue
                    for g in range(count):
                        frac = (c_index * count + g + 1) / (len(rows) * count + 1)
                        day = days[min(len(days) - 1, int(frac * (len(days) - 1)))]
                        value = _score(rng, base, profile.trend, semesters_ago, frac)
                        is_last = c_index == len(rows) - 1 and g == count - 1
                        if profile.drop_last and is_current and is_last and kode == "BIN":
                            value = max(Decimal(0), value - 12)
                        when = datetime.combine(day, time(10, 0), tzinfo=tz)
                        db.add(Nilai(
                            siswa_id=siswa_id, komponen_id=komponen.id, jenis_ujian=komponen.nama,
                            nilai=value, tanggal=day,
                            catatan_guru="Perlu latihan tambahan." if value < 60 else None,
                            dicatat_oleh=teachers.get((siswa.kelas_id, komponen.mapel_id)),
                            created_at=when, updated_at=when,
                        ))
                        r.add("nilai")
    db.flush()


def seed_attendance(
    db: Session, periods: list[PeriodeAkademik], profiles: dict[int, Profile], today: date, tz, r: Report
) -> None:
    """Absensi demo per periode (maks. 45 hari sekolah terakhir tiap periode). Hari ini kosong."""
    active = db.scalar(select(PeriodeAkademik).where(PeriodeAkademik.aktif))
    students = {s.id: s for s in db.scalars(select(Siswa).where(Siswa.id.in_(list(profiles))))}
    homeroom = dict(db.execute(select(Kelas.id, Kelas.wali_kelas_id)).all())
    for periode in periods:
        if periode.tanggal_mulai >= today:
            continue
        end = min(periode.tanggal_selesai, today - timedelta(days=1))
        days = school_days(periode.tanggal_mulai, end)[-45:]
        is_current = active is not None and periode.id == active.id
        rows = []
        for siswa_id, profile in profiles.items():
            if is_current and profile.no_attendance_now:
                continue
            siswa = students[siswa_id]
            rng = random.Random(f"absen-{siswa.nis}-{periode.id}")
            for day in days:
                roll = rng.random()
                if roll < profile.hadir:
                    status, clock = StatusAbsensi.HADIR, time(6, rng.randint(40, 59), rng.randint(0, 59))
                elif roll < profile.hadir + (1 - profile.hadir) * 0.5:
                    status, clock = StatusAbsensi.TERLAMBAT, time(7, rng.randint(16, 40), rng.randint(0, 59))
                else:
                    status = rng.choice([StatusAbsensi.IZIN, StatusAbsensi.SAKIT, StatusAbsensi.ALPA])
                    clock = None
                when = datetime.combine(day, clock or time(8, 0), tzinfo=tz)
                rows.append({
                    "siswa_id": siswa_id, "tanggal": day, "waktu": clock, "status": status,
                    "metode_input": MetodeInput.MANUAL, "dicatat_oleh": homeroom.get(siswa.kelas_id),
                    "catatan": "Keterangan dari orang tua." if status is StatusAbsensi.IZIN else None,
                    "created_at": when, "updated_at": when,
                })
        for start in range(0, len(rows), 2000):
            inserted = db.execute(
                pg_insert(Absensi).values(rows[start:start + 2000])
                .on_conflict_do_nothing(index_elements=["siswa_id", "tanggal"])
                .returning(Absensi.id)
            ).all()
            if inserted:
                r.add("absensi", len(inserted))
    db.flush()


def ensure_demo_rules(db: Session, periods: list[PeriodeAkademik], r: Report) -> None:
    metode, mahir, cukup = DEMO_RULE
    for periode in periods:
        if db.get(AturanKlasifikasi, periode.id) is None:
            db.add(AturanKlasifikasi(periode_id=periode.id, metode=metode, batas_mahir=mahir,
                                     batas_cukup=cukup))
            r.add("aturan_demo")
    db.flush()


def populate_academic(db: Session, tz, today: date | None = None, *, commit: bool = True) -> Report:
    """Mengisi data akademik demo dalam satu transaksi. Aman dijalankan berulang kali."""
    today = today or datetime.now(tz).date()
    r = Report()
    try:
        periods = ensure_periods(db, today, r)
        subjects = ensure_subjects(db, r)
        classes = ensure_classes(db, r)
        ensure_teachers(db, classes, subjects, r)
        profiles = ensure_students(db, classes, r)
        components = ensure_components(db, periods, subjects, r)
        seed_grades(db, periods, components, profiles, today, tz, r)
        seed_attendance(db, periods, profiles, today, tz, r)
        ensure_demo_rules(db, periods, r)
        for periode in periods:
            grading_service.recompute(db, periode)
        if commit:
            db.commit()
    except Exception:
        db.rollback()
        raise
    return r


def main() -> int:
    settings = get_settings()
    if settings.is_production:
        print("Menolak: seeder hanya untuk development (ENVIRONMENT=production).", file=sys.stderr)
        return 1
    engine = build_engine(settings.database_url)
    with build_session_factory(engine)() as db:
        if db.scalar(text("SELECT to_regclass('public.periode_akademik')")) is None:
            print("Tabel akademik belum ada. Jalankan dulu: python -m scripts.init_db", file=sys.stderr)
            return 1
        report = populate_academic(db, settings.tzinfo)
        totals = {
            "siswa": db.scalar(select(func.count()).select_from(Siswa)),
            "kelas": db.scalar(select(func.count()).select_from(Kelas)),
            "nilai": db.scalar(select(func.count()).select_from(Nilai)),
            "absensi": db.scalar(select(func.count()).select_from(Absensi)),
            "akun": db.scalar(select(func.count()).select_from(User)),
        }
    added = ", ".join(f"{k} {v}" for k, v in sorted(report.counts.items())) or "tidak ada (sudah lengkap)"
    print(f"Ditambahkan: {added}.")
    print("Total sekarang: " + ", ".join(f"{k} {v}" for k, v in totals.items()) + ".")
    for note in report.notes:
        print(f"Catatan: {note}")
    if report.counts.get("aturan_demo"):
        print("PERHATIAN: aturan klasifikasi demo (rata-rata, Mahir >= 80, Cukup >= 65) hanya contoh; "
              "tetapkan aturan resmi lewat menu admin Klasifikasi.")
    print(f"Akun guru/orang tua demo baru memakai password {DEMO_PASSWORD}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
