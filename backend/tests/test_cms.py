from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app.models import (
    Berita,
    Fasilitas,
    Faq,
    HalamanSitus,
    Kegiatan,
    KegiatanFoto,
    LogAktivitas,
    Pengumuman,
    ProfilSekolah,
)
from app.models.base import UserRole
from app.services import cms_pages
from app.services.cms_service import slugify
from tests.factories import make_guru, make_user
from tests.test_auth import bearer, token_for

CMS = "/api/v1/admin/cms"
PUBLIC = "/api/v1/public"
JKT = ZoneInfo("Asia/Jakarta")
TODAY = "2026-10-08"
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
WEBP = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 64


@pytest.fixture
def adm(app, client, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    make_user(db, UserRole.ADMIN, "admin@contoh.id", "Admin Sekolah")
    make_guru(db, "rina@contoh.id", "Bu Rina")
    return bearer(token_for(client, "admin@contoh.id"))


def rows(db, model):
    db.expire_all()
    order = model.kunci if model is HalamanSitus else model.id
    return list(db.scalars(select(model).order_by(order)))


def messages(db):
    return [r.pesan for r in rows(db, LogAktivitas)]


def post_body(**override):
    return {
        "judul": "Gerakan Literasi Pagi", "kategori": "Berita", "ringkasan": "Ringkas.",
        "isi": "Isi lengkap berita.", "status": "terbit", "tanggal": "2026-10-01", **override,
    }


class TestAuthorization:
    ENDPOINTS = [
        ("get", "/pages"), ("put", "/pages"), ("get", "/school"), ("put", "/school"),
        ("get", "/posts"), ("get", "/posts/x"), ("post", "/posts"), ("put", "/posts/x"),
        ("delete", "/posts/x"), ("get", "/kegiatan"), ("post", "/kegiatan"), ("put", "/kegiatan/x"),
        ("delete", "/kegiatan/x"), ("get", "/fasilitas"), ("post", "/fasilitas"),
        ("put", "/fasilitas/1"), ("delete", "/fasilitas/1"), ("get", "/faq"), ("post", "/faq"),
        ("put", "/faq/1"), ("delete", "/faq/1"), ("post", "/media"),
    ]

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    def test_requires_a_token(self, client, adm, method, path):
        assert client.request(method, f"{CMS}{path}").status_code == 401

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    def test_guru_and_parents_are_forbidden(self, client, db, adm, method, path):
        make_user(db, UserRole.ORTU, "ortu@contoh.id", "Ortu")
        for email in ("rina@contoh.id", "ortu@contoh.id"):
            headers = bearer(token_for(client, email))
            assert client.request(method, f"{CMS}{path}", headers=headers, json={}).status_code == 403


class TestPages:
    def test_lists_every_registered_key_with_empty_text_when_unset(self, client, adm):
        body = client.get(f"{CMS}/pages", headers=adm).json()

        assert [p["kunci"] for p in body] == [p.kunci for p in cms_pages.PAGES]
        assert set(body[0]) == {"kunci", "label", "grup", "baris", "isi"}
        assert {p["grup"] for p in body} == {"Beranda", "Profil Sekolah", "Akademik", "PPDB"}
        keys = {p["kunci"] for p in body}
        assert not any(k.startswith("kelas-") or k == "akademik-kalender" for k in keys), (
            "dikelola lewat tabel informasi kelas dan kalender"
        )
        assert all(p["isi"] == "" for p in body)

    def test_saving_changes_the_public_website_immediately(self, client, adm):
        before = {p["kunci"] for p in client.get(f"{PUBLIC}/halaman").json()}
        response = client.put(
            f"{CMS}/pages", headers=adm,
            json={"halaman": {"hero-title": "  Selamat Datang\nDi Sekolah Kami ", "visi": "Visi baru"}},
        )

        assert response.status_code == 200
        saved = {p["kunci"]: p["isi"] for p in response.json()}
        assert saved["hero-title"] == "Selamat Datang\nDi Sekolah Kami"
        public = {p["kunci"]: p["isi"] for p in client.get(f"{PUBLIC}/halaman").json()}
        assert before == set() and public == {"hero-title": "Selamat Datang\nDi Sekolah Kami", "visi": "Visi baru"}

    def test_blank_text_removes_the_entry_so_the_website_falls_back(self, client, db, adm):
        client.put(f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "Visi"}})

        client.put(f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "   "}})

        assert rows(db, HalamanSitus) == []
        assert client.get(f"{PUBLIC}/halaman").json() == []

    def test_unknown_keys_are_rejected_and_nothing_is_saved(self, client, db, adm):
        response = client.put(
            f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "Visi", "bukan-kunci": "x"}}
        )

        assert response.status_code == 422
        assert response.json()["errors"] == {"bukan-kunci": "Kunci teks tidak dikenal."}
        assert rows(db, HalamanSitus) == []

    def test_text_longer_than_the_limit_is_rejected(self, client, adm):
        response = client.put(f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "x" * 20001}})

        assert response.status_code == 422

    def test_unchanged_save_writes_no_log(self, client, db, adm):
        client.put(f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "Visi"}})
        client.put(f"{CMS}/pages", headers=adm, json={"halaman": {"visi": "Visi"}})

        assert messages(db) == ["Admin Sekolah memperbarui 1 teks halaman website."]


