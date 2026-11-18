"""Periode akademik, mata pelajaran, komponen nilai, dan klasifikasi otomatis."""

from datetime import date, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app.models import (
    AturanKlasifikasi,
    KlasifikasiSiswa,
    Nilai,
    PengaturanSekolah,
    Siswa,
)
from app.models.base import KategoriNilai, Klasifikasi, UserRole
from app.services import grading_service
from app.services.grading_service import Part, category_score, classify, final_score
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

API = "/api/v1"
ADMIN = f"{API}/admin/academic"
GURU = f"{API}/guru"
JKT = ZoneInfo("Asia/Jakarta")
L, N = KategoriNilai.LITERASI, KategoriNilai.NUMERASI


@pytest.fixture
def world(app, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 8, 0, tzinfo=JKT)
    make_user(db, UserRole.ADMIN, "admin@contoh.id", "Admin")
    andi = make_guru(db, "andi@contoh.id", "Pak Andi")
    rina = make_guru(db, "rina@contoh.id", "Bu Rina")
    lama = make_guru(db, "lama@contoh.id", "Pak Lama")
    kelas_a = make_class(db, "5A", wali=rina, mapel=(lama,))  # `lama`: penugasan tanpa mapel
    kelas_b = make_class(db, "4B")
    lalu = make_period(db, "2025/2026", 2, date(2026, 1, 5), date(2026, 6, 20), aktif=False)
    kini = make_period(db)  # 2026/2027 Ganjil, aktif
    bin_ = make_subject(db, "BIN", "Bahasa Indonesia")
    mtk = make_subject(db, "MTK", "Matematika")
    pjok = make_subject(db, "PJOK", "PJOK")
    assign(db, andi, kelas_a, bin_)
    assign(db, andi, kelas_a, mtk)
    return {
        "andi": andi, "rina": rina, "lama": lama, "a": kelas_a, "b": kelas_b,
        "lalu": lalu, "kini": kini, "bin": bin_, "mtk": mtk, "pjok": pjok,
        "ahmad": make_student(db, "Ahmad", kelas_a),
        "siti": make_student(db, "Siti", kelas_a),
        "dimas": make_student(db, "Dimas", kelas_a),
        "budi": make_student(db, "Budi", kelas_b),
    }


@pytest.fixture
def adm(client, world):
    return bearer(token_for(client, "admin@contoh.id"))


@pytest.fixture
def auth(client, world):
    return lambda email: bearer(token_for(client, email))


def grade(db, siswa, komponen, value, day=date(2026, 9, 1)):
    row = Nilai(siswa_id=siswa.id, komponen_id=komponen.id, jenis_ujian=komponen.nama,
                nilai=Decimal(str(value)), tanggal=day)
    db.add(row)
    db.commit()
    return row


def rule(db, periode, metode="rata_rata", mahir=80, cukup=65):
    db.merge(AturanKlasifikasi(periode_id=periode.id, metode=metode,
                               batas_mahir=Decimal(mahir), batas_cukup=Decimal(cukup)))
    db.commit()


# Rumus (unit)


class TestFormula:
    def part(self, avg, bobot=None, mapel=1, kategori=L):
        return Part(mapel, None, kategori, None if bobot is None else Decimal(bobot), Decimal(avg))

    def test_weighted_score_is_normalised_over_graded_components_only(self):
        # Tugas 80 (bobot 30) dan UAS 90 (bobot 50); komponen bobot 20 belum dinilai -> tidak nol.
        assert final_score([self.part(80, 30), self.part(90, 50)]) == Decimal("86.25")

    def test_any_component_without_weight_falls_back_to_a_plain_mean(self):
        assert final_score([self.part(80, 30), self.part(91)]) == Decimal("85.50")

    def test_no_grades_means_no_score_not_zero(self):
        assert final_score([]) is None

    def test_category_score_averages_subjects_and_ignores_other_categories(self):
        parts = [self.part(80, mapel=1), self.part(90, mapel=2), self.part(10, mapel=3, kategori=N)]
        assert category_score(parts, L) == Decimal("85.00")
        assert category_score(parts, N) == Decimal("10.00")
        assert category_score([self.part(70, kategori=None)], L) is None

    @pytest.mark.parametrize(
        ("metode", "lit", "num", "expected"),
        [
            ("rata_rata", 80, 80, Klasifikasi.MAHIR),        # tepat di batas Mahir
            ("rata_rata", 90, 69, Klasifikasi.CUKUP),        # rata-rata 79.5
            ("rata_rata", 65, 65, Klasifikasi.CUKUP),        # tepat di batas Cukup
            ("rata_rata", 70, 59, Klasifikasi.PERLU_PENDAMPINGAN),
            ("terendah", 95, 70, Klasifikasi.CUKUP),         # skor terendah 70
            ("terendah", 95, 60, Klasifikasi.PERLU_PENDAMPINGAN),
        ],
    )
    def test_classification_follows_the_period_rule(self, metode, lit, num, expected):
        aturan = AturanKlasifikasi(metode=metode, batas_mahir=Decimal(80), batas_cukup=Decimal(65))
        assert classify(Decimal(lit), Decimal(num), aturan)[1] is expected

    def test_missing_category_or_missing_rule_is_not_classified(self):
        aturan = AturanKlasifikasi(metode="rata_rata", batas_mahir=Decimal(80), batas_cukup=Decimal(65))
        assert classify(Decimal(90), None, aturan) == (None, None)
        assert classify(Decimal(90), Decimal(90), None) == (None, None)


