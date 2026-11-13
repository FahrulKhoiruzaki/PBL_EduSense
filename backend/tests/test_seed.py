from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import func, select

from app.models import Absensi, Kelas, Nilai, Siswa, User
from scripts import seed
from tests.test_auth import bearer, login

API = "/api/v1"
JKT = ZoneInfo("Asia/Jakarta")


@pytest.fixture
def seeded(app, db):
    app.state.clock = lambda: datetime.now(JKT)
    seed.populate(db, JKT)


def token(client, email, password=seed.DEMO_PASSWORD):
    response = login(client, email, password)
    assert response.status_code == 200, (email, response.text)
    return response.json()["token"]


def test_every_demo_account_can_log_in_with_the_documented_password(client, seeded):
    demo = [
        (seed.ADMIN_EMAIL, seed.DEMO_PASSWORD, "admin"),
        *[(f"{g.key}@{seed.DOMAIN}", seed.TEMP_PASSWORD if g.temporary else seed.DEMO_PASSWORD, "guru")
          for g in seed.GURU],
        *[(f"ortu.{key}@{seed.DOMAIN}", seed.DEMO_PASSWORD, "ortu") for key in seed.PARENTS],
    ]

    for email, password, role in demo:
        response = login(client, email, password)
        assert response.status_code == 200, email
        assert response.json()["user"]["role"] == role


def test_only_the_temporary_guru_must_change_password(client, seeded):
    flags = {
        g.key: login(client, f"{g.key}@{seed.DOMAIN}", seed.TEMP_PASSWORD if g.temporary else seed.DEMO_PASSWORD)
        .json()["user"]["must_change_password"]
        for g in seed.GURU
    }

    assert flags == {"rina": False, "andi": False, "sari": False, "hadi": True}


def test_guru_sessions_carry_the_class_relations(client, seeded):
    def session(key):
        password = seed.TEMP_PASSWORD if key == "hadi" else seed.DEMO_PASSWORD
        headers = bearer(token(client, f"{key}@{seed.DOMAIN}", password))
        return client.get(f"{API}/auth/me", headers=headers).json()

    assert session("rina")["guru"] == {"nip": "198504122010012001", "wali_kelas": ["5A"], "mapel": ["5B"]}
    assert session("andi")["guru"]["wali_kelas"] == [] and session("andi")["guru"]["mapel"] == ["5A", "5B"]
    assert session("sari")["guru"]["wali_kelas"] == ["5B"]
    assert session("hadi")["guru"]["mapel"] == []
    assert session("rina")["pengaturan"]["batas_jam_terlambat"] == "07:15"


def test_guru_dashboard_loads_classes_with_students_grades_and_trends(client, seeded):
    headers = bearer(token(client, f"andi@{seed.DOMAIN}"))

    classes = {c["kelas"]: c for c in client.get(f"{API}/guru/classes", headers=headers).json()}
    detail = client.get(f"{API}/guru/classes/5A", headers=headers).json()

    assert {k: classes[k]["jumlah_siswa"] for k in ("5A", "5B")} == {"5A": 4, "5B": 4}
    assert [s["nama"] for s in detail["siswa"]] == sorted(s["nama"] for s in detail["siswa"])
    assert all(s["status"] is None for s in detail["siswa"]), "absensi hari ini harus kosong"
    assert len(detail["nilai"]) == 4 * 12
    assert detail["rata_literasi"] > 0 and len(detail["tren"]["literasi"]) >= 4
    assert len(detail["tren"]["kehadiran"]) >= 4
    assert [s["nama"] for s in detail["siswa"] if s["menurun"]] == ["Dimas Arya"]


def test_mapel_guru_can_record_in_both_classes_and_a_wali_can_record_in_the_class_she_teaches(client, seeded):
    andi, rina = (bearer(token(client, f"{k}@{seed.DOMAIN}")) for k in ("andi", "rina"))
    body = {"status": "H", "metode_input": "manual"}

    def record(headers, code):
        student = client.get(f"{API}/guru/classes/{code}", headers=headers).json()["siswa"][0]["id"]
        return client.put(f"{API}/guru/classes/{code}/attendance/{student}", json=body, headers=headers)

    assert record(andi, "5A").status_code == 204
    assert record(andi, "5B").status_code == 204
    assert record(rina, "5B").status_code == 204
    assert record(rina, "5A").status_code == 403


