"""Data awal untuk test manual: akun, kelas, siswa, absensi, nilai, notifikasi, dan konten website.

    python -m scripts.seed                 # isi database yang masih kosong
    python -m scripts.seed --reset         # KOSONGKAN semua data lalu isi ulang (minta konfirmasi)

Hanya untuk development: menolak berjalan bila ENVIRONMENT=production. Semua akun demo memakai
password yang sama (lihat DEMO_PASSWORD) kecuali satu guru yang sengaja masih memakai password
sementara agar alur "wajib ganti password" bisa dicoba. Absensi hari ini sengaja dikosongkan.
"""

import argparse
import random
import sys
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.database import build_engine, build_session_factory
from app.models import (
    Absensi,
    Berita,
    Fasilitas,
    Faq,
    Guru,
    HalamanSitus,
    InformasiKelas,
    KalenderAkademik,
    Kegiatan,
    Kelas,
    LogAktivitas,
    MapelGuru,
    Nilai,
    Notifikasi,
    OrangTua,
    PengaturanSekolah,
    Pengumuman,
    ProfilSekolah,
    RiwayatKlasifikasi,
    Siswa,
    User,
)
from app.models.base import (
    BeritaKategori,
    FaqKategori,
    KategoriNilai,
    KegiatanKategori,
    Klasifikasi,
    KontenStatus,
    LogTipe,
    MetodeInput,
    StatusAbsensi,
    UserRole,
)
from app.services import cms_pages
from app.services.auth_service import create_user

DOMAIN = "sdn02.test"
DEMO_PASSWORD = "Password123"
TEMP_PASSWORD = "Sementara123"
ADMIN_EMAIL = f"admin@{DOMAIN}"
SINGLETONS = {"pengaturan_sekolah", "profil_sekolah"}

M, C, P = Klasifikasi.MAHIR, Klasifikasi.CUKUP, Klasifikasi.PERLU_PENDAMPINGAN


@dataclass(frozen=True)
class GuruSpec:
    key: str
    nama: str
    nip: str | None
    jabatan: str
    wali: str | None = None
    mapel: tuple[str, ...] = ()
    temporary: bool = False


@dataclass(frozen=True)
class SiswaSpec:
    nama: str
    kelas: str
    parent: str
    nis: str
    klasifikasi: Klasifikasi
    riwayat: tuple[Klasifikasi, Klasifikasi, Klasifikasi]  # dua bulan lalu, bulan lalu, bulan ini
    literasi: tuple[int, int]  # nilai awal -> akhir (rata-rata menuju akhir)
    numerasi: tuple[int, int]
    hadir: float  # peluang hadir tepat waktu pada hari sekolah
    drop_last: bool = False


GURU = [
    GuruSpec("rina", "Bu Rina Wulandari", "198504122010012001", "Wali Kelas 5A", wali="5A", mapel=("5B",)),
    GuruSpec("andi", "Pak Andi Pratama", "198811032012011003", "Guru Mapel", mapel=("5A", "5B")),
    GuruSpec("sari", "Bu Sari Dewi", "199002172015022002", "Wali Kelas 5B", wali="5B", mapel=("5A",)),
    GuruSpec("hadi", "Pak Hadi Nugroho", None, "Guru Baru", temporary=True),
]

PARENTS = {
    "wijaya": "Bapak Hendra Wijaya",
    "siti": "Ibu Aminah",
    "dimas": "Bapak Arif",
    "nadia": "Ibu Ratna",
    "budi": "Bapak Santoso",
    "citra": "Ibu Lestari",
    "eko": "Bapak Prasetyo",
}

