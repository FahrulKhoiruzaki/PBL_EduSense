"""Rapor siswa (semua mapel), status kelengkapan, filter periode, titik tren, dan otorisasinya."""

from datetime import date
from decimal import Decimal

import pytest

from app.models import KomponenPenilaian
from app.services.grading_service import subject_result
from tests.factories import make_component, make_guru
from tests.test_academic import API, GURU, L, N, auth, grade, world  # noqa: F401 (fixture)
from tests.test_auth import bearer, token_for

ORTU = f"{API}/ortu"


def comp(id_, aktif=True, bobot=None):
    return KomponenPenilaian(id=id_, aktif=aktif, kategori=None,
                             bobot=None if bobot is None else Decimal(bobot), nama=f"K{id_}")


class TestCompleteness:
    def test_status_follows_active_components(self):
        a, b, inactive = comp(1, bobot=40), comp(2, bobot=60), comp(3, aktif=False)
        ks = [a, b, inactive]
        assert subject_result(9, [], {}).status == "belum_ada_komponen"
        assert subject_result(9, ks, {}).status == "belum_dinilai"

        partial = subject_result(9, ks, {1: Decimal(80)})
        assert (partial.status, partial.filled, partial.required, partial.final) == ("belum_lengkap", 1, 2, None)

        # Komponen nonaktif tidak wajib, tetapi dihitung bila sudah ada nilainya.
        done = subject_result(9, ks, {1: Decimal(80), 2: Decimal(90)})
        assert (done.status, done.filled, done.required, done.final) == ("lengkap", 2, 2, Decimal("86.00"))
        with_old = subject_result(9, ks, {1: Decimal(80), 2: Decimal(90), 3: Decimal(50)})
        assert (with_old.status, with_old.required) == ("lengkap", 3)

    def test_only_inactive_components_graded_is_complete(self):
        assert subject_result(9, [comp(3, aktif=False)], {3: Decimal(70)}).status == "lengkap"


@pytest.fixture
def graded(db, world):
    """BIN: Tugas (L, 40) + UAS (L, 60), MTK: Kuis (N). Ahmad lengkap BIN, Siti hanya Tugas."""
    kini, lalu = world["kini"], world["lalu"]
    tugas = make_component(db, kini, world["bin"], "Tugas", L, 40)
    uas = make_component(db, kini, world["bin"], "UAS", L, 60)
    make_component(db, kini, world["mtk"], "Kuis", N)
    lama = make_component(db, lalu, world["bin"], "Tugas", L)
    grade(db, world["ahmad"], tugas, 80)
    grade(db, world["ahmad"], uas, 90)
    grade(db, world["siti"], tugas, 70)
    grade(db, world["ahmad"], lama, 60, day=date(2026, 3, 2))


def report(client, headers, siswa, query=""):
    return client.get(f"{GURU}/classes/5A/students/{siswa.id}/report{query}", headers=headers)