class TestSchool:
    def test_get_returns_defaults_then_saved_values_visible_publicly(self, client, adm):
        first = client.get(f"{CMS}/school", headers=adm).json()
        assert (first["nama"], first["kota"], first["alamat"]) == ("SDN 02 Pakunden", "Blitar", None)

        response = client.put(
            f"{CMS}/school", headers=adm,
            json={
                "nama": "SDN 02 Pakunden", "kota": "Blitar", "alamat": "Jl. Mawar 1",
                "telepon": "0342-123", "email": "info@sekolah.id", "whatsapp": "0812-3456-7890",
                "media_sosial": "@sdn02", "npsn": "", "akreditasi": "A", "peta_url": "",
            },
        )

        assert response.status_code == 200
        public = client.get(f"{PUBLIC}/sekolah").json()
        assert public["alamat"] == "Jl. Mawar 1" and public["whatsapp"] == "6281234567890"
        assert public["npsn"] is None and public["peta_url"] is None

    @pytest.mark.parametrize(
        ("raw", "stored"),
        [("+62 812 3456 7890", "6281234567890"), ("081234567890", "6281234567890"), ("6281234567890", "6281234567890")],
    )
    def test_whatsapp_is_normalised_for_wa_me(self, client, adm, raw, stored):
        response = client.put(
            f"{CMS}/school", headers=adm, json={"nama": "SDN", "kota": "Blitar", "whatsapp": raw}
        )

        assert response.json()["whatsapp"] == stored

    @pytest.mark.parametrize(
        ("override", "field"),
        [
            ({"whatsapp": "abc"}, "whatsapp"),
            ({"whatsapp": "123"}, "whatsapp"),
            ({"email": "bukan-email"}, "email"),
            ({"nama": "  "}, "nama"),
            ({"peta_url": "javascript:alert(1)"}, "peta_url"),
        ],
    )
    def test_invalid_values_are_field_errors_and_change_nothing(self, client, db, adm, override, field):
        body = {"nama": "SDN 02", "kota": "Blitar", **override}

        response = client.put(f"{CMS}/school", headers=adm, json=body)

        assert response.status_code == 422 and field in response.json()["errors"]
        assert rows(db, ProfilSekolah)[0].nama == "SDN 02 Pakunden"