# Periode akademik


class TestPeriods:
    def test_list_has_counts_and_delete_flags(self, client, db, adm, world):
        k = make_component(db, world["kini"], world["bin"], "Tugas", L)
        grade(db, world["ahmad"], k, 80)

        body = client.get(f"{ADMIN}/periods", headers=adm).json()

        assert [p["label"] for p in body] == ["Semester Ganjil 2026/2027", "Semester Genap 2025/2026"]
        kini, lalu = body
        assert (kini["aktif"], kini["jumlah_nilai"], kini["jumlah_komponen"], kini["dapat_dihapus"]) == (
            True, 1, 1, False,
        )
        assert (lalu["aktif"], lalu["dapat_dihapus"], lalu["punya_aturan"]) == (False, True, False)

    def test_create_validates_and_rejects_overlap_and_duplicates(self, client, adm, world):
        ok = client.post(f"{ADMIN}/periods", headers=adm, json={
            "tahun_ajaran": "2026/2027", "semester": 2,
            "tanggal_mulai": "2027-01-04", "tanggal_selesai": "2027-06-19",
        })
        overlap = client.post(f"{ADMIN}/periods", headers=adm, json={
            "tahun_ajaran": "2027/2028", "semester": 1,
            "tanggal_mulai": "2027-06-01", "tanggal_selesai": "2027-12-19",
        })
        duplicate = client.post(f"{ADMIN}/periods", headers=adm, json={
            "tahun_ajaran": "2026/2027", "semester": 1,
            "tanggal_mulai": "2030-01-01", "tanggal_selesai": "2030-06-01",
        })
        bad_year = client.post(f"{ADMIN}/periods", headers=adm, json={
            "tahun_ajaran": "2026/2028", "semester": 1,
            "tanggal_mulai": "2030-01-01", "tanggal_selesai": "2030-06-01",
        })
        reversed_dates = client.post(f"{ADMIN}/periods", headers=adm, json={
            "tahun_ajaran": "2030/2031", "semester": 1,
            "tanggal_mulai": "2030-06-01", "tanggal_selesai": "2030-01-01",
        })

        assert ok.status_code == 201 and ok.json()["aktif"] is False
        assert overlap.status_code == 409 and "tanggal_mulai" in overlap.json()["errors"]
        assert duplicate.status_code == 409 and "semester" in duplicate.json()["errors"]
        assert bad_year.status_code == 422 and "tahun_ajaran" in bad_year.json()["errors"]
        assert reversed_dates.status_code == 422

    def test_activating_keeps_one_active_period_and_syncs_the_academic_year(self, client, db, adm, world):
        response = client.post(f"{ADMIN}/periods/{world['lalu'].id}/activate", headers=adm)

        assert response.status_code == 200 and response.json()["aktif"] is True
        active = [p for p in client.get(f"{ADMIN}/periods", headers=adm).json() if p["aktif"]]
        assert [p["id"] for p in active] == [world["lalu"].id]
        db.expire_all()
        assert db.get(PengaturanSekolah, True).tahun_ajaran == "2025/2026"
        settings = client.get(f"{API}/admin/settings", headers=adm).json()
        assert (settings["tahun_ajaran"], settings["periode_aktif"]) == (
            "2025/2026", "Semester Genap 2025/2026",
        )

    def test_settings_cannot_set_a_year_that_contradicts_the_active_period(self, client, adm, world):
        response = client.put(f"{API}/admin/settings", headers=adm,
                              json={"tahun_ajaran": "2030/2031", "batas_jam_terlambat": "07:00"})

        assert response.status_code == 422 and "tahun_ajaran" in response.json()["errors"]
        same = client.put(f"{API}/admin/settings", headers=adm,
                          json={"tahun_ajaran": "2026/2027", "batas_jam_terlambat": "07:00"})
        assert same.status_code == 204

    def test_history_is_protected_from_deletion_and_range_changes(self, client, db, adm, world):
        k = make_component(db, world["kini"], world["bin"], "Tugas", L)
        grade(db, world["ahmad"], k, 80, day=date(2026, 12, 1))

        delete_active = client.delete(f"{ADMIN}/periods/{world['kini'].id}", headers=adm)
        client.post(f"{ADMIN}/periods/{world['lalu'].id}/activate", headers=adm)
        delete_used = client.delete(f"{ADMIN}/periods/{world['kini'].id}", headers=adm)
        shrink = client.put(f"{ADMIN}/periods/{world['kini'].id}", headers=adm, json={
            "tahun_ajaran": "2026/2027", "semester": 1,
            "tanggal_mulai": "2026-07-13", "tanggal_selesai": "2026-11-30",
        })
        rename = client.put(f"{ADMIN}/periods/{world['kini'].id}", headers=adm, json={
            "tahun_ajaran": "2027/2028", "semester": 1,
            "tanggal_mulai": "2026-07-13", "tanggal_selesai": "2026-12-19",
        })

        assert (delete_active.status_code, delete_used.status_code) == (409, 409)
        assert shrink.status_code == 409 and rename.status_code == 409
        assert db.scalar(select(Nilai.periode_id)) == world["kini"].id

    def test_unused_inactive_period_can_be_deleted(self, client, adm, world):
        assert client.delete(f"{ADMIN}/periods/{world['lalu'].id}", headers=adm).status_code == 204
        assert len(client.get(f"{ADMIN}/periods", headers=adm).json()) == 1

    @pytest.mark.parametrize("who", ["andi@contoh.id", "ortu.ahmad@contoh.id"])
    def test_only_admins_can_use_academic_endpoints(self, client, auth, world, who):
        headers = auth(who)
        for path in ("/periods", "/subjects", "/components", "/classification"):
            assert client.get(f"{ADMIN}{path}", headers=headers).status_code == 403
        assert client.get(f"{ADMIN}/periods").status_code == 401