SISWA = [
    SiswaSpec("Ahmad Rizky Wijaya", "5A", "wijaya", "2024001", C, (C, C, C), (78, 86), (72, 76), 0.80),
    SiswaSpec("Siti Aulia", "5A", "siti", "2024002", M, (M, M, M), (90, 94), (88, 91), 0.97),
    SiswaSpec("Dimas Arya", "5A", "dimas", "2024003", P, (C, P, P), (64, 56), (58, 52), 0.60, drop_last=True),
    SiswaSpec("Nadia Putri", "5A", "nadia", "2024004", C, (C, C, C), (80, 83), (70, 74), 0.88),
    SiswaSpec("Budi Santoso", "5B", "budi", "2024005", C, (P, C, C), (72, 79), (75, 80), 0.85),
    SiswaSpec("Citra Lestari", "5B", "citra", "2024006", M, (C, M, M), (85, 90), (82, 88), 0.95),
    SiswaSpec("Eko Prasetyo", "5B", "eko", "2024007", P, (P, P, P), (60, 63), (65, 62), 0.55),
    SiswaSpec("Salsa Wijaya", "5B", "wijaya", "2024008", C, (C, C, C), (77, 81), (79, 84), 0.90),
]

ASSESSMENTS = ["Ulangan Harian", "Kuis", "Tugas Mandiri", "Ulangan Harian", "Kuis", "UTS"]
GRADE_NOTES = {0: "Pertahankan.", 3: "Perlu latihan tambahan."}


@dataclass
class Seeded:
    users: dict[str, User] = field(default_factory=dict)
    guru: dict[str, Guru] = field(default_factory=dict)
    kelas: dict[str, Kelas] = field(default_factory=dict)
    siswa: dict[str, Siswa] = field(default_factory=dict)
    parents: dict[str, OrangTua] = field(default_factory=dict)
    first_grade: dict[str, Nilai] = field(default_factory=dict)


def school_days(today: date, count: int = 28) -> list[date]:
    days, cursor = [], today - timedelta(days=1)
    while len(days) < count:
        if cursor.weekday() < 5:
            days.append(cursor)
        cursor -= timedelta(days=1)
    return sorted(days)


def weekday_on_or_before(day: date) -> date:
    while day.weekday() >= 5:
        day -= timedelta(days=1)
    return day


def month_start(today: date, back: int) -> date:
    year, month = today.year, today.month - back
    while month <= 0:
        year, month = year - 1, month + 12
    return date(year, month, 1)


def academic_year(today: date) -> str:
    start = today.year if today.month >= 7 else today.year - 1
    return f"{start}/{start + 1}"


def stamp(day: date, clock: time | None, tz) -> datetime:
    return datetime.combine(day, clock or time(8, 0), tzinfo=tz)


def seed_accounts(db: Session, s: Seeded) -> None:
    s.users["admin"] = create_user(
        db, role=UserRole.ADMIN, email=ADMIN_EMAIL, nama="Admin Sekolah",
        password=DEMO_PASSWORD, must_change_password=False, commit=False,
    )
    for spec in GURU:
        user = create_user(
            db, role=UserRole.GURU, email=f"{spec.key}@{DOMAIN}", nama=spec.nama, nip=spec.nip,
            password=TEMP_PASSWORD if spec.temporary else DEMO_PASSWORD,
            must_change_password=spec.temporary, commit=False,
        )
        user.guru_profile.jabatan = spec.jabatan
        user.guru_profile.tampil_publik = True
        s.users[spec.key] = user
        s.guru[spec.key] = user.guru_profile
    for key, nama in PARENTS.items():
        user = create_user(
            db, role=UserRole.ORTU, email=f"ortu.{key}@{DOMAIN}", nama=nama,
            password=DEMO_PASSWORD, must_change_password=False, commit=False,
        )
        s.users[f"ortu.{key}"] = user
        s.parents[key] = user.ortu_profile


def seed_classes(db: Session, s: Seeded) -> None:
    for code in ("5A", "5B", "6A"):
        kelas = Kelas(nama_kelas=code)
        db.add(kelas)
        s.kelas[code] = kelas
    db.flush()
    for spec in GURU:
        if spec.wali:
            s.kelas[spec.wali].wali_kelas_id = s.guru[spec.key].id
        for code in spec.mapel:
            db.add(MapelGuru(guru_id=s.guru[spec.key].id, kelas_id=s.kelas[code].id))
    for spec in SISWA:
        siswa = Siswa(
            nis=spec.nis, nama=spec.nama, kelas_id=s.kelas[spec.kelas].id,
            orang_tua_id=s.parents[spec.parent].id, status_klasifikasi=spec.klasifikasi,
        )
        db.add(siswa)
        s.siswa[spec.nama] = siswa
    db.flush()