class TestSchoolPhoto:
    def upload(self, client, adm, data=JPEG, name="sekolah.jpg", content_type="image/jpeg"):
        return client.post(f"{CMS}/school/photo", headers=adm, files={"file": (name, data, content_type)})

    def stored(self, app):
        from pathlib import Path

        return sorted(p.name for p in Path(app.state.settings.media_dir).glob("*"))

    def test_upload_sets_the_photo_shown_on_the_public_site(self, client, app, adm):
        response = self.upload(client, adm)

        assert response.status_code == 201
        body = response.json()
        assert body["foto_url"].startswith("/media/") and body["foto_url"].endswith(".jpg")
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == body["foto_url"]
        assert client.get(f"{CMS}/school", headers=adm).json()["foto_url"] == body["foto_url"]
        assert client.get(body["foto_url"]).content == JPEG
        assert self.stored(app) == [body["foto_url"].removeprefix("/media/")]

    def test_no_photo_is_null_until_one_is_uploaded(self, client, adm):
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] is None

    def test_replacing_removes_the_old_file_and_keeps_only_the_new_one(self, client, app, adm):
        old = self.upload(client, adm).json()["foto_url"]
        new = self.upload(client, adm, PNG, "baru.png", "image/png").json()["foto_url"]

        assert old != new and new.endswith(".png")
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == new
        assert self.stored(app) == [new.removeprefix("/media/")]
        assert client.get(old).status_code == 404

    @pytest.mark.parametrize(
        "data", [b"<script>alert(1)</script>", b"<svg xmlns='http://www.w3.org/2000/svg'/>", b"GIF89a....", b"%PDF-1.4", b""]
    )
    def test_a_rejected_file_keeps_the_previous_photo(self, client, app, adm, data):
        keep = self.upload(client, adm).json()["foto_url"]

        response = self.upload(client, adm, data, "x.jpg")

        assert response.status_code == 422 and "file" in response.json()["errors"]
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == keep
        assert self.stored(app) == [keep.removeprefix("/media/")]

    def test_an_oversized_file_is_rejected_and_the_photo_is_kept(self, client, app, adm):
        keep = self.upload(client, adm).json()["foto_url"]

        response = self.upload(client, adm, JPEG + b"\x00" * (64 * 1024))

        assert response.status_code == 413
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == keep
        assert self.stored(app) == [keep.removeprefix("/media/")]

    def test_a_database_failure_leaves_the_old_photo_and_no_orphan_file(self, client, app, adm, monkeypatch):
        keep = self.upload(client, adm).json()["foto_url"]

        def boom(*a, **k):
            raise RuntimeError("db down")

        monkeypatch.setattr("app.services.cms_service.replace_school_photo", boom)
        failing = TestClientNoRaise(app)
        response = failing.post(
            f"{CMS}/school/photo", headers=adm, files={"file": ("x.png", PNG, "image/png")}
        )

        assert response.status_code == 500
        monkeypatch.undo()
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == keep
        assert self.stored(app) == [keep.removeprefix("/media/")]

    def test_saving_contact_details_does_not_touch_the_photo(self, client, adm):
        keep = self.upload(client, adm).json()["foto_url"]

        client.put(f"{CMS}/school", headers=adm, json={"nama": "SDN 02", "kota": "Blitar", "alamat": "Jl. Baru"})

        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] == keep

    def test_only_admins_can_replace_the_photo(self, client, db, adm):
        make_user(db, UserRole.ORTU, "ortu@contoh.id", "Ortu")
        assert client.post(f"{CMS}/school/photo", files={"file": ("a.jpg", JPEG, "image/jpeg")}).status_code == 401
        for email in ("rina@contoh.id", "ortu@contoh.id"):
            headers = bearer(token_for(client, email))
            response = client.post(f"{CMS}/school/photo", headers=headers, files={"file": ("a.jpg", JPEG, "image/jpeg")})
            assert response.status_code == 403
        assert client.get(f"{PUBLIC}/sekolah").json()["foto_url"] is None

    def test_the_replacement_is_logged(self, client, db, adm):
        self.upload(client, adm)

        assert messages(db) == ["Admin Sekolah mengganti foto sekolah di beranda."]

    def test_delete_media_never_touches_files_outside_the_media_dir(self, tmp_path):
        from app.services.media_service import delete_media

        outside = tmp_path / "rahasia.jpg"
        outside.write_bytes(b"x")
        media = tmp_path / "media"
        media.mkdir()

        for url in ("/media/../rahasia.jpg", "/media/" + "a" * 32 + ".svg", "https://x.id/a.jpg", None, ""):
            delete_media(media, url)

        assert outside.exists()


def TestClientNoRaise(app):
    from fastapi.testclient import TestClient

    return TestClient(app, raise_server_exceptions=False)