# Mata pelajaran dan muatan lokal


class TestSubjects:
    def test_admin_can_add_a_local_content_subject_for_some_levels(self, client, adm, world):
        response = client.post(f"{ADMIN}/subjects", headers=adm, json={
            "kode": "bjawa", "nama": "Bahasa Jawa", "jenis": "muatan_lokal", "tingkat": [6, 1, 1],
            "deskripsi": "Muatan lokal",
        })

        assert response.status_code == 201
        body = response.json()
        assert (body["kode"], body["jenis"], body["tingkat"], body["aktif"]) == (
            "BJAWA", "muatan_lokal", [1, 6], True,
        )
        listed = {m["kode"]: m for m in client.get(f"{ADMIN}/subjects", headers=adm).json()}
        assert listed["BIN"]["dipakai"] is True and listed["PJOK"]["dipakai"] is False

    @pytest.mark.parametrize(
        ("body", "field", "status"),
        [
            ({"kode": "BIN", "nama": "Lain"}, "kode", 409),
            ({"kode": "XYZ", "nama": "matematika"}, "nama", 409),
            ({"kode": "B I N", "nama": "Spasi"}, "kode", 422),
            ({"kode": "SNI", "nama": "Seni", "tingkat": []}, "tingkat", 422),
            ({"kode": "SNI", "nama": "Seni", "tingkat": [7]}, "tingkat", 422),
            ({"kode": "SNI", "nama": "Seni", "jenis": "lain"}, "jenis", 422),
        ],
    )
    def test_validation(self, client, adm, world, body, field, status):
        response = client.post(f"{ADMIN}/subjects", headers=adm, json=body)
        assert response.status_code == status and field in response.json()["errors"]

    def test_used_subjects_are_deactivated_not_deleted(self, client, adm, world):
        used = client.delete(f"{ADMIN}/subjects/{world['bin'].id}", headers=adm)
        unused = client.delete(f"{ADMIN}/subjects/{world['pjok'].id}", headers=adm)
        deactivate = client.put(f"{ADMIN}/subjects/{world['bin'].id}/active", headers=adm, json={"aktif": False})

        assert (used.status_code, unused.status_code, deactivate.status_code) == (409, 204, 204)
        listed = {m["kode"]: m for m in client.get(f"{ADMIN}/subjects", headers=adm).json()}
        assert listed["BIN"]["aktif"] is False and "PJOK" not in listed

    def test_cannot_drop_a_level_that_still_has_teacher_assignments(self, client, adm, world):
        response = client.put(f"{ADMIN}/subjects/{world['bin'].id}", headers=adm, json={
            "kode": "BIN", "nama": "Bahasa Indonesia", "tingkat": [1, 2, 3],
        })
        assert response.status_code == 409 and "5A" in response.json()["message"]

    def test_teacher_assignment_per_subject(self, client, adm, world):
        path = f"{API}/admin/classes/4B/mapel"
        ipas = client.post(f"{ADMIN}/subjects", headers=adm, json={
            "kode": "IPAS", "nama": "IPAS", "tingkat": [5, 6],
        }).json()

        ok = client.post(path, headers=adm, json={"guru_id": world["andi"].id, "mapel_id": world["mtk"].id})
        again = client.post(path, headers=adm, json={"guru_id": world["andi"].id, "mapel_id": world["mtk"].id})
        wrong_level = client.post(path, headers=adm, json={"guru_id": world["andi"].id, "mapel_id": ipas["id"]})
        second = client.post(path, headers=adm, json={"guru_id": world["andi"].id, "mapel_id": world["bin"].id})

        assert (ok.status_code, again.status_code, wrong_level.status_code, second.status_code) == (
            204, 409, 422, 204,
        )
        kelas = {c["kode"]: c for c in client.get(f"{API}/admin/classes", headers=adm).json()}["4B"]
        assert kelas["mapel_ids"] == [world["andi"].id]
        assert {a["mapel"] for a in kelas["penugasan"]} == {"Matematika", "Bahasa Indonesia"}

        removed = client.delete(f"{path}/{world['andi'].id}?mapel_id={world['mtk'].id}", headers=adm)
        kelas = {c["kode"]: c for c in client.get(f"{API}/admin/classes", headers=adm).json()}["4B"]
        assert removed.status_code == 204 and [a["mapel"] for a in kelas["penugasan"]] == ["Bahasa Indonesia"]

    def test_guru_session_lists_a_class_once_even_with_several_subjects(self, client, auth, world):
        me = client.get(f"{API}/auth/me", headers=auth("andi@contoh.id")).json()
        assert me["guru"]["mapel"] == ["5A"]