def recorder_for(s: Seeded, kelas: str) -> Guru:
    for spec in GURU:
        if kelas in spec.mapel:
            return s.guru[spec.key]
    raise LookupError(kelas)


def seed_history(db: Session, s: Seeded, today: date, tz) -> None:
    rng = random.Random(2026)
    days = school_days(today)

    for spec in SISWA:
        siswa, guru = s.siswa[spec.nama], recorder_for(s, spec.kelas)

        for back, klasifikasi in zip((2, 1, 0), spec.riwayat):
            db.add(RiwayatKlasifikasi(
                siswa_id=siswa.id, periode=month_start(today, back), klasifikasi=klasifikasi,
            ))

        for day in days:
            roll = rng.random()
            if roll < spec.hadir:
                status, clock = StatusAbsensi.HADIR, time(6, rng.randint(40, 59), rng.randint(0, 59))
            elif roll < spec.hadir + (1 - spec.hadir) * 0.5:
                status, clock = StatusAbsensi.TERLAMBAT, time(7, rng.randint(16, 40), rng.randint(0, 59))
            else:
                status, clock = rng.choice([StatusAbsensi.IZIN, StatusAbsensi.SAKIT, StatusAbsensi.ALPA]), None
            when = stamp(day, clock, tz)
            db.add(Absensi(
                siswa_id=siswa.id, tanggal=day, waktu=clock, status=status,
                metode_input=MetodeInput.MANUAL, dicatat_oleh=guru.id,
                catatan="Keterangan dari orang tua." if status is StatusAbsensi.IZIN else None,
                created_at=when, updated_at=when,
            ))

        dates = [weekday_on_or_before(today - timedelta(days=3 + 7 * k)) for k in range(5, -1, -1)]
        for category, (start, end) in (
            (KategoriNilai.LITERASI, spec.literasi),
            (KategoriNilai.NUMERASI, spec.numerasi),
        ):
            scores = [
                max(0, min(100, round(start + (end - start) * i / 5 + rng.uniform(-2, 2))))
                for i in range(6)
            ]
            if spec.drop_last and category is KategoriNilai.LITERASI:
                scores[-1] = scores[-2] - 7
            for i, (day, score) in enumerate(zip(dates, scores)):
                when = stamp(day, time(10, 0), tz)
                grade = Nilai(
                    siswa_id=siswa.id, kategori=category, jenis_ujian=ASSESSMENTS[i],
                    nilai=Decimal(score), tanggal=day, catatan_guru=GRADE_NOTES.get(i),
                    dicatat_oleh=guru.id, created_at=when, updated_at=when,
                )
                db.add(grade)
                if i == 5 and category is KategoriNilai.LITERASI:
                    s.first_grade[spec.nama] = grade
    db.flush()


def seed_notifications(db: Session, s: Seeded, today: date, tz) -> None:
    now = datetime.now(tz)
    yesterday = now - timedelta(days=1)
    ahmad, dimas = s.siswa["Ahmad Rizky Wijaya"], s.siswa["Dimas Arya"]
    guru_notes = [
        (s.users["rina"], "Nilai baru ditambahkan.", "nilai", s.first_grade[ahmad.nama].id, False, now),
        (s.users["rina"], "Absensi Kelas 5A selesai.", "absensi", None, True, yesterday),
        (s.users["sari"], "Nilai baru ditambahkan.", "nilai", s.first_grade[dimas.nama].id, False, now),
    ]
    parent_notes = [
        (s.users["ortu.wijaya"], "Nilai Literasi baru untuk Ahmad.", "nilai", s.first_grade[ahmad.nama].id, False, now),
        (s.users["ortu.wijaya"], "Kehadiran Ahmad hari ini tercatat: Hadir.", "kehadiran", None, True, yesterday),
        (s.users["ortu.dimas"], "Nilai Literasi baru untuk Dimas.", "nilai", s.first_grade[dimas.nama].id, False, now),
    ]
    for user, judul, target, target_id, read, when in guru_notes + parent_notes:
        db.add(Notifikasi(
            user_id=user.id, judul=judul, target=target, target_id=target_id,
            dibaca=read, created_at=when,
        ))


