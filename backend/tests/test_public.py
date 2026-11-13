from datetime import date

from sqlalchemy import update

from app.models import (
    Berita,
    Fasilitas,
    Faq,
    HalamanSitus,
    Kegiatan,
    KegiatanFoto,
    Pengumuman,
    ProfilSekolah,
)
from app.models.base import (
    BeritaKategori,
    FaqKategori,
    KegiatanKategori,
    KontenStatus,
)
from tests.factories import make_guru, publish

API = "/api/v1/public"


def test_informasi_merges_announcements_and_news_newest_first_without_auth(client, db):
    publish(Pengumuman, db, slug="libur", judul="Libur Semester", ringkasan="Mulai pekan depan",
            isi="Isi pengumuman", tanggal=date(2026, 10, 5))
    publish(Berita, db, slug="juara", judul="Juara Lomba", kategori=BeritaKategori.BERITA,
            ringkasan="Tingkat kota", tanggal=date(2026, 10, 7))
    publish(Berita, db, slug="ppdb", judul="PPDB Dibuka", kategori=BeritaKategori.PPDB,
            tanggal=date(2026, 9, 1))

    response = client.get(f"{API}/informasi")

    assert response.status_code == 200
    items = response.json()
    assert [i["slug"] for i in items] == ["juara", "libur", "ppdb"]
    assert [i["kategori"] for i in items] == ["Berita", "Pengumuman", "PPDB"]
    assert items[1] == {
        "slug": "libur",
        "kategori": "Pengumuman",
        "tanggal": "2026-10-05",
        "judul": "Libur Semester",
        "ringkasan": "Mulai pekan depan",
        "gambar_url": None,
    }
    assert "isi" not in items[0]


def test_drafts_and_archived_content_are_never_public(client, db):
    publish(Berita, db, slug="terbit", judul="Terbit")
    db.add(Berita(slug="draft", judul="Draft", status=KontenStatus.DRAFT))
    db.add(Pengumuman(slug="arsip", judul="Arsip", status=KontenStatus.ARSIP))
    db.commit()

    assert [i["slug"] for i in client.get(f"{API}/informasi").json()] == ["terbit"]
    assert client.get(f"{API}/informasi/draft").status_code == 404
    assert client.get(f"{API}/informasi/arsip").status_code == 404


def test_informasi_detail_covers_both_tables_and_includes_the_body(client, db):
    publish(Berita, db, slug="juara", judul="Juara", kategori=BeritaKategori.AKADEMIK, isi="Isi berita")
    publish(Pengumuman, db, slug="libur", judul="Libur", isi="Isi pengumuman")

    berita = client.get(f"{API}/informasi/juara").json()
    pengumuman = client.get(f"{API}/informasi/libur").json()

    assert (berita["kategori"], berita["isi"]) == ("Akademik", "Isi berita")
    assert (pengumuman["kategori"], pengumuman["isi"]) == ("Pengumuman", "Isi pengumuman")


def test_unknown_slug_is_404_with_a_message(client):
    response = client.get(f"{API}/informasi/tidak-ada")
    assert response.status_code == 404
    assert response.json() == {"message": "Informasi tidak ditemukan."}


def test_informasi_limit_is_enforced_and_validated(client, db):
    for i in range(5):
        publish(Berita, db, slug=f"b{i}", judul=f"B{i}", tanggal=date(2026, 10, 1 + i))

    assert len(client.get(f"{API}/informasi?limit=2").json()) == 2
    assert client.get(f"{API}/informasi?limit=0").status_code == 422
    assert client.get(f"{API}/informasi?limit=9999").status_code == 422


