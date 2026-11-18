"""Daftar kunci teks halaman website yang dapat diedit admin (tabel halaman_situs).

Daftar ini juga yang dipakai aplikasi admin untuk membangun formulir, sehingga menambah teks baru
cukup dengan menambah baris di sini dan memakainya di website.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class PageDef:
    kunci: str
    label: str
    grup: str
    baris: int  # saran tinggi kolom isian


BERANDA = "Beranda"
PROFIL = "Profil Sekolah"
AKADEMIK = "Akademik"
PPDB = "PPDB"

PAGES: tuple[PageDef, ...] = (
    PageDef("hero-kicker", "Teks kecil di atas judul utama", BERANDA, 1),
    PageDef("hero-title", "Judul utama (Hero)", BERANDA, 2),
    PageDef("hero-subtitle", "Subjudul (Hero)", BERANDA, 3),
    PageDef("sambutan", "Sambutan sekolah", BERANDA, 6),
    PageDef("ppdb-banner", "Teks banner PPDB", BERANDA, 3),
    PageDef("kontak-ajakan", "Ajakan menghubungi sekolah", BERANDA, 2),
    PageDef("tentang", "Tentang sekolah", PROFIL, 5),
    PageDef("sejarah", "Sejarah", PROFIL, 6),
    PageDef("visi", "Visi", PROFIL, 3),
    PageDef("misi", "Misi", PROFIL, 6),
    PageDef("tujuan", "Tujuan", PROFIL, 4),
    PageDef("identitas", "Identitas sekolah", PROFIL, 4),
    PageDef("kepala-sekolah", "Kepala sekolah", PROFIL, 5),
    PageDef("akademik-pembelajaran", "Informasi pembelajaran", AKADEMIK, 4),
    PageDef("akademik-kegiatan", "Kegiatan akademik", AKADEMIK, 4),
    PageDef("akademik-penilaian", "Penilaian", AKADEMIK, 4),
    PageDef("ppdb-informasi", "Informasi PPDB", PPDB, 4),
    PageDef("ppdb-jadwal", "Jadwal PPDB", PPDB, 4),
    PageDef("ppdb-persyaratan", "Persyaratan PPDB", PPDB, 4),
    *(PageDef(f"ppdb-alur-{i}", f"Alur pendaftaran langkah {i}", PPDB, 2) for i in range(1, 6)),
    PageDef("ppdb-dokumen", "Dokumen PPDB", PPDB, 3),
)

BY_KEY = {p.kunci: p for p in PAGES}

# Isi awal untuk teks yang dulu tertanam di aplikasi (dipasang oleh migrasi 002 dan seeder).
DEFAULTS: dict[str, str] = {
    "hero-kicker": "Kota Blitar",
    "hero-title": "SDN 02 Pakunden\nKota Blitar",
    "hero-subtitle": "Informasi sekolah dalam satu tempat: profil, kegiatan, akademik, dan penerimaan "
    "peserta didik baru.",
    "ppdb-banner": "Jadwal, persyaratan, dan alur pendaftaran diumumkan oleh pihak sekolah.",
    "kontak-ajakan": "Hubungi admin sekolah melalui WhatsApp.",
}