def seed_settings_and_logs(db: Session, s: Seeded, today: date, tz) -> None:
    settings = db.get(PengaturanSekolah, True)
    settings.tahun_ajaran = academic_year(today)
    settings.batas_jam_terlambat = time(7, 15)

    admin = s.users["admin"]
    now = datetime.now(tz)
    entries = [
        (LogTipe.SISTEM, "Admin Sekolah mengubah pengaturan sekolah: batas jam terlambat 07:15."),
        (LogTipe.KELAS, "Admin Sekolah membuat kelas 5A."),
        (LogTipe.KELAS, "Admin Sekolah membuat kelas 5B."),
        (LogTipe.KELAS, "Admin Sekolah membuat kelas 6A."),
        (LogTipe.AKUN, "Admin Sekolah membuat akun guru Bu Rina Wulandari."),
        (LogTipe.AKUN, "Admin Sekolah membuat akun guru Pak Andi Pratama."),
        (LogTipe.SISWA, "Admin Sekolah menambahkan siswa Ahmad Rizky Wijaya ke kelas 5A."),
        (LogTipe.SISWA, "Admin Sekolah menambahkan siswa Siti Aulia ke kelas 5A."),
    ]
    for i, (tipe, pesan) in enumerate(entries):
        db.add(LogAktivitas(
            user_id=admin.id, tipe=tipe, pesan=pesan,
            created_at=now - timedelta(hours=len(entries) - i),
        ))


PAGES = {
    **cms_pages.DEFAULTS,
    "sambutan": "Selamat datang di website SDN 02 Pakunden Kota Blitar. Kami berkomitmen menghadirkan "
    "pembelajaran yang menyenangkan, berkarakter, dan berpusat pada murid.",
    "tentang": "SDN 02 Pakunden adalah sekolah dasar negeri di Kota Blitar yang membimbing murid "
    "tumbuh dalam literasi, numerasi, dan karakter.",
    "sejarah": "Sekolah ini berdiri untuk melayani pendidikan dasar bagi warga sekitar dan terus "
    "berkembang bersama masyarakat Pakunden.",
    "visi": "Terwujudnya murid yang beriman, berilmu, mandiri, dan berakhlak mulia.",
    "misi": "Menyelenggarakan pembelajaran yang aktif dan menyenangkan. Menumbuhkan budaya literasi "
    "dan numerasi. Membiasakan perilaku jujur, disiplin, dan peduli.",
    "tujuan": "Murid menguasai kompetensi dasar, gemar belajar, dan siap melanjutkan ke jenjang berikutnya.",
    "identitas": "Informasi identitas sekolah ditampilkan pada bagian Identitas Sekolah.",
    "kepala-sekolah": "Kepala sekolah memimpin seluruh guru dan tenaga kependidikan dalam menjaga "
    "mutu layanan pendidikan.",
    "akademik-pembelajaran": "Pembelajaran berlangsung Senin sampai Sabtu mengikuti kurikulum yang berlaku.",
    "akademik-kegiatan": "Kegiatan akademik mencakup pembelajaran di kelas, kegiatan literasi pagi, "
    "dan pendampingan belajar.",
    "akademik-penilaian": "Penilaian dilakukan melalui ulangan harian, tugas, dan asesmen tengah serta "
    "akhir semester.",
    "ppdb-informasi": "Penerimaan peserta didik baru dibuka setiap tahun ajaran sesuai ketentuan dinas pendidikan.",
    "ppdb-jadwal": "Jadwal pendaftaran, verifikasi, dan pengumuman akan diumumkan sekolah melalui halaman Informasi.",
    "ppdb-persyaratan": "Calon murid memenuhi batas usia dan melengkapi dokumen yang ditentukan.",
    "ppdb-alur-1": "Baca informasi PPDB terbaru.",
    "ppdb-alur-2": "Lengkapi dokumen persyaratan.",
    "ppdb-alur-3": "Isi formulir pendaftaran.",
    "ppdb-alur-4": "Sekolah memeriksa berkas.",
    "ppdb-alur-5": "Hasil diumumkan di sekolah dan website.",
    "ppdb-dokumen": "Akta kelahiran, kartu keluarga, dan pas foto terbaru.",
}


