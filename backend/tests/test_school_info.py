from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select, text

from app.models import HalamanSitus, InformasiKelas, KalenderAkademik, LogAktivitas
from app.models.base import UserRole
from tests.factories import make_guru, make_user
from tests.test_auth import bearer, token_for

CMS = "/api/v1/admin/cms"
PUBLIC = "/api/v1/public"
JKT = ZoneInfo("Asia/Jakarta")


@pytest.fixture
def adm(app, client, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    make_user(db, UserRole.ADMIN, "admin@contoh.id", "Admin Sekolah")
    make_guru(db, "rina@contoh.id", "Bu Rina")
    return bearer(token_for(client, "admin@contoh.id"))


def rows(db, model):
    db.expire_all()
    return list(db.scalars(select(model).order_by(model.id)))


def info_body(**override):
    return {"tingkat": 3, "jenis": "Pembelajaran", "judul": "Perkalian", "deskripsi": "Tabel 1-10.", **override}


def event_body(**override):
    return {"judul": "Asesmen", "kategori": "Ujian", "tanggal_mulai": "2026-10-12", **override}


class TestAuthorization:
    ENDPOINTS = [
        ("get", "/kelas"), ("post", "/kelas"), ("put", "/kelas/1"), ("delete", "/kelas/1"),
        ("get", "/kalender"), ("post", "/kalender"), ("put", "/kalender/1"), ("delete", "/kalender/1"),
    ]

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    def test_requires_a_token(self, client, adm, method, path):
        assert client.request(method, f"{CMS}{path}").status_code == 401

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    def test_guru_is_forbidden(self, client, adm, method, path):
        headers = bearer(token_for(client, "rina@contoh.id"))
        assert client.request(method, f"{CMS}{path}", headers=headers, json={}).status_code == 403


class TestClassInfo:
    def test_create_defaults_to_the_end_of_its_own_list(self, client, adm):
        a = client.post(f"{CMS}/kelas", headers=adm, json=info_body()).json()
        b = client.post(f"{CMS}/kelas", headers=adm, json=info_body(judul="Pecahan")).json()
        other = client.post(f"{CMS}/kelas", headers=adm, json=info_body(jenis="Kegiatan", judul="Pramuka")).json()

        assert (a["urutan"], b["urutan"], other["urutan"]) == (1, 2, 1)
        assert set(a) == {"id", "tingkat", "jenis", "judul", "deskripsi", "urutan", "tampil"}

    def test_public_list_shows_only_visible_entries_grouped_by_class_and_order(self, client, adm):
        client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=2, judul="B"))
        client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=1, judul="A"))
        client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=1, judul="Tersembunyi", tampil=False))
        client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=1, judul="C", urutan=0))

        public = client.get(f"{PUBLIC}/kelas").json()

        assert [(i["tingkat"], i["judul"]) for i in public] == [(1, "C"), (1, "A"), (2, "B")]
        assert set(public[0]) == {"id", "tingkat", "jenis", "judul", "deskripsi"}
        assert [i["judul"] for i in client.get(f"{PUBLIC}/kelas?tingkat=2").json()] == ["B"]
        assert len(client.get(f"{CMS}/kelas", headers=adm).json()) == 4

    def test_update_changes_fields_and_moving_to_another_class_goes_last(self, client, adm):
        first = client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=4)).json()
        item = client.post(f"{CMS}/kelas", headers=adm, json=info_body(tingkat=3)).json()

        moved = client.put(f"{CMS}/kelas/{item['id']}", headers=adm, json=info_body(tingkat=4, judul="Baru")).json()
        stayed = client.put(f"{CMS}/kelas/{first['id']}", headers=adm, json=info_body(tingkat=4, urutan=7)).json()

        assert (moved["tingkat"], moved["judul"], moved["urutan"]) == (4, "Baru", 2)
        assert stayed["urutan"] == 7

    def test_delete(self, client, db, adm):
        item = client.post(f"{CMS}/kelas", headers=adm, json=info_body()).json()

        assert client.delete(f"{CMS}/kelas/{item['id']}", headers=adm).status_code == 204
        assert rows(db, InformasiKelas) == []
        assert client.delete(f"{CMS}/kelas/{item['id']}", headers=adm).status_code == 404

    @pytest.mark.parametrize(
        ("override", "field"),
        [
            ({"tingkat": 0}, "tingkat"), ({"tingkat": 7}, "tingkat"), ({"jenis": "Lain"}, "jenis"),
            ({"judul": "  "}, "judul"), ({"urutan": -1}, "urutan"), ({"deskripsi": "x" * 5001}, "deskripsi"),
        ],
    )
    def test_invalid_input_is_a_field_error(self, client, db, adm, override, field):
        response = client.post(f"{CMS}/kelas", headers=adm, json=info_body(**override))

        assert response.status_code == 422 and field in response.json()["errors"]
        assert rows(db, InformasiKelas) == []

    def test_unknown_id_is_404_and_changes_are_logged(self, client, db, adm):
        assert client.put(f"{CMS}/kelas/999", headers=adm, json=info_body()).status_code == 404
        item = client.post(f"{CMS}/kelas", headers=adm, json=info_body()).json()
        client.delete(f"{CMS}/kelas/{item['id']}", headers=adm)

        assert [r.pesan for r in rows(db, LogAktivitas)] == [
            'Admin Sekolah menambahkan informasi kelas 3 "Perkalian".',
            'Admin Sekolah menghapus informasi kelas 3 "Perkalian".',
        ]

    def test_the_database_itself_rejects_a_bad_class_level(self, db):
        with pytest.raises(Exception):
            db.execute(text("INSERT INTO informasi_kelas (tingkat, jenis, judul) VALUES (9, 'Kegiatan', 'x')"))
        db.rollback()