# Komponen penilaian


class TestComponents:
    def body(self, world, **override):
        return {"periode_id": world["kini"].id, "mapel_id": world["bin"].id, "kategori": "Literasi",
                "nama": "Tugas", "bobot": 40, **override}

    def test_create_list_and_filter(self, client, adm, world):
        created = client.post(f"{ADMIN}/components", headers=adm, json=self.body(world))
        client.post(f"{ADMIN}/components", headers=adm,
                    json=self.body(world, mapel_id=world["pjok"].id, kategori=None, nama="Praktik", bobot=None))

        assert created.status_code == 201
        assert created.json()["mapel"] == "Bahasa Indonesia" and created.json()["bobot"] == 40.0
        everything = client.get(f"{ADMIN}/components", headers=adm).json()
        only_pjok = client.get(f"{ADMIN}/components?mapel_id={world['pjok'].id}", headers=adm).json()
        old_period = client.get(f"{ADMIN}/components?periode_id={world['lalu'].id}", headers=adm).json()
        assert len(everything) == 2 and [k["nama"] for k in only_pjok] == ["Praktik"]
        assert only_pjok[0]["kategori"] is None and old_period == []

    def test_active_weights_per_subject_cannot_exceed_100(self, client, adm, world):
        client.post(f"{ADMIN}/components", headers=adm, json=self.body(world, bobot=70))

        too_much = client.post(f"{ADMIN}/components", headers=adm, json=self.body(world, nama="UAS", bobot=40))
        other_subject = client.post(f"{ADMIN}/components", headers=adm,
                                    json=self.body(world, mapel_id=world["mtk"].id, nama="UAS", bobot=40))
        duplicate = client.post(f"{ADMIN}/components", headers=adm, json=self.body(world, nama="tugas", bobot=10))

        assert too_much.status_code == 422 and "bobot" in too_much.json()["errors"]
        assert other_subject.status_code == 201
        assert duplicate.status_code == 409 and "nama" in duplicate.json()["errors"]

    def test_components_with_grades_are_deactivated_not_deleted(self, client, db, adm, world):
        k = make_component(db, world["kini"], world["bin"], "Tugas", L)
        empty = make_component(db, world["kini"], world["bin"], "Kuis", L)
        grade(db, world["ahmad"], k, 80)

        assert client.delete(f"{ADMIN}/components/{k.id}", headers=adm).status_code == 409
        assert client.delete(f"{ADMIN}/components/{empty.id}", headers=adm).status_code == 204
        moved = client.put(f"{ADMIN}/components/{k.id}", headers=adm,
                           json=self.body(world, mapel_id=world["mtk"].id, bobot=None))
        assert moved.status_code == 409

    def test_changing_a_category_recomputes_the_classification(self, client, db, adm, world):
        rule(db, world["kini"])
        tugas = make_component(db, world["kini"], world["bin"], "Tugas", L)
        hitung = make_component(db, world["kini"], world["mtk"], "Hitung", None)
        grade(db, world["ahmad"], tugas, 90)
        grade(db, world["ahmad"], hitung, 90)
        grading_service.recompute(db, world["kini"])
        db.commit()
        assert db.scalar(select(KlasifikasiSiswa.klasifikasi)) is None  # belum ada Numerasi

        response = client.put(f"{ADMIN}/components/{hitung.id}", headers=adm, json={
            "periode_id": world["kini"].id, "mapel_id": world["mtk"].id, "kategori": "Numerasi",
            "nama": "Hitung",
        })

        assert response.status_code == 200
        db.expire_all()
        assert db.scalar(select(KlasifikasiSiswa.klasifikasi)) is Klasifikasi.MAHIR
        assert db.scalar(select(Nilai.kategori).where(Nilai.komponen_id == hitung.id)) is N

    def test_copy_to_a_new_period_skips_existing_names(self, client, db, adm, world):
        make_component(db, world["lalu"], world["bin"], "Tugas", L, 40)
        make_component(db, world["lalu"], world["bin"], "UAS", L, 60)
        make_component(db, world["kini"], world["bin"], "Tugas", L, 30)

        response = client.post(f"{ADMIN}/components/copy", headers=adm,
                               json={"dari_periode_id": world["lalu"].id, "ke_periode_id": world["kini"].id})

        assert response.json() == {"disalin": 1, "dilewati": 1}
        names = [k["nama"] for k in client.get(f"{ADMIN}/components", headers=adm).json()]
        assert sorted(names) == ["Tugas", "UAS"]