CLASS_TOPICS = {
    1: ("Membaca permulaan dan berhitung dasar", "Pengenalan lingkungan sekolah"),
    2: ("Membaca lancar dan operasi hitung sederhana", "Kegiatan bercerita"),
    3: ("Menulis kalimat dan perkalian", "Kunjungan ke perpustakaan"),
    4: ("Teks informasi dan pecahan", "Praktik sains sederhana"),
    5: ("Teks narasi dan bangun ruang", "Kegiatan literasi pagi"),
    6: ("Persiapan asesmen akhir", "Pendampingan persiapan kelulusan"),
}


def seed_class_info(db: Session) -> None:
    for tingkat, (belajar, kegiatan) in CLASS_TOPICS.items():
        db.add(InformasiKelas(
            tingkat=tingkat, jenis="Pembelajaran", judul=belajar, urutan=1,
            deskripsi=f"Fokus pembelajaran kelas {tingkat} semester ini: {belajar.lower()}.",
        ))
        db.add(InformasiKelas(
            tingkat=tingkat, jenis="Kegiatan", judul=kegiatan, urutan=1,
            deskripsi=f"Kegiatan rutin kelas {tingkat}: {kegiatan.lower()}.",
        ))
    db.add(InformasiKelas(
        tingkat=1, jenis="Kegiatan", judul="Masa pengenalan (disembunyikan)", urutan=2, tampil=False,
        deskripsi="Belum dipublikasikan.",
    ))


def seed_calendar(db: Session, today: date) -> None:
    def at(days: int) -> date:
        return today + timedelta(days=days)

    db.add_all([
        KalenderAkademik(judul="Hari pertama semester", kategori="Kegiatan", tanggal_mulai=at(-60),
                         deskripsi="Murid kembali masuk sekolah."),
        KalenderAkademik(judul="Asesmen tengah semester", kategori="Ujian", tanggal_mulai=at(-5),
                         tanggal_selesai=at(1), deskripsi="Asesmen untuk seluruh kelas."),
        KalenderAkademik(judul="Pembagian rapor tengah semester", kategori="Kegiatan",
                         tanggal_mulai=at(9), deskripsi="Orang tua mengambil rapor ke wali kelas."),
        KalenderAkademik(judul="Rapat komite sekolah", kategori="Rapat", tanggal_mulai=at(14)),
        KalenderAkademik(judul="Libur akhir semester", kategori="Libur", tanggal_mulai=at(45),
                         tanggal_selesai=at(59), deskripsi="Kegiatan belajar diliburkan."),
        KalenderAkademik(judul="Hari pertama semester genap", kategori="Kegiatan",
                         tanggal_mulai=at(60)),
        KalenderAkademik(judul="Agenda internal guru", kategori="Rapat", tanggal_mulai=at(20),
                         tampil=False, deskripsi="Tidak tampil di website."),
    ])


