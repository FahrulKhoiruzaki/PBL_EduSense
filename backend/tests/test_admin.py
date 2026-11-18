from datetime import date, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import func, select

from app.models import (
    Absensi,
    Guru,
    Kelas,
    LogAktivitas,
    MapelGuru,
    Nilai,
    OrangTua,
    Siswa,
    User,
)
from app.models.base import KategoriNilai, StatusAbsensi, UserRole
from tests.factories import PASSWORD, make_class, make_guru, make_student, make_user
from tests.test_auth import bearer, login, token_for

API = "/api/v1/admin"
JKT = ZoneInfo("Asia/Jakarta")


@pytest.fixture
def school(app, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    admin = make_user(db, UserRole.ADMIN, "admin@contoh.id", "Admin Sekolah")
    other_admin = make_user(db, UserRole.ADMIN, "admin2@contoh.id", "Admin Dua")
    rina = make_guru(db, "rina@contoh.id", "Bu Rina")
    andi = make_guru(db, "andi@contoh.id", "Pak Andi")
    kelas_a = make_class(db, "5A", wali=rina, mapel=(andi,))
    kelas_b = make_class(db, "5B")
    ahmad = make_student(db, "Ahmad Rizky", kelas_a)
    return {
        "admin": admin.admin_profile, "other_admin": other_admin.admin_profile,
        "rina": rina, "andi": andi, "a": kelas_a, "b": kelas_b, "ahmad": ahmad,
    }


@pytest.fixture
def adm(client, school):
    return bearer(token_for(client, "admin@contoh.id"))


def call(client, method, path, headers, **kw):
    return client.request(method, f"{API}{path}", headers=headers, **kw)


def rows(db, model):
    db.expire_all()
    return list(db.scalars(select(model).order_by(model.id)))


def messages(db):
    return [r.pesan for r in rows(db, LogAktivitas)]


def class_row(db, code):
    db.expire_all()
    return db.scalar(select(Kelas).where(Kelas.nama_kelas == code))


class TestAuthorization:
    ENDPOINTS = [
        ("get", "/me"), ("put", "/me/password"), ("get", "/guru"), ("post", "/guru"),
        ("put", "/guru/1"), ("post", "/guru/1/reset-password"), ("put", "/guru/1/active"),
        ("delete", "/guru/1"), ("get", "/admins"), ("post", "/admins"), ("delete", "/admins/1"),
        ("get", "/siswa"), ("post", "/siswa"), ("post", "/siswa/move"), ("put", "/siswa/1"),
        ("delete", "/siswa/1"), ("get", "/classes"), ("post", "/classes"), ("delete", "/classes/5A"),
        ("put", "/classes/5A/wali"), ("post", "/classes/5A/mapel"), ("delete", "/classes/5A/mapel/1"),
        ("get", "/settings"), ("put", "/settings"), ("get", "/logs"),
    ]

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    def test_requires_a_token(self, client, school, method, path):
        assert call(client, method, path, {}).status_code == 401

    @pytest.mark.parametrize(("method", "path"), ENDPOINTS)
    @pytest.mark.parametrize("email", ["rina@contoh.id", "ortu.ahmad.rizky@contoh.id"])
    def test_only_admins_may_call_them(self, client, school, method, path, email):
        headers = bearer(token_for(client, email))

        assert call(client, method, path, headers, json={}).status_code == 403


class TestOwnAccount:
    def test_me_matches_the_admin_list_id(self, client, adm, school):
        me = call(client, "get", "/me", adm).json()

        assert me == {"id": school["admin"].id, "nama": "Admin Sekolah", "email": "admin@contoh.id"}
        assert me["id"] in [a["id"] for a in call(client, "get", "/admins", adm).json()]

    def test_change_password_keeps_the_session_and_enables_the_new_password(self, client, adm):
        response = call(
            client, "put", "/me/password", adm,
            json={"old_password": PASSWORD, "new_password": "BaruSekali99"},
        )

        assert response.status_code == 204
        assert call(client, "get", "/me", adm).status_code == 200
        assert login(client, "admin@contoh.id", "BaruSekali99").status_code == 200
        assert login(client, "admin@contoh.id", PASSWORD).status_code == 401

    def test_wrong_old_password_is_a_field_error_and_never_a_401(self, client, adm):
        response = call(
            client, "put", "/me/password", adm,
            json={"old_password": "salah-banget", "new_password": "BaruSekali99"},
        )

        assert response.status_code == 422
        assert response.json()["errors"] == {"old_password": "Password lama tidak sesuai."}

    @pytest.mark.parametrize(
        ("new", "field"), [(PASSWORD, "new_password"), ("pendek", "new_password")]
    )
    def test_new_password_must_differ_and_be_long_enough(self, client, adm, new, field):
        response = call(client, "put", "/me/password", adm, json={"old_password": PASSWORD, "new_password": new})

        assert response.status_code == 422
        assert field in response.json()["errors"]


class TestGuruAccounts:
    def create(self, client, adm, **override):
        body = {"nama": "Bu Sari", "email": "sari@contoh.id", "peran": "mapel", **override}
        return call(client, "post", "/guru", adm, json=body)

    def test_create_returns_credentials_and_the_temporary_password_works_once(self, client, adm):
        response = self.create(client, adm)

        assert response.status_code == 201
        body = response.json()
        assert set(body) == {"id", "email", "password_sementara"}
        assert body["email"] == "sari@contoh.id" and len(body["password_sementara"]) >= 8
        session = login(client, "sari@contoh.id", body["password_sementara"]).json()
        assert session["user"]["must_change_password"] is True
        assert session["user"]["nama"] == "Bu Sari"

    def test_email_is_normalised(self, client, adm):
        body = self.create(client, adm, email="  Sari@Contoh.ID ").json()

        assert body["email"] == "sari@contoh.id"

    def test_list_shape_and_role_follow_class_assignments(self, client, adm, school):
        body = call(client, "get", "/guru", adm).json()

        by_name = {g["nama"]: g for g in body}
        assert set(by_name["Bu Rina"]) == {
            "id", "nama", "email", "peran", "aktif", "wajib_ganti_password",
        }
        assert (by_name["Bu Rina"]["peran"], by_name["Pak Andi"]["peran"]) == ("wali", "mapel")
        assert by_name["Bu Rina"]["id"] == school["rina"].id

    def test_duplicate_email_is_a_field_conflict_regardless_of_case(self, client, adm):
        response = self.create(client, adm, email="RINA@contoh.id")

        assert response.status_code == 409
        assert response.json()["errors"] == {"email": "Email sudah dipakai akun lain."}

    @pytest.mark.parametrize(
        ("override", "field", "message"),
        [
            ({"email": "bukan-email"}, "email", "Format email tidak valid."),
            ({"nama": "   "}, "nama", "Kolom ini wajib diisi."),
            ({"peran": "kepala"}, "peran", "Nilai tidak valid."),
        ],
    )
    def test_invalid_input_returns_field_messages(self, client, adm, override, field, message):
        response = self.create(client, adm, **override)

        assert response.status_code == 422
        assert response.json()["errors"][field] == message

    def test_update_changes_name_and_email(self, client, adm, school):
        response = call(
            client, "put", f"/guru/{school['andi'].id}", adm,
            json={"nama": "Pak Andi S.Pd", "email": "andi.baru@contoh.id"},
        )

        assert response.status_code == 204
        assert login(client, "andi.baru@contoh.id", PASSWORD).json()["user"]["nama"] == "Pak Andi S.Pd"

    def test_update_cannot_take_another_accounts_email_but_may_keep_its_own(self, client, adm, school):
        taken = call(
            client, "put", f"/guru/{school['andi'].id}", adm,
            json={"nama": "Pak Andi", "email": "rina@contoh.id"},
        )
        same = call(
            client, "put", f"/guru/{school['andi'].id}", adm,
            json={"nama": "Pak Andi Baru", "email": "andi@contoh.id"},
        )

        assert taken.status_code == 409 and same.status_code == 204

    def test_reset_password_issues_a_new_one_and_revokes_old_sessions(self, client, adm, school):
        old_token = token_for(client, "andi@contoh.id")

        response = call(client, "post", f"/guru/{school['andi'].id}/reset-password", adm)

        body = response.json()
        assert response.status_code == 200
        assert body["email"] == "andi@contoh.id"
        assert client.get("/api/v1/auth/me", headers=bearer(old_token)).status_code == 401
        assert login(client, "andi@contoh.id", PASSWORD).status_code == 401
        session = login(client, "andi@contoh.id", body["password_sementara"]).json()
        assert session["user"]["must_change_password"] is True

    def test_deactivate_blocks_login_and_existing_tokens_until_reactivated(self, client, adm, school):
        token = token_for(client, "andi@contoh.id")
        path = f"/guru/{school['andi'].id}/active"

        assert call(client, "put", path, adm, json={"aktif": False}).status_code == 204
        assert login(client, "andi@contoh.id", PASSWORD).status_code == 403
        assert client.get("/api/v1/auth/me", headers=bearer(token)).status_code == 401
        listed = {g["nama"]: g for g in call(client, "get", "/guru", adm).json()}
        assert listed["Pak Andi"]["aktif"] is False

        assert call(client, "put", path, adm, json={"aktif": True}).status_code == 204
        assert login(client, "andi@contoh.id", PASSWORD).status_code == 200

    def test_delete_releases_assignments_and_keeps_the_records_they_made(self, client, db, adm, school):
        db.add(
            Nilai(
                siswa_id=school["ahmad"].id, kategori=KategoriNilai.LITERASI, jenis_ujian="Kuis",
                nilai=Decimal(80), tanggal=date(2026, 10, 1), dicatat_oleh=school["andi"].id,
            )
        )
        db.add(
            Absensi(
                siswa_id=school["ahmad"].id, tanggal=date(2026, 10, 1), status=StatusAbsensi.IZIN,
                dicatat_oleh=school["rina"].id,
            )
        )
        db.commit()

        assert call(client, "delete", f"/guru/{school['andi'].id}", adm).status_code == 204
        assert call(client, "delete", f"/guru/{school['rina'].id}", adm).status_code == 204

        assert rows(db, MapelGuru) == []
        assert class_row(db, "5A").wali_kelas_id is None
        (grade,) = rows(db, Nilai)
        (attendance,) = rows(db, Absensi)
        assert grade.dicatat_oleh is None and attendance.dicatat_oleh is None
        assert login(client, "andi@contoh.id", PASSWORD).status_code == 401
        assert rows(db, Guru) == []

    def test_unknown_account_is_404(self, client, adm):
        assert call(client, "delete", "/guru/9999", adm).status_code == 404
        assert call(client, "post", "/guru/9999/reset-password", adm).status_code == 404


class TestAdminAccounts:
    def test_create_list_and_log_in_with_the_temporary_password(self, client, adm):
        response = call(client, "post", "/admins", adm, json={"nama": "Admin Tiga", "email": "admin3@contoh.id"})

        assert response.status_code == 201
        assert login(client, "admin3@contoh.id", response.json()["password_sementara"]).status_code == 200
        names = [a["nama"] for a in call(client, "get", "/admins", adm).json()]
        assert "Admin Tiga" in names

    def test_list_shape(self, client, adm):
        first = call(client, "get", "/admins", adm).json()[0]

        assert set(first) == {"id", "nama", "email", "aktif", "wajib_ganti_password"}

    def test_cannot_delete_deactivate_or_reset_your_own_account(self, client, adm, school):
        own = school["admin"].id

        assert call(client, "delete", f"/admins/{own}", adm).status_code == 409
        assert call(client, "put", f"/admins/{own}/active", adm, json={"aktif": False}).status_code == 409
        assert call(client, "post", f"/admins/{own}/reset-password", adm).status_code == 409
        assert call(client, "get", "/me", adm).status_code == 200

    def test_can_manage_another_admin(self, client, db, adm, school):
        other = school["other_admin"].id

        assert call(client, "put", f"/admins/{other}/active", adm, json={"aktif": False}).status_code == 204
        assert login(client, "admin2@contoh.id", PASSWORD).status_code == 403
        assert call(client, "delete", f"/admins/{other}", adm).status_code == 204
        assert db.scalar(select(func.count()).select_from(User).where(User.role == UserRole.ADMIN)) == 1


class TestSiswaAccounts:
    def create(self, client, adm, **override):
        body = {"nama": "Dewi Lestari", "kelas": "5B", "nama_orang_tua": "Bapak Dedi", **override}
        return call(client, "post", "/siswa", adm, json=body)

    def test_create_makes_the_student_and_a_parent_account_that_can_log_in(self, client, db, adm, school):
        response = self.create(client, adm)

        assert response.status_code == 201
        body = response.json()
        assert body["email"] == "ortu.dewi.lestari@ortu.sdn02pakunden.sch.id"
        parent_login = login(client, body["email"], body["password_sementara"]).json()
        assert parent_login["user"]["role"] == "ortu"
        assert parent_login["user"]["must_change_password"] is True
        assert parent_login["user"]["nama"] == "Bapak Dedi"
        (siswa,) = [s for s in rows(db, Siswa) if s.nama == "Dewi Lestari"]
        assert siswa.id == body["id"] and siswa.kelas_id == school["b"].id

    def test_the_parent_can_see_the_new_child_through_the_portal(self, client, adm):
        body = self.create(client, adm).json()
        token = login(client, body["email"], body["password_sementara"]).json()["token"]

        children = client.get("/api/v1/ortu/children", headers=bearer(token)).json()

        assert [(c["nama"], c["kelas"]) for c in children] == [("Dewi Lestari", "5B")]

    def test_students_with_the_same_name_get_distinct_emails(self, client, adm):
        first = self.create(client, adm).json()["email"]
        second = self.create(client, adm).json()["email"]

        assert first != second and second.startswith("ortu.dewi.lestari2@")

    def test_accents_and_punctuation_become_a_clean_email(self, client, adm):
        body = self.create(client, adm, nama="Sri Wahyuní O'Neil").json()

        assert body["email"].startswith("ortu.sri.wahyuni.o.neil@")

    def test_unknown_class_is_404_and_creates_nothing(self, client, db, adm):
        before = len(rows(db, OrangTua))

        assert self.create(client, adm, kelas="6F").status_code == 404
        assert len(rows(db, OrangTua)) == before

    def test_list_shape(self, client, adm, school):
        (item,) = call(client, "get", "/siswa", adm).json()

        assert item == {
            "id": school["ahmad"].id, "nama": "Ahmad Rizky", "email": "ortu.ahmad.rizky@contoh.id",
            "aktif": True, "wajib_ganti_password": False, "kelas": "5A", "nama_orang_tua": "Ortu Ahmad Rizky",
        }

    def test_update_changes_name_class_and_parent_name(self, client, db, adm, school):
        response = call(
            client, "put", f"/siswa/{school['ahmad'].id}", adm,
            json={"nama": "Ahmad R.", "kelas": "5B", "nama_orang_tua": "Ibu Ani"},
        )

        assert response.status_code == 204
        (item,) = call(client, "get", "/siswa", adm).json()
        assert (item["nama"], item["kelas"], item["nama_orang_tua"]) == ("Ahmad R.", "5B", "Ibu Ani")

    def test_deleting_the_last_child_also_removes_the_parent_account_and_history(self, client, db, adm, school):
        db.add(Absensi(siswa_id=school["ahmad"].id, tanggal=date(2026, 10, 1), status=StatusAbsensi.SAKIT))
        db.add(
            Nilai(
                siswa_id=school["ahmad"].id, kategori=KategoriNilai.LITERASI, jenis_ujian="Kuis",
                nilai=Decimal(80), tanggal=date(2026, 10, 1),
            )
        )
        db.commit()

        assert call(client, "delete", f"/siswa/{school['ahmad'].id}", adm).status_code == 204

        assert rows(db, Siswa) == [] and rows(db, Absensi) == [] and rows(db, Nilai) == []
        assert login(client, "ortu.ahmad.rizky@contoh.id", PASSWORD).status_code == 401

    def test_deleting_one_of_two_siblings_keeps_the_parent_account(self, client, db, adm, school):
        parent = school["ahmad"].orang_tua
        sibling = make_student(db, "Adik Ahmad", school["a"], ortu=parent)

        assert call(client, "delete", f"/siswa/{school['ahmad'].id}", adm).status_code == 204

        assert [s.id for s in rows(db, Siswa)] == [sibling.id]
        assert login(client, "ortu.ahmad.rizky@contoh.id", PASSWORD).status_code == 200

    def test_deactivate_and_reset_apply_to_the_parent_account(self, client, adm, school):
        path = f"/siswa/{school['ahmad'].id}"

        call(client, "put", f"{path}/active", adm, json={"aktif": False})
        assert login(client, "ortu.ahmad.rizky@contoh.id", PASSWORD).status_code == 403
        assert call(client, "get", "/siswa", adm).json()[0]["aktif"] is False

        call(client, "put", f"{path}/active", adm, json={"aktif": True})
        reset = call(client, "post", f"{path}/reset-password", adm).json()
        assert reset["email"] == "ortu.ahmad.rizky@contoh.id"
        assert login(client, reset["email"], reset["password_sementara"]).status_code == 200


class TestClasses:
    def test_list_shape(self, client, adm, school):
        body = call(client, "get", "/classes", adm).json()

        assert body == [
            {
                "kode": "5A", "wali_id": school["rina"].id, "mapel_ids": [school["andi"].id],
                # Penugasan dari sebelum ada data mapel: tanpa mata pelajaran.
                "penugasan": [{"guru_id": school["andi"].id, "mapel_id": None, "mapel": None}],
            },
            {"kode": "5B", "wali_id": None, "mapel_ids": [], "penugasan": []},
        ]

    def test_create_normalises_the_code(self, client, adm):
        response = call(client, "post", "/classes", adm, json={"kode": "6c"})

        assert response.status_code == 201
        assert "6C" in [k["kode"] for k in call(client, "get", "/classes", adm).json()]

    def test_create_rejects_duplicates_and_bad_codes(self, client, adm):
        duplicate = call(client, "post", "/classes", adm, json={"kode": "5A"})
        bad = call(client, "post", "/classes", adm, json={"kode": "9Z"})

        assert duplicate.status_code == 409
        assert bad.status_code == 422 and bad.json()["errors"]["kode"] == "Gunakan format seperti 5C."

    def test_delete_requires_an_empty_class(self, client, db, adm, school):
        blocked = call(client, "delete", "/classes/5A", adm)
        done = call(client, "delete", "/classes/5B", adm)

        assert blocked.status_code == 409 and "1 siswa" in blocked.json()["message"]
        assert done.status_code == 204
        assert class_row(db, "5B") is None and class_row(db, "5A") is not None

    def test_delete_releases_teachers_from_the_class(self, client, db, adm, school):
        call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": school["andi"].id})

        assert call(client, "delete", "/classes/5B", adm).status_code == 204

        assert [m.kelas_id for m in rows(db, MapelGuru)] == [school["a"].id]

    def test_assigning_wali_moves_the_teacher_away_from_their_previous_class(self, client, db, adm, school):
        response = call(client, "put", "/classes/5B/wali", adm, json={"guru_id": str(school["rina"].id)})

        assert response.status_code == 204
        assert class_row(db, "5B").wali_kelas_id == school["rina"].id
        assert class_row(db, "5A").wali_kelas_id is None

    def test_the_new_wali_sees_the_class_in_their_session(self, client, adm, school):
        call(client, "put", "/classes/5B/wali", adm, json={"guru_id": school["andi"].id})

        me = client.get("/api/v1/auth/me", headers=bearer(token_for(client, "andi@contoh.id"))).json()

        assert me["guru"]["wali_kelas"] == ["5B"] and me["guru"]["mapel"] == ["5A"]

    @pytest.mark.parametrize("value", ["", None])
    def test_blank_or_null_clears_the_wali(self, client, db, adm, value):
        assert call(client, "put", "/classes/5A/wali", adm, json={"guru_id": value}).status_code == 204

        assert class_row(db, "5A").wali_kelas_id is None

    def test_reassigning_the_same_wali_is_a_no_op(self, client, db, adm, school):
        call(client, "put", "/classes/5A/wali", adm, json={"guru_id": school["rina"].id})

        assert class_row(db, "5A").wali_kelas_id == school["rina"].id

    def test_inactive_or_unknown_guru_cannot_be_assigned(self, client, adm, school):
        call(client, "put", f"/guru/{school['andi'].id}/active", adm, json={"aktif": False})

        inactive = call(client, "put", "/classes/5B/wali", adm, json={"guru_id": school["andi"].id})
        unknown = call(client, "put", "/classes/5B/wali", adm, json={"guru_id": 9999})
        mapel = call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": school["andi"].id})

        assert (inactive.status_code, unknown.status_code, mapel.status_code) == (422, 404, 422)

    def test_add_and_remove_mapel(self, client, db, adm, school):
        added = call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": str(school["rina"].id)})
        duplicate = call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": school["rina"].id})
        removed = call(client, "delete", f"/classes/5B/mapel/{school['rina'].id}", adm)
        missing = call(client, "delete", f"/classes/5B/mapel/{school['rina'].id}", adm)

        assert (added.status_code, duplicate.status_code) == (204, 409)
        assert (removed.status_code, missing.status_code) == (204, 404)
        assert [m.kelas_id for m in rows(db, MapelGuru)] == [school["a"].id]

    def test_new_mapel_guru_can_record_in_the_class(self, client, adm, school):
        call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": school["rina"].id})
        headers = bearer(token_for(client, "rina@contoh.id"))
        siswa = call(client, "post", "/siswa", adm, json={"nama": "Dewi", "kelas": "5B", "nama_orang_tua": "Ibu"}).json()

        response = client.put(
            f"/api/v1/guru/classes/5B/attendance/{siswa['id']}",
            json={"status": "H", "metode_input": "manual"}, headers=headers,
        )

        assert response.status_code == 204

    def test_unknown_class_is_404(self, client, adm, school):
        assert call(client, "put", "/classes/9Z/wali", adm, json={"guru_id": school["rina"].id}).status_code == 404
        assert call(client, "delete", "/classes/9Z", adm).status_code == 404


class TestMoveStudents:
    def test_moves_students_with_their_history(self, client, db, adm, school):
        db.add(Absensi(siswa_id=school["ahmad"].id, tanggal=date(2026, 10, 1), status=StatusAbsensi.SAKIT))
        db.commit()

        response = call(
            client, "post", "/siswa/move", adm,
            json={"siswa_ids": [str(school["ahmad"].id)], "kelas_tujuan": "5B"},
        )

        assert response.status_code == 204
        db.expire_all()
        assert db.get(Siswa, school["ahmad"].id).kelas_id == school["b"].id
        assert len(rows(db, Absensi)) == 1

    def test_unknown_student_or_class_changes_nothing(self, client, db, adm, school):
        missing = call(
            client, "post", "/siswa/move", adm,
            json={"siswa_ids": [school["ahmad"].id, 9999], "kelas_tujuan": "5B"},
        )
        bad_class = call(
            client, "post", "/siswa/move", adm,
            json={"siswa_ids": [school["ahmad"].id], "kelas_tujuan": "6F"},
        )

        assert (missing.status_code, bad_class.status_code) == (404, 404)
        db.expire_all()
        assert db.get(Siswa, school["ahmad"].id).kelas_id == school["a"].id

    def test_moving_into_the_current_class_is_a_quiet_no_op(self, client, db, adm, school):
        before = len(rows(db, LogAktivitas))

        response = call(
            client, "post", "/siswa/move", adm,
            json={"siswa_ids": [school["ahmad"].id], "kelas_tujuan": "5A"},
        )

        assert response.status_code == 204 and len(rows(db, LogAktivitas)) == before

    def test_requires_at_least_one_student(self, client, adm):
        response = call(client, "post", "/siswa/move", adm, json={"siswa_ids": [], "kelas_tujuan": "5B"})

        assert response.status_code == 422


class TestSettings:
    def test_defaults(self, client, adm):
        assert call(client, "get", "/settings", adm).json() == {
            "tahun_ajaran": "2026/2027", "periode_aktif": None, "batas_jam_terlambat": None,
        }

    def test_save_is_visible_to_admin_and_to_guru_sessions(self, client, adm):
        response = call(
            client, "put", "/settings", adm,
            json={"tahun_ajaran": "2027/2028", "batas_jam_terlambat": "07:15"},
        )

        assert response.status_code == 204
        assert call(client, "get", "/settings", adm).json() == {
            "tahun_ajaran": "2027/2028", "periode_aktif": None, "batas_jam_terlambat": "07:15",
        }
        session = login(client, "rina@contoh.id", PASSWORD).json()
        assert session["pengaturan"]["batas_jam_terlambat"] == "07:15"

    @pytest.mark.parametrize("value", [None, ""])
    def test_blank_late_limit_clears_it(self, client, adm, value):
        call(client, "put", "/settings", adm, json={"tahun_ajaran": "2026/2027", "batas_jam_terlambat": "07:00"})

        call(client, "put", "/settings", adm, json={"tahun_ajaran": "2026/2027", "batas_jam_terlambat": value})

        assert call(client, "get", "/settings", adm).json()["batas_jam_terlambat"] is None

    @pytest.mark.parametrize(
        ("body", "field"),
        [
            ({"tahun_ajaran": "2026/2028"}, "tahun_ajaran"),
            ({"tahun_ajaran": "2026-2027"}, "tahun_ajaran"),
            ({"tahun_ajaran": "2026/2027", "batas_jam_terlambat": "25:00"}, "batas_jam_terlambat"),
            ({"tahun_ajaran": "2026/2027", "batas_jam_terlambat": "pagi"}, "batas_jam_terlambat"),
        ],
    )
    def test_invalid_values_are_rejected_with_a_field_message(self, client, adm, body, field):
        response = call(client, "put", "/settings", adm, json=body)

        assert response.status_code == 422 and field in response.json()["errors"]
        assert call(client, "get", "/settings", adm).json()["tahun_ajaran"] == "2026/2027"

    def test_the_late_limit_drives_face_scan_status(self, client, db, app, adm, school):
        from tests.test_face import image, upload

        call(client, "put", "/settings", adm, json={"tahun_ajaran": "2026/2027", "batas_jam_terlambat": "07:30"})
        rina = bearer(token_for(client, "rina@contoh.id"))
        andi = bearer(token_for(client, "andi@contoh.id"))
        client.post(f"/api/v1/guru/classes/5A/students/{school['ahmad'].id}/face", files=upload(image(1)), headers=rina)

        result = client.post("/api/v1/guru/classes/5A/attendance/face", files=upload(image(1)), headers=andi).json()

        assert result["status"] == "T"


class TestLogs:
    def test_actions_are_logged_with_their_type_newest_first(self, client, adm, school):
        call(client, "post", "/classes", adm, json={"kode": "6A"})
        call(client, "post", "/guru", adm, json={"nama": "Bu Sari", "email": "sari@contoh.id"})
        call(client, "put", "/settings", adm, json={"tahun_ajaran": "2027/2028"})

        body = call(client, "get", "/logs", adm).json()

        assert [e["jenis"] for e in body] == ["Sistem", "Akun", "Kelas"]
        assert body[2]["pesan"] == "Admin Sekolah membuat kelas 6A."
        assert body[1]["pesan"] == "Admin Sekolah membuat akun guru Bu Sari."
        assert set(body[0]) == {"waktu", "jenis", "pesan"}
        assert datetime.fromisoformat(body[0]["waktu"]).tzinfo is not None

    def test_every_mutation_type_leaves_a_log_line(self, client, db, adm, school):
        call(client, "put", "/classes/5B/wali", adm, json={"guru_id": school["andi"].id})
        call(client, "post", "/classes/5B/mapel", adm, json={"guru_id": school["rina"].id})
        call(client, "post", "/siswa/move", adm, json={"siswa_ids": [school["ahmad"].id], "kelas_tujuan": "5B"})
        call(client, "put", f"/siswa/{school['ahmad'].id}/active", adm, json={"aktif": False})
        call(client, "delete", f"/siswa/{school['ahmad'].id}", adm)

        text = " | ".join(messages(db))

        assert "menetapkan Pak Andi sebagai wali kelas 5B" in text
        assert "menugaskan Bu Rina sebagai guru mapel kelas 5B" in text
        assert "memindahkan 1 siswa dari kelas 5A ke kelas 5B" in text
        assert "menonaktifkan akun ortu.ahmad.rizky@contoh.id" in text
        assert "menghapus siswa Ahmad Rizky" in text

    def test_failed_actions_leave_no_log(self, client, db, adm):
        call(client, "post", "/classes", adm, json={"kode": "5A"})
        call(client, "post", "/guru", adm, json={"nama": "X", "email": "rina@contoh.id"})

        assert messages(db) == []

    def test_limit_is_respected_and_bounded(self, client, adm):
        for code in ("6A", "6B", "6C"):
            call(client, "post", "/classes", adm, json={"kode": code})

        assert len(call(client, "get", "/logs?limit=2", adm).json()) == 2
        assert call(client, "get", "/logs?limit=0", adm).status_code == 422
        assert call(client, "get", "/logs?limit=5000", adm).status_code == 422
        assert call(client, "get", "/logs?limit=500", adm).status_code == 200

    def test_logs_survive_the_deletion_of_the_actor(self, client, db, adm, school):
        call(client, "post", "/classes", adm, json={"kode": "6A"})
        second = bearer(token_for(client, "admin2@contoh.id"))
        call(client, "post", "/classes", second, json={"kode": "6B"})

        call(client, "delete", f"/admins/{school['other_admin'].id}", adm)

        assert len([m for m in messages(db) if "membuat kelas" in m]) == 2