# Aturan, perhitungan otomatis, dan chart


class TestClassification:
    def setup_grades(self, db, world):
        lit = make_component(db, world["kini"], world["bin"], "UH", L)
        num = make_component(db, world["kini"], world["mtk"], "UH", N)
        for siswa, (a, b) in {"ahmad": (90, 85), "siti": (70, 66), "dimas": (50, 60)}.items():
            grade(db, world[siswa], lit, a)
            grade(db, world[siswa], num, b)
        return lit, num

    def test_without_a_rule_nobody_is_classified(self, client, db, adm, world):
        self.setup_grades(db, world)
        grading_service.recompute(db, world["kini"])
        db.commit()

        body = client.get(f"{ADMIN}/classification", headers=adm).json()

        assert body["aturan"] is None and "belum ditetapkan" in body["catatan"]
        assert body["ringkasan"]["terklasifikasi"] == 0
        assert [k["jumlah"] for k in body["ringkasan"]["kategori"]] == [0, 0, 0]

    def test_saving_a_rule_classifies_and_the_chart_counts_correctly(self, client, db, adm, world):
        self.setup_grades(db, world)

        saved = client.put(f"{ADMIN}/periods/{world['kini'].id}/rule", headers=adm,
                           json={"metode": "rata_rata", "batas_mahir": 80, "batas_cukup": 65})
        body = client.get(f"{ADMIN}/classification", headers=adm).json()

        assert saved.status_code == 200 and saved.json()["metode"] == "rata_rata"
        r = body["ringkasan"]
        # 4 siswa: 3 terklasifikasi (5A) + Budi (4B) belum punya nilai -> tidak masuk kategori mana pun.
        assert (r["total_siswa"], r["terklasifikasi"], r["belum_lengkap"], r["tanpa_nilai"]) == (4, 3, 0, 1)
        assert [(k["klasifikasi"], k["jumlah"], k["persen"]) for k in r["kategori"]] == [
            ("Mahir", 1, 33.3), ("Cukup", 1, 33.3), ("Perlu Pendampingan", 1, 33.3),
        ]
        per_class = {c["kelas"]: c for c in body["per_kelas"]}
        assert per_class["5A"]["terklasifikasi"] == 3 and per_class["4B"]["tanpa_nilai"] == 1
        assert sum(c["total_siswa"] for c in body["per_kelas"]) == r["total_siswa"]
        db.expire_all()
        cache = {s.nama: s.status_klasifikasi for s in db.scalars(select(Siswa))}
        assert cache == {"Ahmad": Klasifikasi.MAHIR, "Siti": Klasifikasi.CUKUP,
                         "Dimas": Klasifikasi.PERLU_PENDAMPINGAN, "Budi": None}

    def test_rule_validation(self, client, adm, world):
        response = client.put(f"{ADMIN}/periods/{world['kini'].id}/rule", headers=adm,
                              json={"metode": "rata_rata", "batas_mahir": 60, "batas_cukup": 70})
        assert response.status_code == 422

    def test_incomplete_students_are_not_put_in_a_category(self, client, db, adm, world):
        rule(db, world["kini"])
        lit = make_component(db, world["kini"], world["bin"], "UH", L)
        grade(db, world["ahmad"], lit, 95)
        grading_service.recompute(db, world["kini"])
        db.commit()

        r = client.get(f"{ADMIN}/classification?kelas=5A", headers=adm).json()["ringkasan"]

        assert (r["terklasifikasi"], r["belum_lengkap"], r["tanpa_nilai"]) == (0, 1, 2)
        assert all(k["persen"] == 0.0 for k in r["kategori"])

    def test_comparison_with_the_previous_semester_uses_the_same_students(self, client, db, adm, world):
        rule(db, world["lalu"])
        rule(db, world["kini"])
        old_l = make_component(db, world["lalu"], world["bin"], "UH", L)
        old_n = make_component(db, world["lalu"], world["mtk"], "UH", N)
        old = date(2026, 3, 1)
        for siswa, (a, b) in {"ahmad": (70, 70), "siti": (90, 90), "dimas": (50, 50)}.items():
            grade(db, world[siswa], old_l, a, old)
            grade(db, world[siswa], old_n, b, old)
        self.setup_grades(db, world)  # sekarang: Ahmad Mahir (naik), Siti Cukup (turun), Dimas tetap
        grading_service.recompute(db, world["lalu"])
        grading_service.recompute(db, world["kini"])
        db.commit()

        comparison = client.get(f"{ADMIN}/classification", headers=adm).json()["perbandingan"]

        assert comparison["periode"]["label"] == "Semester Genap 2025/2026"
        assert (comparison["dibandingkan"], comparison["naik"], comparison["turun"], comparison["tetap"]) == (
            3, 1, 1, 1,
        )
        assert [k["jumlah"] for k in comparison["sebelumnya"]["kategori"]] == [1, 1, 1]

    def test_no_comparison_without_previous_results(self, client, db, adm, world):
        rule(db, world["kini"])
        self.setup_grades(db, world)
        grading_service.recompute(db, world["kini"])
        db.commit()
        assert client.get(f"{ADMIN}/classification", headers=adm).json()["perbandingan"] is None

    def test_recompute_endpoint(self, client, db, adm, world):
        rule(db, world["kini"])
        self.setup_grades(db, world)

        response = client.post(f"{ADMIN}/periods/{world['kini'].id}/recompute", headers=adm)

        assert response.json() == {"dihitung": 3, "terklasifikasi": 3}

    def test_old_periods_keep_the_class_students_had_then(self, client, db, adm, world):
        rule(db, world["lalu"])
        old_l = make_component(db, world["lalu"], world["bin"], "UH", L)
        old_n = make_component(db, world["lalu"], world["mtk"], "UH", N)
        grade(db, world["budi"], old_l, 90, date(2026, 3, 1))
        grade(db, world["budi"], old_n, 90, date(2026, 3, 1))
        grading_service.recompute(db, world["lalu"])
        db.commit()
        client.post(f"{API}/admin/siswa/move", headers=adm,
                    json={"siswa_ids": [world["budi"].id], "kelas_tujuan": "5A"})
        client.post(f"{ADMIN}/periods/{world['lalu'].id}/recompute", headers=adm)

        body = client.get(f"{ADMIN}/classification?periode_id={world['lalu'].id}", headers=adm).json()

        assert [c["kelas"] for c in body["per_kelas"]] == ["4B"]