def seed_website(db: Session, s: Seeded, today: date) -> None:
    profile = db.get(ProfilSekolah, True)
    profile.nama = "SDN 02 Pakunden"
    profile.kota = "Blitar"
    profile.npsn = "00000000"
    profile.alamat = "Jl. Contoh No. 1, Pakunden, Kota Blitar"
    profile.akreditasi = "A"
    profile.telepon = "0342-000000"
    profile.email = f"info@{DOMAIN}"
    profile.media_sosial = "@sdn02pakunden"
    profile.whatsapp = "6281200000000"

    # Migrasi 002 sudah menyisipkan beberapa teks awal; merge menimpa alih-alih bentrok.
    for key, value in PAGES.items():
        db.merge(HalamanSitus(kunci=key, isi=value))

    admin_id = s.users["admin"].id
    d = lambda days: today - timedelta(days=days)  # noqa: E731
    T, D, A = KontenStatus.TERBIT, KontenStatus.DRAFT, KontenStatus.ARSIP

    db.add_all([
        Pengumuman(slug="libur-semester-ganjil", judul="Jadwal Libur Semester Ganjil",
                   ringkasan="Libur semester ganjil dimulai sesuai kalender akademik.",
                   isi="Kegiatan belajar mengajar diliburkan sesuai kalender akademik. Murid kembali "
                   "masuk pada hari pertama semester genap.", tanggal=d(2), status=T, dibuat_oleh=admin_id),
        Pengumuman(slug="pembagian-rapor-tengah-semester", judul="Pembagian Rapor Tengah Semester",
                   ringkasan="Orang tua diharapkan hadir mengambil rapor.",
                   isi="Pembagian rapor dilakukan oleh wali kelas. Mohon orang tua hadir tepat waktu.",
                   tanggal=d(9), status=T, dibuat_oleh=admin_id),
        Pengumuman(slug="rapat-komite-sekolah", judul="Rapat Komite Sekolah",
                   ringkasan="Undangan rapat komite sekolah.", isi="Rapat membahas program sekolah.",
                   tanggal=d(1), status=D, dibuat_oleh=admin_id),
        Pengumuman(slug="pengumuman-lama", judul="Pengumuman Tahun Lalu", ringkasan="Sudah diarsipkan.",
                   isi="Pengumuman ini sudah tidak berlaku.", tanggal=d(300), status=A, dibuat_oleh=admin_id),
        Berita(slug="gerakan-literasi-pagi", kategori=BeritaKategori.BERITA,
               judul="Gerakan Literasi Pagi Dimulai",
               ringkasan="Setiap pagi murid membaca buku selama lima belas menit.",
               isi="Sekolah memulai gerakan literasi pagi. Murid membaca buku pilihan mereka sebelum "
               "pelajaran dimulai, didampingi wali kelas.", tanggal=d(4), status=T, dibuat_oleh=admin_id),
        Berita(slug="asesmen-numerasi-kelas-5", kategori=BeritaKategori.AKADEMIK,
               judul="Asesmen Numerasi Kelas 5",
               ringkasan="Hasil asesmen digunakan untuk merancang pendampingan belajar.",
               isi="Guru melaksanakan asesmen numerasi untuk kelas 5 dan memanfaatkan hasilnya untuk "
               "pendampingan.", tanggal=d(12), status=T, dibuat_oleh=admin_id),
        Berita(slug="informasi-awal-ppdb", kategori=BeritaKategori.PPDB, judul="Informasi Awal PPDB",
               ringkasan="Tahapan PPDB akan diumumkan sekolah.",
               isi="Sekolah akan mengumumkan jadwal dan persyaratan PPDB melalui website ini.",
               tanggal=d(20), status=T, dibuat_oleh=admin_id),
        Berita(slug="kunjungan-perpustakaan-kota", kategori=BeritaKategori.KEGIATAN,
               judul="Kunjungan ke Perpustakaan Kota",
               ringkasan="Murid kelas 4 berkunjung ke perpustakaan kota.",
               isi="Kegiatan kunjungan menambah wawasan murid tentang layanan perpustakaan.",
               tanggal=d(30), status=T, dibuat_oleh=admin_id),
        Berita(slug="berita-konsep", kategori=BeritaKategori.BERITA, judul="Berita Konsep",
               ringkasan="Masih berupa konsep.", isi="Belum diterbitkan.", tanggal=d(1), status=D,
               dibuat_oleh=admin_id),
    ])
    db.add_all([
        Kegiatan(slug="upacara-bendera-senin", kategori=KegiatanKategori.UPACARA,
                 judul="Upacara Bendera Hari Senin", deskripsi="Upacara rutin untuk menumbuhkan disiplin.",
                 tanggal=d(6), status=T, dibuat_oleh=admin_id),
        Kegiatan(slug="latihan-pramuka", kategori=KegiatanKategori.EKSTRAKURIKULER,
                 judul="Latihan Pramuka", deskripsi="Latihan pramuka setiap pekan.", tanggal=d(8),
                 status=T, dibuat_oleh=admin_id),
        Kegiatan(slug="lomba-membaca-puisi", kategori=KegiatanKategori.AKADEMIK,
                 judul="Lomba Membaca Puisi", deskripsi="Lomba antarkelas.", tanggal=d(15),
                 status=T, dibuat_oleh=admin_id),
        Kegiatan(slug="kerja-bakti-sekolah", kategori=KegiatanKategori.SOSIAL,
                 judul="Kerja Bakti Sekolah", deskripsi="Murid dan guru membersihkan lingkungan.",
                 tanggal=d(25), status=T, dibuat_oleh=admin_id),
        Kegiatan(slug="kegiatan-konsep", kategori=KegiatanKategori.ACARA_SEKOLAH, judul="Kegiatan Konsep",
                 deskripsi="Belum diterbitkan.", tanggal=d(1), status=D, dibuat_oleh=admin_id),
    ])
    db.add_all([
        Fasilitas(nama="Perpustakaan", deskripsi="Koleksi buku bacaan untuk semua kelas.", urutan=1),
        Fasilitas(nama="Ruang Kelas", deskripsi="Ruang kelas yang nyaman untuk belajar.", urutan=2),
        Fasilitas(nama="Lapangan Olahraga", deskripsi="Untuk upacara dan olahraga.", urutan=3),
        Fasilitas(nama="Laboratorium Komputer", deskripsi="Belum dibuka.", urutan=4, tampil=False),
    ])
    db.add_all([
        Faq(kategori=FaqKategori.UMUM, pertanyaan="Pukul berapa sekolah dimulai?",
            jawaban="Pelajaran dimulai pagi hari; murid diharapkan tiba sebelum bel masuk.", urutan=1),
        Faq(kategori=FaqKategori.UMUM, pertanyaan="Bagaimana menghubungi sekolah?",
            jawaban="Hubungi admin melalui WhatsApp atau datang langsung ke sekolah.", urutan=2),
        Faq(kategori=FaqKategori.PPDB, pertanyaan="Kapan PPDB dibuka?",
            jawaban="Jadwal diumumkan melalui halaman Informasi.", urutan=1),
        Faq(kategori=FaqKategori.PPDB, pertanyaan="Dokumen apa saja yang perlu disiapkan?",
            jawaban="Akta kelahiran, kartu keluarga, dan pas foto terbaru.", urutan=2),
        Faq(kategori=FaqKategori.KEUANGAN, pertanyaan="Apakah ada biaya pendaftaran?",
            jawaban="Informasi biaya mengikuti ketentuan sekolah negeri.", urutan=1),
        Faq(kategori=FaqKategori.AKADEMIK, pertanyaan="Bagaimana cara melihat nilai anak?",
            jawaban="Orang tua dapat masuk ke Portal Orang Tua dengan akun dari sekolah.", urutan=1),
        Faq(kategori=FaqKategori.KEGIATAN, pertanyaan="Apa saja ekstrakurikuler yang tersedia?",
            jawaban="Pramuka dan kegiatan seni.", urutan=1),
        Faq(kategori=FaqKategori.UMUM, pertanyaan="Pertanyaan tersembunyi", jawaban="Tidak tampil.",
            urutan=9, tampil=False),
    ])


