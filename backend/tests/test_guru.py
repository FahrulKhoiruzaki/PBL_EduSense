from datetime import date, datetime, time
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app.models import Absensi, Notifikasi, Nilai
from app.models.base import KategoriNilai, MetodeInput, StatusAbsensi, UserRole
from app.services.guru_service import AUTO_ALPA_NOTE
from tests.factories import (
    assign,
    make_class,
    make_component,
    make_guru,
    make_period,
    make_student,
    make_subject,
    make_user,
)
from tests.test_auth import bearer, token_for

API = "/api/v1/guru"
JKT = ZoneInfo("Asia/Jakarta")
TODAY = date(2026, 10, 8)


@pytest.fixture
def school(app, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    rina = make_guru(db, "rina@contoh.id", "Bu Rina")
    andi = make_guru(db, "andi@contoh.id", "Pak Andi")
    sari = make_guru(db, "sari@contoh.id", "Bu Sari")
    make_guru(db, "lain@contoh.id", "Bu Lain")
    kelas_a = make_class(db, "5A", wali=rina, mapel=(andi,))
    kelas_b = make_class(db, "5B", wali=sari, mapel=(andi, rina))
    return {
        "rina": rina, "andi": andi, "sari": sari, "a": kelas_a, "b": kelas_b,
        "ahmad": make_student(db, "Ahmad Rizky", kelas_a),
        "siti": make_student(db, "Siti Aulia", kelas_a),
        "budi": make_student(db, "Budi Santoso", kelas_b),
    }


@pytest.fixture
def academic(db, school):
    """Periode aktif, dua mapel dengan komponennya, dan penugasan mapel per kelas.

    Andi mengajar BIN dan MTK di 5A serta BIN di 5B; Rina mengajar BIN di 5B. Penugasan lama
    tanpa mapel dari fixture `school` tetap ada.
    """
    periode = make_period(db)
    bin_, mtk = make_subject(db, "BIN", "Bahasa Indonesia"), make_subject(db, "MTK", "Matematika")
    assign(db, school["andi"], school["a"], bin_)
    assign(db, school["andi"], school["a"], mtk)
    assign(db, school["andi"], school["b"], bin_)
    assign(db, school["rina"], school["b"], bin_)
    return {
        "periode": periode, "bin": bin_, "mtk": mtk,
        "bin_uh": make_component(db, periode, bin_, "Ulangan Harian", KategoriNilai.LITERASI),
        "mtk_uh": make_component(db, periode, mtk, "Ulangan Harian", KategoriNilai.NUMERASI),
    }


@pytest.fixture
def auth(client, school):
    return lambda email: bearer(token_for(client, email))


def add_grade(db, siswa, tanggal, nilai, kategori=KategoriNilai.LITERASI, ujian="Ulangan"):
    row = Nilai(
        siswa_id=siswa.id, kategori=kategori, jenis_ujian=ujian,
        nilai=Decimal(str(nilai)), tanggal=tanggal,
    )
    db.add(row)
    db.commit()
    return row


def set_status(client, auth, siswa, status, *, guru="andi@contoh.id", kode="5A", **body):
    return client.put(
        f"{API}/classes/{kode}/attendance/{siswa.id}",
        json={"status": status, "metode_input": "manual", **body},
        headers=auth(guru),
    )


def grade_body(siswa, komponen, **override):
    return {
        "siswa_id": siswa.id, "komponen_id": komponen.id, "jenis_ujian": "Ulangan Harian",
        "nilai": 85, "tanggal": "2026-10-08", "catatan_guru": "Bagus", **override,
    }


def rows(db, model):
    db.expire_all()
    return list(db.scalars(select(model).order_by(model.id)))


def staff_notes(db, school):
    staff = {school[k].user_id for k in ("rina", "andi", "sari")}
    return [n for n in rows(db, Notifikasi) if n.user_id in staff]


def use_real_clock(app):
    app.state.clock = lambda: datetime.now(JKT)


class TestAuthorization:
    @pytest.mark.parametrize(
        ("method", "path"),
        [
            ("get", "/classes"),
            ("get", "/classes/5A"),
            ("get", "/notifications"),
            ("get", "/activities"),
            ("post", "/classes/5A/attendance/finish"),
            ("delete", "/grades/1"),
        ],
    )
    def test_requires_a_token(self, client, school, method, path):
        assert getattr(client, method)(f"{API}{path}").status_code == 401

    def test_parents_cannot_use_guru_endpoints(self, client, school, auth):
        headers = auth("ortu.ahmad.rizky@contoh.id")
        assert client.get(f"{API}/classes", headers=headers).status_code == 403
        assert client.get(f"{API}/notifications", headers=headers).status_code == 403


class TestClassList:
    def test_lists_classes_where_the_guru_is_wali_or_mapel(self, client, auth, school):
        def names(email):
            body = client.get(f"{API}/classes", headers=auth(email)).json()
            return sorted(k["kelas"] for k in body)

        assert names("andi@contoh.id") == ["5A", "5B"]
        assert names("rina@contoh.id") == ["5A", "5B"]
        assert names("sari@contoh.id") == ["5B"]
        assert names("lain@contoh.id") == []

    def test_counts_students_and_todays_attendance_percentage(self, client, auth, school):
        set_status(client, auth, school["ahmad"], "H")
        set_status(client, auth, school["siti"], "S")

        body = {k["kelas"]: k for k in client.get(f"{API}/classes", headers=auth("andi@contoh.id")).json()}

        assert body["5A"] == {"kelas": "5A", "jumlah_siswa": 2, "persen_hadir": 50}
        assert body["5B"] == {"kelas": "5B", "jumlah_siswa": 1, "persen_hadir": 0}

    def test_late_students_count_as_present(self, client, auth, school):
        set_status(client, auth, school["ahmad"], "T")
        set_status(client, auth, school["siti"], "T")

        body = client.get(f"{API}/classes", headers=auth("andi@contoh.id")).json()

        assert {k["kelas"]: k["persen_hadir"] for k in body}["5A"] == 100


class TestClassDetail:
    def test_returns_students_grades_averages_and_trends(self, client, db, auth, school):
        add_grade(db, school["ahmad"], date(2026, 10, 1), 80)
        add_grade(db, school["ahmad"], date(2026, 10, 5), 70)
        add_grade(db, school["siti"], date(2026, 10, 1), 70)
        add_grade(db, school["siti"], date(2026, 10, 5), 72)
        set_status(client, auth, school["ahmad"], "H")
        set_status(client, auth, school["siti"], "A")

        response = client.get(f"{API}/classes/5A", headers=auth("andi@contoh.id"))

        assert response.status_code == 200
        body = response.json()
        ahmad, siti = body["siswa"]
        assert (ahmad["nama"], ahmad["status"], ahmad["waktu"]) == ("Ahmad Rizky", "H", "07:41:05")
        assert (siti["nama"], siti["status"], siti["waktu"]) == ("Siti Aulia", "A", None)
        assert (ahmad["literasi"], ahmad["numerasi"], ahmad["menurun"]) == (75, 0, True)
        assert (siti["literasi"], siti["menurun"]) == (71, False)
        assert body["rata_literasi"] == 73
        assert body["rata_numerasi"] == 0
        tren = body["tren"]
        assert {k: tren[k] for k in ("literasi", "numerasi", "kehadiran")} == {
            "literasi": [75, 71], "numerasi": [], "kehadiran": [50]
        }
        assert tren["titik"]["literasi"] == [
            {"tanggal": "2026-09-28", "nilai": 75.0, "jumlah": 2},
            {"tanggal": "2026-10-05", "nilai": 71.0, "jumlah": 2},
        ]
        assert tren["titik"]["kehadiran"] == [{"tanggal": "2026-10-05", "nilai": 50.0, "jumlah": 2}]

        newest, *_, oldest = body["nilai"]
        assert newest["tanggal"] == "2026-10-05"
        assert oldest["tanggal"] == "2026-10-01" and oldest["nilai_sebelumnya"] is None
        ahmad_latest = next(n for n in body["nilai"] if n["siswa_id"] == school["ahmad"].id and n["nilai"] == 70)
        assert ahmad_latest["nilai_sebelumnya"] == 80
        assert ahmad_latest["siswa"] == "Ahmad Rizky"

    def test_unrecorded_students_have_no_status(self, client, auth, school):
        body = client.get(f"{API}/classes/5A", headers=auth("andi@contoh.id")).json()
        assert [s["status"] for s in body["siswa"]] == [None, None]

    def test_a_small_drop_is_not_flagged_as_declining(self, client, db, auth, school):
        add_grade(db, school["ahmad"], date(2026, 10, 1), 80)
        add_grade(db, school["ahmad"], date(2026, 10, 5), 76)

        body = client.get(f"{API}/classes/5A", headers=auth("andi@contoh.id")).json()

        assert body["siswa"][0]["menurun"] is False

    def test_wali_who_is_not_mapel_can_read(self, client, auth, school):
        assert client.get(f"{API}/classes/5A", headers=auth("rina@contoh.id")).status_code == 200

    def test_unrelated_guru_is_forbidden(self, client, auth, school):
        assert client.get(f"{API}/classes/5A", headers=auth("lain@contoh.id")).status_code == 403

    def test_unknown_class_is_404_and_code_is_case_insensitive(self, client, auth, school):
        headers = auth("andi@contoh.id")
        assert client.get(f"{API}/classes/9Z", headers=headers).status_code == 404
        assert client.get(f"{API}/classes/5a", headers=headers).status_code == 200

    def test_empty_class_returns_empty_collections(self, client, db, auth, school):
        make_class(db, "6A", mapel=(school["andi"],))

        body = client.get(f"{API}/classes/6A", headers=auth("andi@contoh.id")).json()

        assert body["siswa"] == [] and body["nilai"] == []
        assert body["tren"] == {
            "literasi": [], "numerasi": [], "kehadiran": [],
            "titik": {"literasi": [], "numerasi": [], "kehadiran": []},
        }


class TestManualAttendance:
    def test_records_the_status_with_manual_method(self, client, db, auth, school):
        response = set_status(client, auth, school["ahmad"], "I", catatan="Acara keluarga")

        assert response.status_code == 204
        (row,) = rows(db, Absensi)
        assert (row.status, row.metode_input) == (StatusAbsensi.IZIN, MetodeInput.MANUAL)
        assert (row.tanggal, row.waktu, row.catatan) == (TODAY, None, "Acara keluarga")
        assert row.dicatat_oleh == school["andi"].id

    def test_changing_the_status_overwrites_the_same_row(self, client, db, auth, school):
        set_status(client, auth, school["ahmad"], "A")
        set_status(client, auth, school["ahmad"], "H")

        (row,) = rows(db, Absensi)
        assert row.status is StatusAbsensi.HADIR
        assert row.waktu == time(7, 41, 5)

    def test_leaving_a_present_status_clears_the_arrival_time(self, client, db, auth, school):
        set_status(client, auth, school["ahmad"], "H")
        set_status(client, auth, school["ahmad"], "S")

        (row,) = rows(db, Absensi)
        assert (row.status, row.waktu) == (StatusAbsensi.SAKIT, None)

    def test_switching_between_present_statuses_keeps_the_first_arrival_time(
        self, client, db, app, auth, school
    ):
        set_status(client, auth, school["ahmad"], "T")
        app.state.clock = lambda: datetime(2026, 10, 8, 9, 0, 0, tzinfo=JKT)
        set_status(client, auth, school["ahmad"], "H")

        (row,) = rows(db, Absensi)
        assert (row.status, row.waktu) == (StatusAbsensi.HADIR, time(7, 41, 5))

    def test_wali_who_is_not_mapel_cannot_record(self, client, db, auth, school):
        response = set_status(client, auth, school["ahmad"], "H", guru="rina@contoh.id")

        assert response.status_code == 403
        assert rows(db, Absensi) == []

    def test_student_from_another_class_is_404(self, client, db, auth, school):
        assert set_status(client, auth, school["budi"], "H", kode="5A").status_code == 404
        assert rows(db, Absensi) == []

    def test_unknown_status_is_422(self, client, auth, school):
        response = set_status(client, auth, school["ahmad"], "X")

        assert response.status_code == 422
        assert response.json()["errors"]["status"]


class TestFinishAttendance:
    def test_marks_unrecorded_students_as_alpa_and_keeps_existing_records(self, client, db, auth, school):
        set_status(client, auth, school["ahmad"], "H")

        response = client.post(f"{API}/classes/5A/attendance/finish", headers=auth("andi@contoh.id"))

        assert response.status_code == 200
        assert response.json() == {"jumlah_alpa": 1}
        by_student = {r.siswa_id: r for r in rows(db, Absensi)}
        assert by_student[school["ahmad"].id].status is StatusAbsensi.HADIR
        siti = by_student[school["siti"].id]
        assert (siti.status, siti.metode_input, siti.catatan) == (
            StatusAbsensi.ALPA, MetodeInput.MANUAL, AUTO_ALPA_NOTE,
        )
        assert school["budi"].id not in by_student

    def test_is_idempotent(self, client, db, auth, school):
        headers = auth("andi@contoh.id")
        client.post(f"{API}/classes/5A/attendance/finish", headers=headers)

        again = client.post(f"{API}/classes/5A/attendance/finish", headers=headers)

        assert again.json() == {"jumlah_alpa": 0}
        assert len(rows(db, Absensi)) == 2

    def test_a_teacher_can_still_correct_an_auto_alpa(self, client, db, auth, school):
        client.post(f"{API}/classes/5A/attendance/finish", headers=auth("andi@contoh.id"))

        set_status(client, auth, school["siti"], "S", catatan="Surat dokter")

        siti = next(r for r in rows(db, Absensi) if r.siswa_id == school["siti"].id)
        assert (siti.status, siti.catatan) == (StatusAbsensi.SAKIT, "Surat dokter")

    def test_notifies_wali_but_not_the_actor(self, client, db, auth, school):
        client.post(f"{API}/classes/5A/attendance/finish", headers=auth("andi@contoh.id"))

        (note,) = staff_notes(db, school)
        assert note.user_id == school["rina"].user_id
        assert (note.judul, note.target) == ("Absensi Kelas 5A selesai.", "absensi")

    def test_wali_who_is_not_mapel_cannot_finish(self, client, db, auth, school):
        response = client.post(f"{API}/classes/5A/attendance/finish", headers=auth("rina@contoh.id"))

        assert response.status_code == 403
        assert rows(db, Absensi) == []


class TestGrades:
    def test_create_stores_the_grade_and_notifies_wali(self, client, db, auth, school, academic):
        response = client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["ahmad"], academic["bin_uh"]), headers=auth("andi@contoh.id")
        )

        assert response.status_code == 201
        (row,) = rows(db, Nilai)
        assert response.json() == {"id": row.id}
        assert (row.siswa_id, row.kategori, float(row.nilai)) == (
            school["ahmad"].id, KategoriNilai.LITERASI, 85.0,
        )
        assert (row.jenis_ujian, row.tanggal, row.catatan_guru) == ("Ulangan Harian", TODAY, "Bagus")
        assert row.dicatat_oleh == school["andi"].id
        # Diisi trigger database dari komponennya.
        assert (row.komponen_id, row.mapel_id, row.periode_id) == (
            academic["bin_uh"].id, academic["bin"].id, academic["periode"].id,
        )
        (note,) = staff_notes(db, school)
        assert (note.user_id, note.target, note.target_id) == (school["rina"].user_id, "nilai", row.id)

    def test_blank_note_is_stored_as_null(self, client, db, auth, school, academic):
        client.post(
            f"{API}/classes/5A/grades",
            json=grade_body(school["ahmad"], academic["bin_uh"], catatan_guru="   "),
            headers=auth("andi@contoh.id"),
        )

        assert rows(db, Nilai)[0].catatan_guru is None

    @pytest.mark.parametrize("value", [-1, 100.5])
    def test_value_must_be_between_0_and_100(self, client, db, auth, school, academic, value):
        response = client.post(
            f"{API}/classes/5A/grades",
            json=grade_body(school["ahmad"], academic["bin_uh"], nilai=value),
            headers=auth("andi@contoh.id"),
        )

        assert response.status_code == 422
        assert "nilai" in response.json()["errors"]
        assert rows(db, Nilai) == []

    def test_wali_who_is_not_mapel_cannot_create(self, client, db, auth, school, academic):
        response = client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["ahmad"], academic["bin_uh"]), headers=auth("rina@contoh.id")
        )

        assert response.status_code == 403
        assert rows(db, Nilai) == []

    def test_student_from_another_class_is_404(self, client, db, auth, school, academic):
        response = client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["budi"], academic["bin_uh"]), headers=auth("andi@contoh.id")
        )

        assert response.status_code == 404
        assert rows(db, Nilai) == []

    def test_update_changes_the_grade_in_place(self, client, db, auth, school, academic):
        grade = add_grade(db, school["ahmad"], date(2026, 10, 1), 60)

        response = client.put(
            f"{API}/grades/{grade.id}",
            json=grade_body(school["siti"], academic["mtk_uh"], nilai=91.5, catatan_guru=None),
            headers=auth("andi@contoh.id"),
        )

        assert response.status_code == 204
        (row,) = rows(db, Nilai)
        assert (row.siswa_id, row.kategori, float(row.nilai)) == (
            school["siti"].id, KategoriNilai.NUMERASI, 91.5,
        )
        assert (row.tanggal, row.catatan_guru, row.mapel_id) == (TODAY, None, academic["mtk"].id)

    def test_update_cannot_move_a_grade_to_a_student_in_another_class(self, client, db, auth, school, academic):
        grade = add_grade(db, school["ahmad"], date(2026, 10, 1), 60)

        response = client.put(
            f"{API}/grades/{grade.id}", json=grade_body(school["budi"], academic["bin_uh"]), headers=auth("andi@contoh.id")
        )

        assert response.status_code == 404
        assert rows(db, Nilai)[0].siswa_id == school["ahmad"].id

    def test_delete_removes_the_grade(self, client, db, auth, school, academic):
        grade = add_grade(db, school["ahmad"], date(2026, 10, 1), 60)

        response = client.delete(f"{API}/grades/{grade.id}", headers=auth("andi@contoh.id"))

        assert response.status_code == 204
        assert rows(db, Nilai) == []

    def test_only_mapel_guru_of_the_students_class_can_change_or_delete(self, client, db, auth, school, academic):
        grade = add_grade(db, school["ahmad"], date(2026, 10, 1), 60)

        for email in ("rina@contoh.id", "sari@contoh.id", "lain@contoh.id"):
            headers = auth(email)
            put = client.put(f"{API}/grades/{grade.id}", json=grade_body(school["ahmad"], academic["bin_uh"]), headers=headers)
            delete = client.delete(f"{API}/grades/{grade.id}", headers=headers)
            assert (put.status_code, delete.status_code) == (403, 403), email

        (row,) = rows(db, Nilai)
        assert float(row.nilai) == 60.0

    def test_unknown_grade_is_404(self, client, auth, school, academic):
        headers = auth("andi@contoh.id")
        assert client.delete(f"{API}/grades/999", headers=headers).status_code == 404
        assert client.put(f"{API}/grades/999", json=grade_body(school["ahmad"], academic["bin_uh"]), headers=headers).status_code == 404