def test_a_wali_who_does_not_teach_the_class_cannot_record_there(client, seeded):
    sari = bearer(token(client, f"sari@{seed.DOMAIN}"))
    student = client.get(f"{API}/guru/classes/5B", headers=sari).json()["siswa"][0]["id"]

    response = client.put(
        f"{API}/guru/classes/5B/attendance/{student}", json={"status": "H", "metode_input": "manual"}, headers=sari
    )

    assert response.status_code == 403


def test_guru_notifications_and_activities_are_not_empty(client, seeded):
    headers = bearer(token(client, f"rina@{seed.DOMAIN}"))

    notes = client.get(f"{API}/guru/notifications", headers=headers).json()
    activities = client.get(f"{API}/guru/activities", headers=headers).json()

    assert {n["kelompok"] for n in notes} == {"hari_ini", "sebelumnya"}
    assert any(not n["dibaca"] for n in notes)
    assert activities


def test_parent_with_two_children_sees_both_with_real_numbers(client, seeded):
    headers = bearer(token(client, f"ortu.wijaya@{seed.DOMAIN}"))

    kids = client.get(f"{API}/ortu/children", headers=headers).json()

    assert [(k["nama"], k["kelas"]) for k in kids] == [("Ahmad Rizky Wijaya", "5A"), ("Salsa Wijaya", "5B")]
    ahmad = kids[0]
    assert ahmad["klasifikasi"] == "Cukup" and ahmad["nis"] == "2024001"
    assert ahmad["literasi"] > 0 and ahmad["numerasi"] > 0 and 0 < ahmad["persen_kehadiran"] <= 100
    assert len(ahmad["nilai"]) == 12 and len(ahmad["riwayat_klasifikasi"]) == 3
    assert ahmad["wali_kelas"] == "Bu Rina Wulandari"
    assert ahmad["tahun_ajaran"] == seed.academic_year(datetime.now(JKT).date())
    assert len(ahmad["tren"]["literasi"]) >= 4


def test_parent_attendance_history_and_notifications_have_data(client, seeded):
    headers = bearer(token(client, f"ortu.wijaya@{seed.DOMAIN}"))
    kid = client.get(f"{API}/ortu/children", headers=headers).json()[0]["id"]

    attendance = client.get(f"{API}/ortu/children/{kid}/attendance", headers=headers).json()
    history = client.get(f"{API}/ortu/children/{kid}/history", headers=headers).json()
    notes = client.get(f"{API}/ortu/notifications", headers=headers).json()

    assert len(attendance) == 28
    assert {h["jenis"] for h in history} >= {"nilai", "klasifikasi"}
    assert notes and any(not n["dibaca"] for n in notes)


def test_parents_cannot_see_each_others_children(client, seeded, db):
    other = db.scalar(select(Siswa.id).where(Siswa.nama == "Dimas Arya"))
    headers = bearer(token(client, f"ortu.wijaya@{seed.DOMAIN}"))

    assert client.get(f"{API}/ortu/children/{other}/history", headers=headers).status_code == 404


def test_admin_panel_loads_every_list(client, seeded):
    headers = bearer(token(client, seed.ADMIN_EMAIL))

    def get(path):
        response = client.get(f"{API}/admin{path}", headers=headers)
        assert response.status_code == 200, path
        return response.json()

    assert len(get("/guru")) == 4 and len(get("/siswa")) == 8 and len(get("/admins")) == 1
    classes = {c["kode"]: c for c in get("/classes")}
    assert set(classes) == {"5A", "5B", "6A"} and classes["6A"] == {"kode": "6A", "wali_id": None, "mapel_ids": []}
    assert classes["5A"]["wali_id"] is not None and len(classes["5A"]["mapel_ids"]) == 2
    assert get("/settings") == {"tahun_ajaran": seed.academic_year(datetime.now(JKT).date()), "batas_jam_terlambat": "07:15"}
    assert len(get("/logs")) >= 8
    assert get("/me")["email"] == seed.ADMIN_EMAIL