class TestStudentReport:
    def test_wali_sees_every_applicable_subject_with_status_and_components(self, client, auth, world, graded):
        body = report(client, auth("rina@contoh.id"), world["ahmad"]).json()

        assert body["siswa"] == {"id": world["ahmad"].id, "nama": "Ahmad", "nis": None, "kelas": "5A"}
        assert body["periode"]["id"] == world["kini"].id
        rows = {m["kode"]: m for m in body["mapel"]}
        assert set(rows) == {"BIN", "MTK", "PJOK"}
        assert (rows["BIN"]["status"], rows["BIN"]["nilai_akhir"], rows["BIN"]["metode"]) == (
            "lengkap", 86.0, "berbobot",
        )
        assert [(k["nama"], k["nilai"], k["bobot"], k["jumlah_nilai"]) for k in rows["BIN"]["komponen"]] == [
            ("Tugas", 80.0, 40.0, 1), ("UAS", 90.0, 60.0, 1),
        ]
        assert (rows["MTK"]["status"], rows["MTK"]["nilai_akhir"]) == ("belum_dinilai", None)
        assert rows["PJOK"]["status"] == "belum_ada_komponen"
        assert body["ringkasan"] == {
            "jumlah_mapel": 3, "lengkap": 1, "belum_lengkap": 0, "belum_dinilai": 1,
            "belum_ada_komponen": 1, "rata_rata_nilai_akhir": 86.0,
        }

    def test_incomplete_subject_has_no_final_score(self, client, auth, world, graded):
        body = report(client, auth("rina@contoh.id"), world["siti"]).json()
        bin_ = next(m for m in body["mapel"] if m["kode"] == "BIN")
        assert (bin_["status"], bin_["komponen_terisi"], bin_["komponen_wajib"], bin_["nilai_akhir"]) == (
            "belum_lengkap", 1, 2, None,
        )
        assert body["ringkasan"]["rata_rata_nilai_akhir"] is None

    def test_period_filter_and_history(self, client, auth, world, graded):
        wali = auth("rina@contoh.id")
        old = report(client, wali, world["ahmad"], f"?periode_id={world['lalu'].id}").json()
        assert old["periode"]["id"] == world["lalu"].id
        bin_ = next(m for m in old["mapel"] if m["kode"] == "BIN")
        assert (bin_["status"], bin_["nilai_akhir"]) == ("lengkap", 60.0)
        # Riwayat: periode terlama dulu, tidak tercampur antarperiode.
        history = old["riwayat"]
        assert [h["periode"]["id"] for h in history] == [world["lalu"].id, world["kini"].id]
        assert [(m["nama"], m["nilai_akhir"]) for m in history[0]["mapel"]] == [("Bahasa Indonesia", 60.0)]
        assert [(m["nama"], m["nilai_akhir"]) for m in history[1]["mapel"]] == [("Bahasa Indonesia", 86.0)]
        assert report(client, wali, world["ahmad"], "?periode_id=999999").status_code == 404

    def test_subject_teacher_only_sees_assigned_subjects(self, client, auth, world, graded):
        body = report(client, auth("andi@contoh.id"), world["ahmad"]).json()
        assert {m["kode"] for m in body["mapel"]} == {"BIN", "MTK"}
        # Penugasan lama tanpa mapel: boleh membuka kelas, tetapi tidak melihat nilai mapel mana pun.
        legacy = report(client, auth("lama@contoh.id"), world["ahmad"]).json()
        assert legacy["mapel"] == [] and all(h["mapel"] == [] for h in legacy["riwayat"])

    def test_access_is_limited_to_own_classes_and_students(self, client, db, auth, world, graded):
        make_guru(db, "luar@contoh.id", "Pak Luar")
        assert report(client, auth("luar@contoh.id"), world["ahmad"]).status_code == 403
        # Siswa kelas lain lewat kode kelas yang diampu -> 404.
        assert report(client, auth("rina@contoh.id"), world["budi"]).status_code == 404
        assert client.get(f"{GURU}/classes/4B/students/{world['budi'].id}/report",
                          headers=auth("rina@contoh.id")).status_code == 403


class TestClassReport:
    def test_matrix_of_students_and_subjects(self, client, auth, world, graded):
        body = client.get(f"{GURU}/classes/5A/report", headers=auth("rina@contoh.id")).json()
        codes = [m["kode"] for m in body["mapel"]]
        assert set(codes) == {"BIN", "MTK", "PJOK"}
        bin_summary = next(m for m in body["mapel"] if m["kode"] == "BIN")
        assert (bin_summary["lengkap"], bin_summary["belum_lengkap"], bin_summary["belum_dinilai"],
                bin_summary["rata_rata"]) == (1, 1, 1, 86.0)
        by_name = {s["nama"]: s for s in body["siswa"]}
        i = codes.index("BIN")
        assert by_name["Ahmad"]["nilai"][i]["nilai_akhir"] == 86.0
        assert by_name["Siti"]["nilai"][i] == {
            "mapel_id": world["bin"].id, "status": "belum_lengkap", "komponen_terisi": 1,
            "komponen_wajib": 2, "nilai_akhir": None,
        }
        assert by_name["Dimas"]["nilai"][i]["status"] == "belum_dinilai"

    def test_subject_teacher_matrix_is_limited(self, client, auth, world, graded):
        body = client.get(f"{GURU}/classes/5A/report", headers=auth("andi@contoh.id")).json()
        assert {m["kode"] for m in body["mapel"]} == {"BIN", "MTK"}