class TestPosts:
    def create(self, client, adm, **override):
        return client.post(f"{CMS}/posts", headers=adm, json=post_body(**override))

    def test_create_appears_on_the_public_website_with_a_slug_from_the_title(self, client, adm):
        response = self.create(client, adm, judul="Gerakan Literasi Pagi: Dimulai!")

        assert response.status_code == 201
        body = response.json()
        assert body["slug"] == "gerakan-literasi-pagi-dimulai"
        assert set(body) == {"slug", "kategori", "judul", "ringkasan", "gambar_url", "tanggal", "status", "diperbarui", "isi"}
        public = client.get(f"{PUBLIC}/informasi/{body['slug']}").json()
        assert (public["judul"], public["kategori"], public["isi"]) == (
            "Gerakan Literasi Pagi: Dimulai!", "Berita", "Isi lengkap berita.",
        )

    def test_announcements_go_to_their_own_table_but_share_the_list(self, client, db, adm):
        self.create(client, adm, judul="Libur Semester", kategori="Pengumuman")
        self.create(client, adm, judul="Lomba Puisi", kategori="Kegiatan")

        assert [p.slug for p in rows(db, Pengumuman)] == ["libur-semester"]
        assert [b.slug for b in rows(db, Berita)] == ["lomba-puisi"]
        listed = client.get(f"{CMS}/posts", headers=adm).json()
        assert {p["kategori"] for p in listed} == {"Pengumuman", "Kegiatan"}
        assert all("isi" not in p for p in listed)

    def test_draft_is_listed_for_admin_but_hidden_from_the_public(self, client, adm):
        slug = self.create(client, adm, status="draft").json()["slug"]

        assert [p["slug"] for p in client.get(f"{CMS}/posts", headers=adm).json()] == [slug]
        assert client.get(f"{PUBLIC}/informasi").json() == []
        assert client.get(f"{PUBLIC}/informasi/{slug}").status_code == 404

    def test_slugs_stay_unique_across_both_tables(self, client, adm):
        first = self.create(client, adm, judul="Rapat Komite", kategori="Pengumuman").json()["slug"]
        second = self.create(client, adm, judul="Rapat Komite", kategori="Berita").json()["slug"]
        third = self.create(client, adm, judul="Rapat Komite", kategori="Berita").json()["slug"]

        assert [first, second, third] == ["rapat-komite", "rapat-komite-2", "rapat-komite-3"]

    def test_blank_summary_is_derived_from_the_content(self, client, adm):
        body = self.create(client, adm, ringkasan="", isi="Kalimat  pertama.\n" + "kata " * 80).json()

        assert body["ringkasan"].startswith("Kalimat pertama. kata") and body["ringkasan"].endswith("…")
        assert len(body["ringkasan"]) <= 161

    def test_date_defaults_to_today_on_create(self, client, adm):
        body = client.post(
            f"{CMS}/posts", headers=adm, json={"judul": "Tanpa Tanggal", "kategori": "Berita"}
        ).json()

        assert body["tanggal"] == TODAY and body["status"] == "draft"

    def test_update_keeps_the_slug_and_the_date_when_not_sent(self, client, adm):
        slug = self.create(client, adm).json()["slug"]
        body = post_body(judul="Judul Diubah", isi="Isi baru")
        del body["tanggal"]

        response = client.put(f"{CMS}/posts/{slug}", headers=adm, json=body)

        assert response.status_code == 200
        result = response.json()
        assert (result["slug"], result["judul"], result["isi"], result["tanggal"]) == (
            slug, "Judul Diubah", "Isi baru", "2026-10-01",
        )
        assert client.get(f"{PUBLIC}/informasi/{slug}").json()["judul"] == "Judul Diubah"

    def test_changing_category_across_tables_keeps_the_public_url(self, client, db, adm):
        slug = self.create(client, adm, kategori="Berita").json()["slug"]

        moved = client.put(f"{CMS}/posts/{slug}", headers=adm, json=post_body(kategori="Pengumuman"))
        back = client.put(f"{CMS}/posts/{slug}", headers=adm, json=post_body(kategori="PPDB"))

        assert moved.json()["kategori"] == "Pengumuman" and moved.json()["slug"] == slug
        assert back.json()["kategori"] == "PPDB"
        assert rows(db, Pengumuman) == [] and [b.slug for b in rows(db, Berita)] == [slug]
        assert client.get(f"{PUBLIC}/informasi/{slug}").json()["kategori"] == "PPDB"

    def test_unpublishing_removes_it_from_the_public_site(self, client, adm):
        slug = self.create(client, adm).json()["slug"]

        client.put(f"{CMS}/posts/{slug}", headers=adm, json=post_body(status="arsip"))

        assert client.get(f"{PUBLIC}/informasi").json() == []

    def test_delete(self, client, db, adm):
        slug = self.create(client, adm).json()["slug"]

        assert client.delete(f"{CMS}/posts/{slug}", headers=adm).status_code == 204

        assert rows(db, Berita) == []
        assert client.delete(f"{CMS}/posts/{slug}", headers=adm).status_code == 404
        assert client.get(f"{CMS}/posts/{slug}", headers=adm).status_code == 404

    @pytest.mark.parametrize(
        ("override", "field"),
        [
            ({"judul": "   "}, "judul"),
            ({"kategori": "Gosip"}, "kategori"),
            ({"status": "dihapus"}, "status"),
            ({"gambar_url": "javascript:alert(1)"}, "gambar_url"),
            ({"gambar_url": "data:text/html,x"}, "gambar_url"),
            ({"gambar_url": "/etc/passwd"}, "gambar_url"),
            ({"isi": "x" * 50001}, "isi"),
        ],
    )
    def test_invalid_input_is_a_field_error(self, client, db, adm, override, field):
        response = self.create(client, adm, **override)

        assert response.status_code == 422 and field in response.json()["errors"]
        assert rows(db, Berita) == []

    def test_images_may_be_uploads_or_http_links(self, client, adm):
        a = self.create(client, adm, judul="A", gambar_url="/media/abc.jpg").json()
        b = self.create(client, adm, judul="B", gambar_url="https://contoh.id/x.png").json()
        c = self.create(client, adm, judul="C", gambar_url="  ").json()

        assert (a["gambar_url"], b["gambar_url"], c["gambar_url"]) == (
            "/media/abc.jpg", "https://contoh.id/x.png", None,
        )

    def test_log_names_the_item_as_berita_or_pengumuman_never_by_its_category(self, client, db, adm):
        self.create(client, adm, judul="Satu", kategori="Akademik")
        self.create(client, adm, judul="Dua", kategori="PPDB")
        self.create(client, adm, judul="Tiga", kategori="Pengumuman")

        assert messages(db) == [
            'Admin Sekolah membuat berita "Satu".',
            'Admin Sekolah membuat berita "Dua".',
            'Admin Sekolah membuat pengumuman "Tiga".',
        ]

    def test_mutations_are_logged(self, client, db, adm):
        slug = self.create(client, adm, judul="Berita Satu").json()["slug"]
        client.put(f"{CMS}/posts/{slug}", headers=adm, json=post_body(judul="Berita Satu"))
        client.delete(f"{CMS}/posts/{slug}", headers=adm)

        assert messages(db) == [
            'Admin Sekolah membuat berita "Berita Satu".',
            'Admin Sekolah memperbarui berita "Berita Satu".',
            'Admin Sekolah menghapus berita/pengumuman "Berita Satu".',
        ]