def populate(db: Session, tz) -> None:
    """Mengisi seluruh data demo dalam satu transaksi; gagal di tengah = tidak ada yang tersimpan."""
    today = datetime.now(tz).date()
    seeded = Seeded()
    try:
        seed_accounts(db, seeded)
        seed_classes(db, seeded)
        seed_history(db, seeded, today, tz)
        seed_notifications(db, seeded, today, tz)
        seed_settings_and_logs(db, seeded, today, tz)
        seed_website(db, seeded, today)
        seed_class_info(db)
        seed_calendar(db, today)
        db.commit()
    except Exception:
        db.rollback()
        raise


def reset_database(db: Session) -> None:
    tables = [
        row[0]
        for row in db.execute(text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'"))
        if row[0] not in SINGLETONS
    ]
    db.execute(text(f"TRUNCATE {', '.join(tables)} RESTART IDENTITY CASCADE"))
    db.execute(text("UPDATE pengaturan_sekolah SET batas_jam_terlambat = NULL"))
    db.execute(
        text(
            "UPDATE profil_sekolah SET nama = DEFAULT, kota = DEFAULT, npsn = NULL, alamat = NULL,"
            " akreditasi = NULL, telepon = NULL, email = NULL, media_sosial = NULL,"
            " whatsapp = NULL, peta_url = NULL"
        )
    )


def print_accounts() -> None:
    rows = [
        ("Admin (web)", ADMIN_EMAIL, DEMO_PASSWORD, "Login Admin di website"),
        ("Guru - wali 5A + mapel 5B", f"rina@{DOMAIN}", DEMO_PASSWORD, "wali 5A hanya melihat 5A; mencatat di 5B"),
        ("Guru - mapel 5A & 5B", f"andi@{DOMAIN}", DEMO_PASSWORD, "bisa absen, nilai, scan wajah"),
        ("Guru - wali 5B + mapel 5A", f"sari@{DOMAIN}", DEMO_PASSWORD, ""),
        ("Guru - password sementara", f"hadi@{DOMAIN}", TEMP_PASSWORD, "wajib ganti password; belum punya kelas"),
        ("Orang tua - 2 anak (5A, 5B)", f"ortu.wijaya@{DOMAIN}", DEMO_PASSWORD, "Ahmad & Salsa"),
        ("Orang tua - 1 anak", f"ortu.siti@{DOMAIN}", DEMO_PASSWORD, "juga: ortu.dimas, nadia, budi, citra, eko"),
    ]
    print("\nAkun demo:")
    for label, email, password, note in rows:
        print(f"  {label:<30} {email:<28} {password:<14} {note}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--reset", action="store_true", help="kosongkan semua data sebelum mengisi")
    parser.add_argument("--yes", action="store_true", help="lewati konfirmasi untuk --reset")
    args = parser.parse_args()

    settings = get_settings()
    if settings.is_production:
        print("Menolak: seeder hanya untuk development (ENVIRONMENT=production).", file=sys.stderr)
        return 1

    url = make_url(settings.database_url)
    engine = build_engine(settings.database_url)
    with build_session_factory(engine)() as db:
        if db.scalar(text("SELECT to_regclass('public.users')")) is None:
            print("Tabel belum ada. Jalankan dulu: python -m scripts.init_db", file=sys.stderr)
            return 1

        if args.reset:
            target = f"{url.database} @ {url.host or url.query.get('host', 'lokal')}"
            if not args.yes and input(f"SEMUA data di {target} akan dihapus. Ketik 'ya' untuk lanjut: ") != "ya":
                print("Dibatalkan.")
                return 1
            reset_database(db)
            db.commit()
        elif db.scalar(text("SELECT count(*) FROM users")):
            print("Database sudah berisi data; tidak diubah. Pakai --reset untuk mengisi ulang dari awal.")
            return 0

        populate(db, settings.tzinfo)

    print(f"Selesai: {len(SISWA)} siswa, {len(GURU)} guru, {len(PARENTS)} akun orang tua, 3 kelas.")
    print_accounts()
    return 0


if __name__ == "__main__":
    sys.exit(main())