class TestNotifications:
    def create_grade(self, client, auth, school, academic):
        return client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["ahmad"], academic["bin_uh"]), headers=auth("andi@contoh.id")
        ).json()["id"]

    def test_each_user_only_sees_their_own(self, app, client, auth, school, academic):
        use_real_clock(app)
        grade_id = self.create_grade(client, auth, school, academic)

        rina = client.get(f"{API}/notifications", headers=auth("rina@contoh.id")).json()
        andi = client.get(f"{API}/notifications", headers=auth("andi@contoh.id")).json()

        assert andi == []
        (item,) = rina
        assert item["judul"] == "Nilai baru ditambahkan."
        assert (item["target"], item["target_id"]) == ("nilai", grade_id)
        assert (item["dibaca"], item["kelompok"]) == (False, "hari_ini")

    def test_older_notifications_are_grouped_as_sebelumnya(self, client, auth, school, academic):
        self.create_grade(client, auth, school, academic)

        (item,) = client.get(f"{API}/notifications", headers=auth("rina@contoh.id")).json()

        assert item["kelompok"] == "sebelumnya"

    def test_mark_read(self, app, client, auth, school, academic):
        use_real_clock(app)
        self.create_grade(client, auth, school, academic)
        headers = auth("rina@contoh.id")
        (item,) = client.get(f"{API}/notifications", headers=headers).json()

        assert client.post(f"{API}/notifications/{item['id']}/read", headers=headers).status_code == 204

        (after,) = client.get(f"{API}/notifications", headers=headers).json()
        assert after["dibaca"] is True

    def test_cannot_mark_someone_elses_notification(self, client, db, auth, school, academic):
        self.create_grade(client, auth, school, academic)
        (note,) = staff_notes(db, school)

        response = client.post(f"{API}/notifications/{note.id}/read", headers=auth("andi@contoh.id"))

        assert response.status_code == 404
        assert staff_notes(db, school)[0].dibaca is False

    def test_unknown_notification_is_404(self, client, auth, school, academic):
        assert client.post(f"{API}/notifications/999/read", headers=auth("rina@contoh.id")).status_code == 404

    def test_read_all_only_affects_the_caller(self, client, db, auth, school, academic):
        self.create_grade(client, auth, school, academic)
        client.post(f"{API}/classes/5B/attendance/finish", headers=auth("andi@contoh.id"))
        self.create_grade(client, auth, school, academic)

        response = client.post(f"{API}/notifications/read-all", headers=auth("rina@contoh.id"))

        assert response.status_code == 204
        by_user = {}
        for note in rows(db, Notifikasi):
            by_user.setdefault(note.user_id, []).append(note.dibaca)
        assert by_user[school["rina"].user_id] == [True, True]
        assert by_user[school["sari"].user_id] == [False]