class TestKegiatan:
    BODY = {"judul": "Latihan Pramuka", "kategori": "Ekstrakurikuler", "deskripsi": "Setiap pekan.",
            "status": "terbit", "tanggal": "2026-10-03", "foto_urls": ["/media/a.jpg", "https://x.id/b.png"]}

    def test_create_then_public_shows_photos_in_order(self, client, adm):
        response = client.post(f"{CMS}/kegiatan", headers=adm, json=self.BODY)

        assert response.status_code == 201
        assert response.json()["foto_urls"] == ["/media/a.jpg", "https://x.id/b.png"]
        public = client.get(f"{PUBLIC}/kegiatan/latihan-pramuka").json()
        assert [f["url"] for f in public["foto"]] == ["/media/a.jpg", "https://x.id/b.png"]
        assert public["gambar_url"] == "/media/a.jpg"

    def test_update_replaces_the_photo_list_and_delete_removes_photos(self, client, db, adm):
        client.post(f"{CMS}/kegiatan", headers=adm, json=self.BODY)

        updated = client.put(
            f"{CMS}/kegiatan/latihan-pramuka", headers=adm,
            json={**self.BODY, "judul": "Pramuka Pekan Ini", "foto_urls": ["/media/c.jpg"]},
        )

        assert updated.json()["foto_urls"] == ["/media/c.jpg"] and updated.json()["slug"] == "latihan-pramuka"
        assert [f.url for f in rows(db, KegiatanFoto)] == ["/media/c.jpg"]
        assert client.delete(f"{CMS}/kegiatan/latihan-pramuka", headers=adm).status_code == 204
        assert rows(db, Kegiatan) == [] and rows(db, KegiatanFoto) == []

    def test_drafts_are_admin_only_and_list_is_newest_first(self, client, adm):
        client.post(f"{CMS}/kegiatan", headers=adm, json={**self.BODY, "judul": "Lama", "tanggal": "2026-09-01"})
        client.post(f"{CMS}/kegiatan", headers=adm, json={**self.BODY, "judul": "Baru", "status": "draft"})

        assert [k["judul"] for k in client.get(f"{CMS}/kegiatan", headers=adm).json()] == ["Baru", "Lama"]
        assert [k["judul"] for k in client.get(f"{PUBLIC}/kegiatan").json()] == ["Lama"]

    @pytest.mark.parametrize(
        "override",
        [{"kategori": "Lain"}, {"foto_urls": ["javascript:x"]}, {"foto_urls": [f"/media/{i}.jpg" for i in range(21)]}],
    )
    def test_invalid_input_is_rejected(self, client, db, adm, override):
        assert client.post(f"{CMS}/kegiatan", headers=adm, json={**self.BODY, **override}).status_code == 422
        assert rows(db, Kegiatan) == []

    def test_unknown_slug_is_404(self, client, adm):
        assert client.put(f"{CMS}/kegiatan/x", headers=adm, json=self.BODY).status_code == 404
        assert client.delete(f"{CMS}/kegiatan/x", headers=adm).status_code == 404