class TestCalendar:
    def test_create_and_public_list_sorted_by_date_without_hidden_entries(self, client, adm):
        client.post(f"{CMS}/kalender", headers=adm, json=event_body(judul="Akhir", tanggal_mulai="2026-12-20"))
        client.post(f"{CMS}/kalender", headers=adm, json=event_body(judul="Awal", tanggal_mulai="2026-07-13"))
        client.post(f"{CMS}/kalender", headers=adm, json=event_body(judul="Rahasia", tampil=False))

        public = client.get(f"{PUBLIC}/kalender").json()

        assert [e["judul"] for e in public] == ["Awal", "Akhir"]
        assert set(public[0]) == {"id", "judul", "deskripsi", "kategori", "tanggal_mulai", "tanggal_selesai"}
        assert len(client.get(f"{CMS}/kalender", headers=adm).json()) == 3

    def test_a_one_day_event_has_no_end_date_and_a_range_keeps_it(self, client, adm):
        one = client.post(
            f"{CMS}/kalender", headers=adm, json=event_body(tanggal_selesai="2026-10-12")
        ).json()
        span = client.post(
            f"{CMS}/kalender", headers=adm, json=event_body(judul="Libur", kategori="Libur", tanggal_selesai="2026-10-20")
        ).json()

        assert one["tanggal_selesai"] is None
        assert span["tanggal_selesai"] == "2026-10-20"

    def test_update_and_delete(self, client, db, adm):
        item = client.post(f"{CMS}/kalender", headers=adm, json=event_body()).json()

        updated = client.put(
            f"{CMS}/kalender/{item['id']}", headers=adm,
            json=event_body(judul="Asesmen Akhir", kategori="Rapat", tanggal_mulai="2026-11-01"),
        ).json()
        assert (updated["judul"], updated["kategori"], updated["tanggal_mulai"]) == ("Asesmen Akhir", "Rapat", "2026-11-01")

        assert client.delete(f"{CMS}/kalender/{item['id']}", headers=adm).status_code == 204
        assert rows(db, KalenderAkademik) == []
        assert client.put(f"{CMS}/kalender/{item['id']}", headers=adm, json=event_body()).status_code == 404

    @pytest.mark.parametrize(
        ("override", "field", "message"),
        [
            ({"tanggal_selesai": "2026-10-01"}, "tanggal_selesai", "Tanggal selesai tidak boleh sebelum tanggal mulai."),
            ({"kategori": "Pesta"}, "kategori", "Nilai tidak valid."),
            ({"judul": " "}, "judul", "Kolom ini wajib diisi."),
            ({"tanggal_mulai": "bukan-tanggal"}, "tanggal_mulai", "Nilai tidak valid."),
        ],
    )
    def test_invalid_input_has_a_readable_field_message(self, client, db, adm, override, field, message):
        response = client.post(f"{CMS}/kalender", headers=adm, json=event_body(**override))

        assert response.status_code == 422
        assert response.json()["errors"][field] == message
        assert rows(db, KalenderAkademik) == []

    def test_start_date_is_required(self, client, adm):
        body = event_body()
        del body["tanggal_mulai"]

        assert client.post(f"{CMS}/kalender", headers=adm, json=body).status_code == 422


class TestMigration:
    def test_old_class_texts_become_class_info_and_their_keys_disappear(self, db):
        db.execute(text("DELETE FROM informasi_kelas"))
        db.add_all([
            HalamanSitus(kunci="kelas-2", isi="Teks lama kelas 2"),
            HalamanSitus(kunci="kelas-5", isi="   "),
            HalamanSitus(kunci="visi", isi="Tetap"),
        ])
        db.commit()
        sql = (__import__("pathlib").Path(__file__).resolve().parents[1] / "db/migrations/003_class_info_calendar.sql").read_text()

        db.connection().connection.execute(sql)  # dijalankan dua kali: harus idempoten
        db.connection().connection.execute(sql)
        db.commit()

        migrated = rows(db, InformasiKelas)
        assert [(m.tingkat, m.jenis, m.deskripsi) for m in migrated] == [(2, "Pembelajaran", "Teks lama kelas 2")]
        assert [h.kunci for h in rows_pages(db)] == ["visi"]


def rows_pages(db):
    db.expire_all()
    return list(db.scalars(select(HalamanSitus).order_by(HalamanSitus.kunci)))