def test_kegiatan_lists_photos_and_uses_the_first_as_cover(client, db):
    kegiatan = publish(Kegiatan, db, slug="upacara", judul="Upacara", deskripsi="Senin pagi",
                       kategori=KegiatanKategori.UPACARA, tanggal=date(2026, 9, 13))
    db.add_all([
        KegiatanFoto(kegiatan_id=kegiatan.id, url="https://x.test/2.jpg", urutan=2),
        KegiatanFoto(kegiatan_id=kegiatan.id, url="https://x.test/1.jpg", urutan=1),
    ])
    db.add(Kegiatan(slug="draft", judul="Draft", kategori=KegiatanKategori.SOSIAL,
                    status=KontenStatus.DRAFT))
    db.commit()

    items = client.get(f"{API}/kegiatan").json()
    detail = client.get(f"{API}/kegiatan/upacara").json()

    assert [i["slug"] for i in items] == ["upacara"]
    assert items[0]["gambar_url"] == "https://x.test/1.jpg"
    assert detail["foto"] == [{"url": "https://x.test/1.jpg"}, {"url": "https://x.test/2.jpg"}]
    assert detail["kategori"] == "Upacara" and detail["deskripsi"] == "Senin pagi"
    assert client.get(f"{API}/kegiatan/draft").status_code == 404


def test_fasilitas_hides_unlisted_items_and_follows_the_order(client, db):
    db.add_all([
        Fasilitas(nama="Perpustakaan", urutan=2),
        Fasilitas(nama="Lab Komputer", deskripsi="20 unit", urutan=1),
        Fasilitas(nama="Gudang", tampil=False),
    ])
    db.commit()

    items = client.get(f"{API}/fasilitas").json()

    assert [i["nama"] for i in items] == ["Lab Komputer", "Perpustakaan"]
    assert set(items[0]) == {"id", "nama", "deskripsi", "gambar_url"}


def test_faq_returns_visible_questions_with_category_labels(client, db):
    db.add_all([
        Faq(kategori=FaqKategori.PPDB, pertanyaan="Kapan dibuka?", jawaban="Januari", urutan=1),
        Faq(kategori=FaqKategori.UMUM, pertanyaan="Jam masuk?", jawaban="07.00", urutan=2),
        Faq(kategori=FaqKategori.KEUANGAN, pertanyaan="Tersembunyi", tampil=False),
    ])
    db.commit()

    assert client.get(f"{API}/faq").json() == [
        {"kategori": "PPDB", "pertanyaan": "Kapan dibuka?", "jawaban": "Januari"},
        {"kategori": "Umum", "pertanyaan": "Jam masuk?", "jawaban": "07.00"},
    ]


def test_guru_endpoint_only_exposes_opted_in_public_profiles(client, db):
    public = make_guru(db, "a@contoh.id", "Bu Rina")
    public.tampil_publik, public.jabatan = True, "Kepala Sekolah"
    make_guru(db, "b@contoh.id", "Pak Rahasia")
    db.commit()

    body = client.get(f"{API}/guru").json()

    assert body == [{"nama": "Bu Rina", "jabatan": "Kepala Sekolah", "foto_url": None}]
    assert "email" not in body[0] and "nip" not in body[0]


def test_sekolah_has_defaults_and_reflects_updates(client, db):
    assert client.get(f"{API}/sekolah").json()["nama"] == "SDN 02 Pakunden"

    db.execute(update(ProfilSekolah).values(alamat="Jl. Merdeka 1", whatsapp="6281234567890"))
    db.commit()

    body = client.get(f"{API}/sekolah").json()
    assert body["alamat"] == "Jl. Merdeka 1"
    assert body["whatsapp"] == "6281234567890"
    assert body["kota"] == "Blitar" and body["npsn"] is None


def test_halaman_lists_page_texts_by_key(client, db):
    db.add_all([HalamanSitus(kunci="sambutan", isi="Selamat datang"), HalamanSitus(kunci="tentang", isi="Profil")])
    db.commit()

    assert client.get(f"{API}/halaman").json() == [
        {"kunci": "sambutan", "isi": "Selamat datang"},
        {"kunci": "tentang", "isi": "Profil"},
    ]


def test_halaman_skips_blank_rows_so_the_website_shows_its_fallback(client, db):
    db.add_all([HalamanSitus(kunci="visi", isi="   "), HalamanSitus(kunci="misi", isi="Misi sekolah")])
    db.commit()

    assert client.get(f"{API}/halaman").json() == [{"kunci": "misi", "isi": "Misi sekolah"}]


def test_public_responses_are_always_revalidated_so_admin_edits_show_immediately(client):
    assert client.get(f"{API}/faq").headers["cache-control"] == "no-cache"