class TestFasilitas:
    def test_crud_and_public_visibility(self, client, db, adm):
        a = client.post(f"{CMS}/fasilitas", headers=adm, json={"nama": "Perpustakaan"}).json()
        b = client.post(
            f"{CMS}/fasilitas", headers=adm,
            json={"nama": "Lab Komputer", "deskripsi": "Baru", "tampil": False, "gambar_url": "/media/x.jpg"},
        ).json()

        assert (a["urutan"], b["urutan"]) == (1, 2), "urutan otomatis menambah di akhir"
        assert [f["nama"] for f in client.get(f"{PUBLIC}/fasilitas").json()] == ["Perpustakaan"]
        assert [f["nama"] for f in client.get(f"{CMS}/fasilitas", headers=adm).json()] == ["Perpustakaan", "Lab Komputer"]

        updated = client.put(
            f"{CMS}/fasilitas/{b['id']}", headers=adm,
            json={"nama": "Lab Komputer", "tampil": True, "urutan": 0},
        ).json()
        assert (updated["tampil"], updated["urutan"], updated["gambar_url"]) == (True, 0, None)
        assert [f["nama"] for f in client.get(f"{PUBLIC}/fasilitas").json()] == ["Lab Komputer", "Perpustakaan"]

        assert client.delete(f"{CMS}/fasilitas/{a['id']}", headers=adm).status_code == 204
        assert [f.nama for f in rows(db, Fasilitas)] == ["Lab Komputer"]

    def test_validation_and_unknown_id(self, client, adm):
        assert client.post(f"{CMS}/fasilitas", headers=adm, json={"nama": " "}).status_code == 422
        assert client.post(f"{CMS}/fasilitas", headers=adm, json={"nama": "X", "urutan": -1}).status_code == 422
        assert client.put(f"{CMS}/fasilitas/999", headers=adm, json={"nama": "X"}).status_code == 404
        assert client.delete(f"{CMS}/fasilitas/999", headers=adm).status_code == 404