class TestRecapProgress:
    def test_recap_shows_progress_per_period_of_complete_students(self, client, auth, world, graded):
        body = client.get(f"{GURU}/classes/5A/recap?mapel_id={world['bin'].id}",
                          headers=auth("andi@contoh.id")).json()
        assert [(p["periode"]["id"], p["rata_rata"], p["jumlah_lengkap"], p["jumlah_siswa"])
                for p in body["perkembangan"]] == [
            (world["lalu"].id, 60.0, 1, 3),
            (world["kini"].id, 86.0, 1, 3),
        ]


class TestParentReport:
    @pytest.fixture
    def ibu(self, client, world):
        return bearer(token_for(client, "ortu.ahmad@contoh.id"))

    def test_parent_reads_own_child_report_with_period_filter(self, client, world, graded, ibu):
        body = client.get(f"{ORTU}/children/{world['ahmad'].id}/report", headers=ibu).json()
        assert body["periode"]["id"] == world["kini"].id
        assert {m["kode"] for m in body["mapel"]} == {"BIN", "MTK", "PJOK"}
        old = client.get(f"{ORTU}/children/{world['ahmad'].id}/report?periode_id={world['lalu'].id}",
                         headers=ibu).json()
        assert next(m for m in old["mapel"] if m["kode"] == "BIN")["nilai_akhir"] == 60.0

    def test_parent_cannot_read_another_child_or_write(self, client, world, graded, ibu):
        assert client.get(f"{ORTU}/children/{world['siti'].id}/report", headers=ibu).status_code == 404
        assert client.get(f"{ORTU}/children/999999/report", headers=ibu).status_code == 404
        assert client.post(f"{GURU}/classes/5A/grades", headers=ibu, json={}).status_code in (401, 403)

    def test_report_requires_a_parent_token(self, client, auth, world, graded):
        url = f"{ORTU}/children/{world['ahmad'].id}/report"
        assert client.get(url).status_code == 401
        assert client.get(url, headers=auth("rina@contoh.id")).status_code == 403

    def test_periods_list_and_children_period_filter(self, client, world, graded, ibu):
        periods = client.get(f"{ORTU}/periods", headers=ibu).json()
        assert [p["id"] for p in periods] == [world["kini"].id, world["lalu"].id]
        kid = client.get(f"{ORTU}/children?periode_id={world['lalu'].id}", headers=ibu).json()[0]
        assert (kid["periode_id"], kid["tahun_ajaran"]) == (world["lalu"].id, "2025/2026")
        assert kid["tren"]["titik"]["literasi"] == [{"tanggal": "2026-03-02", "nilai": 60.0, "jumlah": 1}]
        assert client.get(f"{ORTU}/children?periode_id=999999", headers=ibu).status_code == 404

    def test_same_final_score_for_teacher_wali_and_parent(self, client, auth, world, graded, ibu):
        recap = client.get(f"{GURU}/classes/5A/recap?mapel_id={world['bin'].id}",
                           headers=auth("andi@contoh.id")).json()
        teacher = next(r for r in recap["siswa"] if r["nama"] == "Ahmad")["nilai_akhir"]
        wali = next(m for m in report(client, auth("rina@contoh.id"), world["ahmad"]).json()["mapel"]
                    if m["kode"] == "BIN")["nilai_akhir"]
        parent = next(m for m in client.get(f"{ORTU}/children/{world['ahmad'].id}/report",
                                            headers=ibu).json()["mapel"] if m["kode"] == "BIN")["nilai_akhir"]
        assert teacher == wali == parent == 86.0