# Guru: hak per mapel, periode, rekap


class TestGuruAcademic:
    def body(self, siswa, komponen, **override):
        return {"siswa_id": siswa.id, "komponen_id": komponen.id, "nilai": 80,
                "tanggal": "2026-10-01", **override}

    def test_grade_rights_are_per_subject(self, client, db, auth, world):
        bin_k = make_component(db, world["kini"], world["bin"], "UH", L)
        pjok_k = make_component(db, world["kini"], world["pjok"], "Praktik")
        db.add_all([])

        andi_pjok = client.post(f"{GURU}/classes/5A/grades", headers=auth("andi@contoh.id"),
                                json=self.body(world["ahmad"], pjok_k))
        lama = client.post(f"{GURU}/classes/5A/grades", headers=auth("lama@contoh.id"),
                           json=self.body(world["ahmad"], bin_k))
        lama_attendance = client.put(f"{GURU}/classes/5A/attendance/{world['ahmad'].id}",
                                     headers=auth("lama@contoh.id"), json={"status": "H"})
        wali = client.post(f"{GURU}/classes/5A/grades", headers=auth("rina@contoh.id"),
                           json=self.body(world["ahmad"], bin_k))
        andi_bin = client.post(f"{GURU}/classes/5A/grades", headers=auth("andi@contoh.id"),
                               json=self.body(world["ahmad"], bin_k, jenis_ujian=""))

        assert (andi_pjok.status_code, lama.status_code, wali.status_code) == (403, 403, 403)
        assert lama_attendance.status_code == 204, "penugasan lama tetap boleh absensi"
        assert andi_bin.status_code == 201
        assert db.get(Nilai, andi_bin.json()["id"]).jenis_ujian == "UH"

    @pytest.mark.parametrize("case", ["inactive", "outside", "level"])
    def test_component_must_be_usable(self, client, db, auth, world, case):
        if case == "inactive":
            k = make_component(db, world["kini"], world["bin"], "Lama", L, aktif=False)
            body, field = self.body(world["ahmad"], k), "komponen_id"
        elif case == "outside":
            k = make_component(db, world["kini"], world["bin"], "UH", L)
            body, field = self.body(world["ahmad"], k, tanggal="2027-01-10"), "tanggal"
        else:
            kecil = make_subject(db, "BACA", "Membaca Permulaan", tingkat=(1, 2))
            assign(db, world["andi"], world["a"], kecil)
            k = make_component(db, world["kini"], kecil, "UH", L)
            body, field = self.body(world["ahmad"], k), "komponen_id"

        response = client.post(f"{GURU}/classes/5A/grades", headers=auth("andi@contoh.id"), json=body)

        assert response.status_code == 422 and field in response.json()["errors"]

    def test_creating_and_deleting_grades_keeps_the_classification_current(self, client, db, auth, world):
        rule(db, world["kini"])
        lit = make_component(db, world["kini"], world["bin"], "UH", L)
        num = make_component(db, world["kini"], world["mtk"], "UH", N)
        headers = auth("andi@contoh.id")

        client.post(f"{GURU}/classes/5A/grades", headers=headers, json=self.body(world["ahmad"], lit, nilai=90))
        second = client.post(f"{GURU}/classes/5A/grades", headers=headers,
                             json=self.body(world["ahmad"], num, nilai=86)).json()["id"]
        db.expire_all()
        assert db.get(Siswa, world["ahmad"].id).status_klasifikasi is Klasifikasi.MAHIR

        client.delete(f"{GURU}/grades/{second}", headers=headers)
        db.expire_all()
        row = db.scalar(select(KlasifikasiSiswa))
        assert row.klasifikasi is None and float(row.skor_literasi) == 90.0
        assert db.get(Siswa, world["ahmad"].id).status_klasifikasi is None

    def test_class_detail_follows_the_selected_period(self, client, db, auth, world):
        rule(db, world["lalu"])
        old = make_component(db, world["lalu"], world["bin"], "UH", L)
        new = make_component(db, world["kini"], world["bin"], "UH", L)
        grade(db, world["ahmad"], old, 40, date(2026, 3, 1))
        grade(db, world["ahmad"], new, 95)
        grading_service.recompute(db, world["lalu"])
        grading_service.recompute(db, world["kini"])
        db.commit()
        headers = auth("andi@contoh.id")

        active = client.get(f"{GURU}/classes/5A", headers=headers).json()
        history = client.get(f"{GURU}/classes/5A?periode_id={world['lalu'].id}", headers=headers).json()
        missing = client.get(f"{GURU}/classes/5A?periode_id=999", headers=headers)

        assert active["periode"]["label"] == "Semester Ganjil 2026/2027"
        assert [g["nilai"] for g in active["nilai"]] == [95.0]
        assert active["nilai"][0]["mapel"] == "Bahasa Indonesia" and active["nilai"][0]["komponen"] == "UH"
        assert history["periode"]["aktif"] is False and [g["nilai"] for g in history["nilai"]] == [40.0]
        ahmad = next(s for s in history["siswa"] if s["nama"] == "Ahmad")
        assert ahmad["literasi"] == 40 and ahmad["klasifikasi"] is None  # Numerasi belum ada
        assert missing.status_code == 404

    def test_periods_subjects_recap_and_classification_endpoints(self, client, db, auth, world):
        rule(db, world["kini"])
        tugas = make_component(db, world["kini"], world["bin"], "Tugas", L, 40)
        uas = make_component(db, world["kini"], world["bin"], "UAS", L, 60)
        num = make_component(db, world["kini"], world["mtk"], "UH", N)
        grade(db, world["ahmad"], tugas, 70)
        grade(db, world["ahmad"], tugas, 90)  # rata-rata komponen 80
        grade(db, world["ahmad"], uas, 90)
        grade(db, world["ahmad"], num, 80)
        grading_service.recompute(db, world["kini"])
        db.commit()
        andi, rina = auth("andi@contoh.id"), auth("rina@contoh.id")

        labels = [p["label"] for p in client.get(f"{GURU}/periods", headers=andi).json()]
        subjects = client.get(f"{GURU}/classes/5A/subjects", headers=andi).json()
        wali_subjects = client.get(f"{GURU}/classes/5A/subjects", headers=rina).json()
        recap = client.get(f"{GURU}/classes/5A/recap?mapel_id={world['bin'].id}", headers=andi).json()
        chart = client.get(f"{GURU}/classes/5A/classification", headers=rina).json()

        assert labels == ["Semester Ganjil 2026/2027", "Semester Genap 2025/2026"]
        assert [(m["kode"], m["boleh_input"], len(m["komponen"])) for m in subjects] == [
            ("BIN", True, 2), ("MTK", True, 1),
        ]
        assert {m["kode"]: m["boleh_input"] for m in wali_subjects} == {"BIN": False, "MTK": False, "PJOK": False}
        assert recap["metode"] == "berbobot" and [k["nama"] for k in recap["komponen"]] == ["Tugas", "UAS"]
        ahmad = next(r for r in recap["siswa"] if r["nama"] == "Ahmad")
        assert ahmad["nilai_komponen"] == [80.0, 90.0] and ahmad["nilai_akhir"] == 86.0
        siti = next(r for r in recap["siswa"] if r["nama"] == "Siti")
        assert siti == {"siswa_id": world["siti"].id, "nama": "Siti", "nilai_komponen": [None, None],
                        "nilai_akhir": None, "status": "belum_dinilai", "komponen_terisi": 0,
                        "komponen_wajib": 2}
        assert (ahmad["status"], ahmad["komponen_terisi"], ahmad["komponen_wajib"]) == ("lengkap", 2, 2)
        r = chart["ringkasan"]
        assert (r["total_siswa"], r["terklasifikasi"], r["tanpa_nilai"]) == (3, 1, 2)
        assert [c["kelas"] for c in chart["per_kelas"]] == ["5A"]

    def test_recap_requires_teaching_the_subject_unless_wali(self, client, db, auth, world):
        make_guru(db, "lain@contoh.id", "Bu Lain")
        assign(db, world["rina"], world["b"], world["bin"])
        andi_pjok = client.get(f"{GURU}/classes/5A/recap?mapel_id={world['pjok'].id}", headers=auth("andi@contoh.id"))
        outsider = client.get(f"{GURU}/classes/5A/recap?mapel_id={world['bin'].id}", headers=auth("lain@contoh.id"))
        assert (andi_pjok.status_code, outsider.status_code) == (403, 403)