def test_admin_roles_follow_assignments(client, seeded):
    headers = bearer(token(client, seed.ADMIN_EMAIL))

    roles = {g["nama"]: g["peran"] for g in client.get(f"{API}/admin/guru", headers=headers).json()}

    assert roles == {
        "Bu Rina Wulandari": "wali", "Pak Andi Pratama": "mapel",
        "Bu Sari Dewi": "wali", "Pak Hadi Nugroho": "mapel",
    }


def test_the_empty_class_can_be_deleted_but_filled_ones_cannot(client, seeded):
    headers = bearer(token(client, seed.ADMIN_EMAIL))

    assert client.delete(f"{API}/admin/classes/6A", headers=headers).status_code == 204
    assert client.delete(f"{API}/admin/classes/5A", headers=headers).status_code == 409


def test_public_website_shows_published_content_only(client, seeded):
    news = client.get(f"{API}/public/informasi").json()
    titles = [n["judul"] for n in news]

    assert len(news) == 6 and {n["kategori"] for n in news} == {"Pengumuman", "Berita", "Akademik", "PPDB", "Kegiatan"}
    assert "Berita Konsep" not in titles and "Rapat Komite Sekolah" not in titles
    assert "Pengumuman Tahun Lalu" not in titles
    assert client.get(f"{API}/public/informasi/libur-semester-ganjil").json()["isi"]
    assert len(client.get(f"{API}/public/kegiatan").json()) == 4
    assert [f["nama"] for f in client.get(f"{API}/public/fasilitas").json()] == [
        "Perpustakaan", "Ruang Kelas", "Lapangan Olahraga",
    ]
    assert len(client.get(f"{API}/public/faq").json()) == 7
    assert len(client.get(f"{API}/public/guru").json()) == 4
    assert client.get(f"{API}/public/sekolah").json()["nama"] == "SDN 02 Pakunden"


def test_every_page_key_the_website_reads_has_text(client, seeded):
    pages = {p["kunci"]: p["isi"] for p in client.get(f"{API}/public/halaman").json()}
    from app.services import cms_pages

    required = {p.kunci for p in cms_pages.PAGES}

    assert required <= set(pages) and all(pages[k].strip() for k in required)


def test_class_info_covers_every_level_and_the_calendar_hides_internal_entries(client, seeded):
    info = client.get(f"{API}/public/kelas").json()
    calendar = client.get(f"{API}/public/kalender").json()

    assert {i["tingkat"] for i in info} == {1, 2, 3, 4, 5, 6}
    assert {i["jenis"] for i in info} == {"Pembelajaran", "Kegiatan"}
    assert "Masa pengenalan (disembunyikan)" not in [i["judul"] for i in info]
    titles = [e["judul"] for e in calendar]
    assert "Agenda internal guru" not in titles and len(titles) == 6
    assert [e["tanggal_mulai"] for e in calendar] == sorted(e["tanggal_mulai"] for e in calendar)
    assert any(e["tanggal_selesai"] for e in calendar)


def test_today_is_left_empty_and_history_never_includes_weekends_or_today(db, seeded):
    today = datetime.now(JKT).date()
    dates = set(db.scalars(select(Absensi.tanggal)))

    assert today not in dates and all(d.weekday() < 5 for d in dates)
    assert max(db.scalars(select(Nilai.tanggal))) < today


def test_seeding_after_the_migration_defaults_does_not_collide(db, client):
    from app.models import HalamanSitus

    db.add(HalamanSitus(kunci="hero-title", isi="Bawaan migrasi"))
    db.commit()

    seed.populate(db, JKT)

    pages = {p["kunci"]: p["isi"] for p in client.get(f"{API}/public/halaman").json()}
    assert pages["hero-title"] == seed.PAGES["hero-title"]


def test_seeding_is_all_or_nothing(db, monkeypatch):
    monkeypatch.setattr(seed, "seed_website", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))

    with pytest.raises(RuntimeError):
        seed.populate(db, JKT)

    assert db.scalar(select(func.count()).select_from(User)) == 0
    assert db.scalar(select(func.count()).select_from(Kelas)) == 0