class TestStudentAttendanceTrendAndHistory:
    @pytest.fixture
    def attendance(self, db, world, graded):
        from app.models import Absensi
        from app.models.base import StatusAbsensi as S

        ahmad = world["ahmad"]
        for day, status in [
            (date(2026, 10, 5), S.HADIR), (date(2026, 10, 6), S.TERLAMBAT),
            (date(2026, 10, 7), S.SAKIT), (date(2026, 3, 3), S.ALPA),  # Maret = periode lalu
        ]:
            db.add(Absensi(siswa_id=ahmad.id, tanggal=day, status=status))
        db.commit()

    def test_report_has_period_attendance_and_labelled_trends(self, client, auth, world, attendance):
        body = report(client, auth("rina@contoh.id"), world["ahmad"]).json()
        assert body["kehadiran"] == {
            "total": 3, "hadir": 1, "terlambat": 1, "izin": 0, "sakit": 1, "alpa": 0, "persen_hadir": 66.7,
        }
        assert body["tren"]["kehadiran"] == [{"tanggal": "2026-10-05", "nilai": 66.7, "jumlah": 3}]
        assert body["tren"]["literasi"] == [{"tanggal": "2026-08-31", "nilai": 85.0, "jumlah": 2}]
        old = report(client, auth("rina@contoh.id"), world["ahmad"], f"?periode_id={world['lalu'].id}").json()
        assert (old["kehadiran"]["total"], old["kehadiran"]["alpa"], old["kehadiran"]["persen_hadir"]) == (1, 1, 0.0)

    def test_student_without_records_has_empty_summary_not_zero_percent(self, client, auth, world, graded):
        body = report(client, auth("rina@contoh.id"), world["dimas"]).json()
        assert body["kehadiran"]["total"] == 0 and body["kehadiran"]["persen_hadir"] is None
        assert body["tren"] == {"literasi": [], "numerasi": [], "kehadiran": []}

    def history(self, client, headers, siswa, kode="5A"):
        return client.get(f"{GURU}/classes/{kode}/students/{siswa.id}/history", headers=headers)

    def test_wali_history_has_real_grades_attendance_newest_first(self, client, db, auth, world, attendance):
        from app.models import Nilai

        legacy = Nilai(siswa_id=world["ahmad"].id, kategori=L, jenis_ujian="UH", nilai=Decimal(70),
                       tanggal=date(2026, 9, 2))
        db.add(legacy)
        db.commit()
        items = self.history(client, auth("rina@contoh.id"), world["ahmad"]).json()
        assert [i["tanggal"] for i in items] == sorted((i["tanggal"] for i in items), reverse=True)
        kinds = {(i["jenis"], i["judul"]) for i in items}
        assert ("kehadiran", "Terlambat") in kinds and ("kehadiran", "Sakit") in kinds
        assert ("nilai", "Bahasa Indonesia 90") in kinds and ("nilai", "Literasi 70") in kinds

    def test_subject_teacher_history_only_shows_own_subject_grades(self, client, db, auth, world, attendance):
        from tests.factories import assign, make_subject

        ipas = make_subject(db, "IPAS", "IPAS")
        make_guru(db, "ipas@contoh.id", "Bu IPAS")
        from app.models import Guru
        from sqlalchemy import select

        guru = db.scalar(select(Guru).where(Guru.nama == "Bu IPAS"))
        assign(db, guru, world["a"], ipas)
        items = self.history(client, auth("ipas@contoh.id"), world["ahmad"]).json()
        assert [i for i in items if i["jenis"] == "nilai"] == []
        assert any(i["jenis"] == "kehadiran" for i in items)

    def test_history_access_is_limited(self, client, db, auth, world, attendance):
        make_guru(db, "luar@contoh.id", "Pak Luar")
        assert self.history(client, auth("luar@contoh.id"), world["ahmad"]).status_code == 403
        assert self.history(client, auth("rina@contoh.id"), world["budi"]).status_code == 404
        assert client.get(f"{GURU}/classes/5A/students/{world['ahmad'].id}/history").status_code == 401
