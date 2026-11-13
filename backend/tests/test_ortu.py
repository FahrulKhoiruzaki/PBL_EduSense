from datetime import date, datetime, time
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app.models import Absensi, Nilai, Notifikasi, RiwayatKlasifikasi
from app.models.base import (
    KategoriNilai,
    Klasifikasi,
    MetodeInput,
    StatusAbsensi,
    UserRole,
)
from app.services.guru_service import AUTO_ALPA_NOTE
from tests.factories import make_class, make_guru, make_student, make_user
from tests.test_auth import bearer, token_for
from tests.test_face import image, upload

API = "/api/v1/ortu"
GURU = "/api/v1/guru"
JKT = ZoneInfo("Asia/Jakarta")
H, T, I, S, A = (StatusAbsensi.HADIR, StatusAbsensi.TERLAMBAT, StatusAbsensi.IZIN,
                 StatusAbsensi.SAKIT, StatusAbsensi.ALPA)


@pytest.fixture
def school(app, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    rina = make_guru(db, "rina@contoh.id", "Bu Rina")
    andi = make_guru(db, "andi@contoh.id", "Pak Andi")
    kelas_a = make_class(db, "5A", wali=rina, mapel=(andi,))
    kelas_b = make_class(db, "5B", mapel=(andi,))
    parent = make_user(db, UserRole.ORTU, "ibu.ahmad@contoh.id", "Ibu Ahmad").ortu_profile
    other = make_user(db, UserRole.ORTU, "bapak.budi@contoh.id", "Bapak Budi").ortu_profile
    ahmad = make_student(db, "Ahmad Rizky", kelas_a, ortu=parent)
    siti = make_student(db, "Siti Aulia", kelas_a, ortu=parent)
    budi = make_student(db, "Budi Santoso", kelas_b, ortu=other)
    return {
        "rina": rina, "andi": andi, "a": kelas_a, "ahmad": ahmad, "siti": siti, "budi": budi,
        "parent": parent, "other": other,
    }


@pytest.fixture
def auth(client, school):
    return lambda email: bearer(token_for(client, email))


@pytest.fixture
def ibu(auth):
    return auth("ibu.ahmad@contoh.id")


def add_attendance(db, siswa, tanggal, status, *, waktu=None, catatan=None):
    db.add(
        Absensi(
            siswa_id=siswa.id, tanggal=tanggal, status=status, waktu=waktu, catatan=catatan,
            metode_input=MetodeInput.MANUAL,
        )
    )
    db.commit()


def add_grade(db, siswa, tanggal, value, category=KategoriNilai.LITERASI, note=None, kind="Ulangan"):
    row = Nilai(
        siswa_id=siswa.id, kategori=category, jenis_ujian=kind, nilai=Decimal(str(value)),
        tanggal=tanggal, catatan_guru=note,
    )
    db.add(row)
    db.commit()
    return row


@pytest.fixture
def ahmad_data(db, school):
    ahmad = school["ahmad"]
    ahmad.status_klasifikasi = Klasifikasi.CUKUP
    db.add_all(
        [
            RiwayatKlasifikasi(siswa_id=ahmad.id, periode=date(2026, 8, 1), klasifikasi=Klasifikasi.MAHIR),
            RiwayatKlasifikasi(siswa_id=ahmad.id, periode=date(2026, 10, 1), klasifikasi=Klasifikasi.CUKUP),
        ]
    )
    db.commit()
    add_attendance(db, ahmad, date(2026, 6, 15), H, waktu=time(7, 0))
    add_attendance(db, ahmad, date(2026, 10, 5), H, waktu=time(7, 10))
    add_attendance(db, ahmad, date(2026, 10, 6), T, waktu=time(7, 52))
    add_attendance(db, ahmad, date(2026, 10, 7), S, catatan="Demam")
    add_attendance(db, ahmad, date(2026, 10, 8), A, catatan=AUTO_ALPA_NOTE)
    add_grade(db, ahmad, date(2026, 10, 1), 80)
    add_grade(db, ahmad, date(2026, 10, 2), 60, KategoriNilai.NUMERASI)
    add_grade(db, ahmad, date(2026, 10, 5), 90, note="Hebat")


def get(client, path, headers):
    return client.get(f"{API}{path}", headers=headers)


class TestAuthorization:
    @pytest.mark.parametrize(
        "path", ["/children", "/children/1/attendance", "/children/1/history", "/notifications"]
    )
    def test_requires_a_token(self, client, school, path):
        assert client.get(f"{API}{path}").status_code == 401

    @pytest.mark.parametrize("email", ["andi@contoh.id", "rina@contoh.id"])
    def test_guru_cannot_use_parent_endpoints(self, client, auth, school, email):
        assert get(client, "/children", auth(email)).status_code == 403
        assert get(client, "/notifications", auth(email)).status_code == 403


class TestChildren:
    def test_lists_only_the_parents_own_children(self, client, ibu, school):
        body = get(client, "/children", ibu).json()

        assert [c["nama"] for c in body] == ["Ahmad Rizky", "Siti Aulia"]
        assert [c["id"] for c in body] == [school["ahmad"].id, school["siti"].id]

    def test_another_parent_sees_a_different_list(self, client, auth, school):
        body = get(client, "/children", auth("bapak.budi@contoh.id")).json()

        assert [(c["nama"], c["kelas"]) for c in body] == [("Budi Santoso", "5B")]
        assert body[0]["wali_kelas"] is None

    def test_parent_without_children_gets_an_empty_list(self, client, db, auth, school):
        make_user(db, UserRole.ORTU, "kosong@contoh.id", "Ortu Kosong")

        assert get(client, "/children", auth("kosong@contoh.id")).json() == []

    def test_child_without_any_records_has_zero_stats(self, client, ibu, school):
        siti = next(c for c in get(client, "/children", ibu).json() if c["nama"] == "Siti Aulia")

        assert siti["klasifikasi"] is None
        assert (siti["literasi"], siti["numerasi"], siti["persen_kehadiran"], siti["jumlah_terlambat"]) == (0, 0, 0, 0)
        assert siti["tren"] == {"literasi": [], "numerasi": [], "kehadiran": []}
        assert siti["nilai"] == [] and siti["riwayat_klasifikasi"] == []
        assert siti["wali_kelas"] == "Bu Rina"
        assert siti["tahun_ajaran"] == "2026/2027"

    def test_overview_has_the_shape_the_flutter_app_parses(self, client, ibu, school, ahmad_data):
        ahmad = get(client, "/children", ibu).json()[0]

        assert set(ahmad) == {
            "id", "nis", "nama", "kelas", "klasifikasi", "literasi", "numerasi", "persen_kehadiran",
            "jumlah_terlambat", "tren", "riwayat_klasifikasi", "nilai", "wali_kelas", "tahun_ajaran",
            "diperbarui",
        }
        assert (ahmad["kelas"], ahmad["klasifikasi"], ahmad["wali_kelas"]) == ("5A", "Cukup", "Bu Rina")
        assert ahmad["literasi"] == 85 and ahmad["numerasi"] == 60

    def test_attendance_figures_only_count_the_current_academic_year(self, client, ibu, school, ahmad_data):
        ahmad = get(client, "/children", ibu).json()[0]

        # Hadir 10-05, Terlambat 10-06 dari 4 hari tahun ajaran ini; 15 Juni 2026 tidak dihitung.
        assert ahmad["persen_kehadiran"] == 50
        assert ahmad["jumlah_terlambat"] == 1

    def test_trends_are_oldest_first_weekly_series(self, client, ibu, school, ahmad_data):
        ahmad = get(client, "/children", ibu).json()[0]

        assert ahmad["tren"] == {"literasi": [80, 90], "numerasi": [60], "kehadiran": [100, 50]}

    def test_grades_are_newest_first_with_the_previous_value(self, client, ibu, school, ahmad_data):
        grades = get(client, "/children", ibu).json()[0]["nilai"]

        assert [(g["tanggal"], g["nilai"], g["nilai_sebelumnya"]) for g in grades] == [
            ("2026-10-05", 90.0, 80.0),
            ("2026-10-02", 60.0, None),
            ("2026-10-01", 80.0, None),
        ]
        assert set(grades[0]) == {
            "id", "kategori", "jenis_ujian", "nilai", "nilai_sebelumnya", "tanggal", "catatan_guru",
        }
        assert grades[0]["catatan_guru"] == "Hebat"

    def test_classification_history_uses_month_names_oldest_first(self, client, ibu, school, ahmad_data):
        history = get(client, "/children", ibu).json()[0]["riwayat_klasifikasi"]

        assert history == [
            {"bulan": "Agustus", "klasifikasi": "Mahir"},
            {"bulan": "Oktober", "klasifikasi": "Cukup"},
        ]

    def test_current_classification_is_shown_even_without_history(self, client, db, ibu, school):
        school["siti"].status_klasifikasi = Klasifikasi.PERLU_PENDAMPINGAN
        db.commit()

        siti = next(c for c in get(client, "/children", ibu).json() if c["nama"] == "Siti Aulia")

        assert siti["riwayat_klasifikasi"] == [{"bulan": "Oktober", "klasifikasi": "Perlu Pendampingan"}]

    def test_updated_timestamp_has_no_zone_so_the_date_is_not_shifted(self, client, ibu, school, ahmad_data):
        value = get(client, "/children", ibu).json()[0]["diperbarui"]

        assert datetime.fromisoformat(value).tzinfo is None


class TestAttendance:
    def test_returns_days_oldest_first_and_hides_the_internal_auto_note(self, client, ibu, school, ahmad_data):
        body = get(client, f"/children/{school['ahmad'].id}/attendance", ibu).json()

        assert [(d["tanggal"], d["status"]) for d in body] == [
            ("2026-06-15", "H"), ("2026-10-05", "H"), ("2026-10-06", "T"),
            ("2026-10-07", "S"), ("2026-10-08", "A"),
        ]
        by_date = {d["tanggal"]: d for d in body}
        assert by_date["2026-10-06"]["waktu"] == "07:52:00"
        assert by_date["2026-10-07"]["catatan"] == "Demam"
        assert by_date["2026-10-08"]["catatan"] is None

    def test_records_older_than_a_year_are_left_out(self, client, db, ibu, school):
        add_attendance(db, school["ahmad"], date(2025, 9, 1), H, waktu=time(7, 0))
        add_attendance(db, school["ahmad"], date(2025, 11, 1), H, waktu=time(7, 0))

        body = get(client, f"/children/{school['ahmad'].id}/attendance", ibu).json()

        assert [d["tanggal"] for d in body] == ["2025-11-01"]

    def test_other_parents_child_and_unknown_child_are_404(self, client, ibu, school):
        assert get(client, f"/children/{school['budi'].id}/attendance", ibu).status_code == 404
        assert get(client, "/children/9999/attendance", ibu).status_code == 404


class TestHistory:
    def test_merges_grades_attendance_and_classification_newest_first(self, client, ibu, school, ahmad_data):
        body = get(client, f"/children/{school['ahmad'].id}/history", ibu).json()

        dates = [i["tanggal"] for i in body]
        assert dates == sorted(dates, reverse=True)
        by_kind = {k: [i for i in body if i["jenis"] == k] for k in ("nilai", "kehadiran", "klasifikasi")}
        assert [(i["judul"], i["keterangan"]) for i in by_kind["kehadiran"]] == [
            ("Alpa", ""), ("Sakit", "Demam"), ("Terlambat", "Tiba pukul 07:52."),
        ]
        assert [(i["judul"], i["keterangan"]) for i in by_kind["nilai"]] == [
            ("Literasi 90", "Hebat"),
            ("Numerasi 60", "Nilai pertama untuk kategori ini."),
            ("Literasi 80", "Nilai pertama untuk kategori ini."),
        ]
        assert [(i["judul"], i["keterangan"]) for i in by_kind["klasifikasi"]] == [
            ("Cukup", "Berubah dari Mahir pada bulan lalu."),
            ("Mahir", "Klasifikasi pertama yang tercatat."),
        ]

    def test_present_days_are_not_history_entries(self, client, ibu, school, ahmad_data):
        body = get(client, f"/children/{school['ahmad'].id}/history", ibu).json()

        assert all(i["judul"] != "Hadir" for i in body)

    def test_grade_without_a_note_describes_the_change(self, client, db, ibu, school):
        add_grade(db, school["siti"], date(2026, 10, 1), 70)
        add_grade(db, school["siti"], date(2026, 10, 5), 64)

        body = get(client, f"/children/{school['siti'].id}/history", ibu).json()

        assert body[0] == {
            "jenis": "nilai", "tanggal": "2026-10-05", "judul": "Literasi 64",
            "keterangan": "Turun 6 poin dari nilai sebelumnya.",
        }

    def test_other_parents_child_is_404(self, client, ibu, school):
        assert get(client, f"/children/{school['budi'].id}/history", ibu).status_code == 404


class TestNotifications:
    def guru_put_attendance(self, client, auth, siswa, status):
        return client.put(
            f"{GURU}/classes/5A/attendance/{siswa.id}",
            json={"status": status, "metode_input": "manual"},
            headers=auth("andi@contoh.id"),
        )

    def parent_notes(self, db, parent):
        db.expire_all()
        return list(
            db.scalars(select(Notifikasi).where(Notifikasi.user_id == parent.user_id).order_by(Notifikasi.id))
        )

    def test_new_grade_notifies_the_childs_parent_with_the_grade_id(self, client, db, auth, ibu, school):
        grade_id = client.post(
            f"{GURU}/classes/5A/grades",
            json={
                "siswa_id": school["ahmad"].id, "kategori": "Numerasi", "jenis_ujian": "Kuis",
                "nilai": 88, "tanggal": "2026-10-08", "catatan_guru": "",
            },
            headers=auth("andi@contoh.id"),
        ).json()["id"]

        (item,) = get(client, "/notifications", ibu).json()

        assert item["judul"] == "Nilai Numerasi baru untuk Ahmad."
        assert (item["target"], item["target_id"], item["dibaca"]) == ("nilai", grade_id, False)
        assert get(client, "/notifications", auth("bapak.budi@contoh.id")).json() == []

    def test_manual_attendance_notifies_once_per_status_change(self, client, db, auth, ibu, school):
        self.guru_put_attendance(client, auth, school["ahmad"], "S")
        self.guru_put_attendance(client, auth, school["ahmad"], "S")
        self.guru_put_attendance(client, auth, school["ahmad"], "H")

        titles = [n.judul for n in self.parent_notes(db, school["parent"])]

        assert titles == [
            "Kehadiran Ahmad hari ini tercatat: Sakit.",
            "Kehadiran Ahmad hari ini tercatat: Hadir.",
        ]
        assert {n.target for n in self.parent_notes(db, school["parent"])} == {"kehadiran"}

    def test_finishing_attendance_notifies_parents_of_students_marked_alpa_only(self, client, db, auth, school):
        self.guru_put_attendance(client, auth, school["ahmad"], "H")
        client.post(f"{GURU}/classes/5A/attendance/finish", headers=auth("andi@contoh.id"))

        titles = [n.judul for n in self.parent_notes(db, school["parent"])]

        assert titles == [
            "Kehadiran Ahmad hari ini tercatat: Hadir.",
            "Kehadiran Siti hari ini tercatat: Alpa.",
        ]

    def test_face_scan_notifies_the_parent(self, client, db, auth, school):
        client.post(
            f"{GURU}/classes/5A/students/{school['ahmad'].id}/face",
            files=upload(image(1)), headers=auth("rina@contoh.id"),
        )

        client.post(f"{GURU}/classes/5A/attendance/face", files=upload(image(1)), headers=auth("andi@contoh.id"))

        assert [n.judul for n in self.parent_notes(db, school["parent"])] == [
            "Kehadiran Ahmad hari ini tercatat: Hadir.",
        ]

    def test_mark_read_and_read_all_only_touch_the_callers_notifications(self, client, db, auth, ibu, school):
        self.guru_put_attendance(client, auth, school["ahmad"], "S")
        self.guru_put_attendance(client, auth, school["siti"], "I")
        client.put(
            f"{GURU}/classes/5B/attendance/{school['budi'].id}",
            json={"status": "A", "metode_input": "manual"},
            headers=auth("andi@contoh.id"),
        )
        first, second = get(client, "/notifications", ibu).json()[::-1]

        assert client.post(f"{API}/notifications/{first['id']}/read", headers=ibu).status_code == 204
        after_one = {n["id"]: n["dibaca"] for n in get(client, "/notifications", ibu).json()}
        assert after_one == {first["id"]: True, second["id"]: False}

        assert client.post(f"{API}/notifications/read-all", headers=ibu).status_code == 204
        assert all(n["dibaca"] for n in get(client, "/notifications", ibu).json())
        budi_notes = get(client, "/notifications", auth("bapak.budi@contoh.id")).json()
        assert [n["dibaca"] for n in budi_notes] == [False]

    def test_cannot_mark_another_parents_notification(self, client, db, auth, ibu, school):
        client.put(
            f"{GURU}/classes/5B/attendance/{school['budi'].id}",
            json={"status": "A", "metode_input": "manual"},
            headers=auth("andi@contoh.id"),
        )
        (budi_note,) = self.parent_notes(db, school["other"])

        response = client.post(f"{API}/notifications/{budi_note.id}/read", headers=ibu)

        assert response.status_code == 404
        assert self.parent_notes(db, school["other"])[0].dibaca is False