class TestFaq:
    BODY = {"kategori": "PPDB", "pertanyaan": "Kapan PPDB dibuka?", "jawaban": "Bulan Juni."}

    def test_crud_and_public_visibility(self, client, db, adm):
        a = client.post(f"{CMS}/faq", headers=adm, json=self.BODY).json()
        b = client.post(f"{CMS}/faq", headers=adm, json={**self.BODY, "pertanyaan": "Tersembunyi?", "tampil": False}).json()

        assert (a["urutan"], b["urutan"]) == (1, 2)
        assert [f["pertanyaan"] for f in client.get(f"{PUBLIC}/faq").json()] == ["Kapan PPDB dibuka?"]
        updated = client.put(f"{CMS}/faq/{b['id']}", headers=adm, json={**self.BODY, "pertanyaan": "Terlihat?"}).json()
        assert updated["tampil"] is True
        assert len(client.get(f"{PUBLIC}/faq").json()) == 2
        assert client.delete(f"{CMS}/faq/{a['id']}", headers=adm).status_code == 204
        assert [f.pertanyaan for f in rows(db, Faq)] == ["Terlihat?"]

    @pytest.mark.parametrize("override", [{"kategori": "Gosip"}, {"pertanyaan": " "}, {"jawaban": ""}])
    def test_invalid_input(self, client, adm, override):
        assert client.post(f"{CMS}/faq", headers=adm, json={**self.BODY, **override}).status_code == 422

    def test_unknown_id(self, client, adm):
        assert client.put(f"{CMS}/faq/999", headers=adm, json=self.BODY).status_code == 404
        assert client.delete(f"{CMS}/faq/999", headers=adm).status_code == 404


class TestMedia:
    def upload(self, client, adm, data, name="foto.jpg", content_type="image/jpeg"):
        return client.post(f"{CMS}/media", headers=adm, files={"file": (name, data, content_type)})

    @pytest.mark.parametrize(("data", "ext"), [(JPEG, "jpg"), (PNG, "png"), (WEBP, "webp")])
    def test_accepts_images_by_content_and_serves_them(self, client, adm, data, ext):
        response = self.upload(client, adm, data)

        assert response.status_code == 201
        body = response.json()
        assert body["url"].startswith("/media/") and body["url"].endswith(f".{ext}")
        assert body["ukuran"] == len(data)
        served = client.get(body["url"])
        assert served.status_code == 200 and served.content == data
        assert served.headers["x-content-type-options"] == "nosniff"

    def test_the_clients_filename_and_declared_type_are_ignored(self, client, adm):
        url = self.upload(client, adm, JPEG, name="../../etc/evil.html", content_type="text/html").json()["url"]

        assert url.startswith("/media/") and "evil" not in url and ".." not in url and url.endswith(".jpg")

    @pytest.mark.parametrize(
        "data", [b"<script>alert(1)</script>", b"<svg xmlns='http://www.w3.org/2000/svg'/>", b"GIF89a....", b"%PDF-1.4", b""]
    )
    def test_non_images_are_rejected_even_with_an_image_extension(self, client, adm, data):
        response = self.upload(client, adm, data, name="x.jpg")

        assert response.status_code == 422 and "file" in response.json()["errors"]

    def test_oversized_files_are_rejected(self, client, adm):
        assert self.upload(client, adm, JPEG + b"\x00" * (64 * 1024)).status_code == 413

    def test_missing_file_field_is_422(self, client, adm):
        assert client.post(f"{CMS}/media", headers=adm).status_code == 422

    def test_uploaded_image_url_can_be_used_in_content(self, client, adm):
        url = self.upload(client, adm, PNG).json()["url"]

        post = client.post(f"{CMS}/posts", headers=adm, json=post_body(gambar_url=url))

        assert post.status_code == 201 and post.json()["gambar_url"] == url


def test_slugify_handles_accents_symbols_and_length():
    assert slugify("Pembagian Rapor — Tengah Semester!") == "pembagian-rapor-tengah-semester"
    assert slugify("Café Résumé") == "cafe-resume"
    assert slugify("???") == "tanpa-judul"
    long = slugify("kata " * 50)
    assert len(long) <= 80 and not long.endswith("-")