class TestParentPeriod:
    def test_parent_overview_uses_the_active_period_and_semester_history(self, client, db, world):
        rule(db, world["lalu"])
        rule(db, world["kini"])
        old_l = make_component(db, world["lalu"], world["bin"], "UH", L)
        old_n = make_component(db, world["lalu"], world["mtk"], "UH", N)
        lit = make_component(db, world["kini"], world["bin"], "UH", L)
        num = make_component(db, world["kini"], world["mtk"], "UH", N)
        grade(db, world["ahmad"], old_l, 60, date(2026, 3, 1))
        grade(db, world["ahmad"], old_n, 60, date(2026, 3, 1))
        grade(db, world["ahmad"], lit, 88)
        grade(db, world["ahmad"], num, 84)
        grading_service.recompute(db, world["lalu"])
        grading_service.recompute(db, world["kini"])
        db.commit()

        (kid,) = client.get(f"{API}/ortu/children", headers=bearer(token_for(client, "ortu.ahmad@contoh.id"))).json()

        assert (kid["periode"], kid["tahun_ajaran"], kid["klasifikasi"]) == (
            "Semester Ganjil 2026/2027", "2026/2027", "Mahir",
        )
        assert (kid["literasi"], kid["numerasi"]) == (88, 84)
        assert kid["riwayat_klasifikasi"] == [
            {"bulan": "Genap 2025/2026", "klasifikasi": "Perlu Pendampingan"},
            {"bulan": "Ganjil 2026/2027", "klasifikasi": "Mahir"},
        ]
        assert {g["mapel"] for g in kid["nilai"]} == {"Bahasa Indonesia", "Matematika"}