class TestActivities:
    def test_lists_recent_attendance_and_grade_changes_newest_first(
        self, app, client, db, auth, school, academic
    ):
        use_real_clock(app)
        headers = auth("andi@contoh.id")
        set_status(client, auth, school["ahmad"], "S")
        grade_id = client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["siti"], academic["bin_uh"]), headers=headers
        ).json()["id"]

        body = client.get(f"{API}/activities", headers=headers).json()

        assert [(a["judul"], a["target"], a["target_id"]) for a in body] == [
            ("Nilai Bahasa Indonesia Siti Aulia ditambahkan", "nilai", grade_id),
            ("Absensi Ahmad Rizky tercatat: Sakit", "absensi", None),
        ]

    def test_edited_grades_are_labelled_as_updated(self, app, client, db, auth, school, academic):
        use_real_clock(app)
        headers = auth("andi@contoh.id")
        grade_id = client.post(
            f"{API}/classes/5A/grades", json=grade_body(school["siti"], academic["bin_uh"]), headers=headers
        ).json()["id"]
        client.put(f"{API}/grades/{grade_id}", json=grade_body(school["siti"], academic["bin_uh"], nilai=90), headers=headers)

        (item,) = client.get(f"{API}/activities", headers=headers).json()

        assert item["judul"] == "Nilai Bahasa Indonesia Siti Aulia diperbarui"

    def test_automatic_alpa_from_finishing_is_not_listed(self, app, client, auth, school):
        use_real_clock(app)
        headers = auth("andi@contoh.id")
        client.post(f"{API}/classes/5A/attendance/finish", headers=headers)

        assert client.get(f"{API}/activities", headers=headers).json() == []

    def test_only_includes_classes_the_guru_can_access(self, app, client, auth, school):
        use_real_clock(app)
        set_status(client, auth, school["ahmad"], "H")

        assert client.get(f"{API}/activities", headers=auth("sari@contoh.id")).json() == []
        assert client.get(f"{API}/activities", headers=auth("rina@contoh.id")).json() != []
