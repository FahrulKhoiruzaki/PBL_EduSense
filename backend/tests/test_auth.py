from datetime import datetime, time, timedelta, timezone

from sqlalchemy import select

from app.core.security import create_access_token
from app.models import PengaturanSekolah, User
from app.models.base import UserRole
from tests.factories import PASSWORD, make_class, make_guru, make_user

API = "/api/v1"


def login(client, email, password=PASSWORD):
    return client.post(f"{API}/auth/login", json={"email": email, "password": password})


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def token_for(client, email, password=PASSWORD):
    response = login(client, email, password)
    assert response.status_code == 200, response.text
    return response.json()["token"]


def test_login_guru_returns_the_shape_the_flutter_app_parses(client, db):
    rina = make_guru(db, "bu.rina@contoh.id", "Bu Rina", nip="198501012010011001")
    andi = make_guru(db, "pak.andi@contoh.id", "Pak Andi")
    make_class(db, "5A", wali=rina, mapel=(andi,))
    make_class(db, "5B", wali=None, mapel=(rina, andi))
    db.execute(PengaturanSekolah.__table__.update().values(batas_jam_terlambat=time(7, 15)))
    db.commit()

    body = login(client, "bu.rina@contoh.id").json()

    assert body["token"]
    assert body["user"] == {
        "id": rina.user_id,
        "email": "bu.rina@contoh.id",
        "nama": "Bu Rina",
        "role": "guru",
        "must_change_password": False,
    }
    assert body["guru"] == {"nip": "198501012010011001", "wali_kelas": ["5A"], "mapel": ["5B"]}
    assert body["pengaturan"] == {"batas_jam_terlambat": "07:15"}

    andi_body = login(client, "pak.andi@contoh.id").json()
    assert andi_body["guru"]["wali_kelas"] == []
    assert andi_body["guru"]["mapel"] == ["5A", "5B"]
    assert andi_body["guru"]["nip"] is None


def test_login_admin_and_parent_have_no_guru_block(client, db):
    make_user(db, UserRole.ADMIN, "admin@contoh.id", "Admin Sekolah")
    make_user(db, UserRole.ORTU, "orangtua@contoh.id", "Orang tua Ahmad", must_change=True)

    admin = login(client, "admin@contoh.id").json()
    ortu = login(client, "orangtua@contoh.id").json()

    assert admin["user"]["role"] == "admin" and admin["user"]["nama"] == "Admin Sekolah"
    assert admin["guru"] is None
    assert ortu["user"]["role"] == "ortu" and ortu["user"]["must_change_password"] is True
    assert ortu["pengaturan"] == {"batas_jam_terlambat": None}


def test_wrong_password_and_unknown_email_are_indistinguishable(client, db):
    make_guru(db, "ada@contoh.id")

    wrong = login(client, "ada@contoh.id", "SalahSalah1")
    unknown = login(client, "tidak.ada@contoh.id")

    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json() == {"message": "Email atau password tidak sesuai."}


def test_email_is_case_insensitive_and_trimmed(client, db):
    make_guru(db, "bu.rina@contoh.id")
    assert login(client, "  Bu.Rina@Contoh.ID ").status_code == 200


def test_inactive_account_is_refused_only_with_the_right_password(client, db):
    guru = make_guru(db, "off@contoh.id")
    user = db.get(User, guru.user_id)
    user.is_active = False
    db.commit()

    refused = login(client, "off@contoh.id")
    assert refused.status_code == 403
    assert refused.json()["message"] == "Akun Anda dinonaktifkan. Hubungi admin sekolah."
    assert login(client, "off@contoh.id", "SalahSalah1").status_code == 401


def test_password_is_stored_hashed_and_login_records_the_time(client, db):
    guru = make_guru(db, "hash@contoh.id")
    login(client, "hash@contoh.id")

    db.expire_all()
    user = db.get(User, guru.user_id)
    assert user.password_hash.startswith("$argon2")
    assert PASSWORD not in user.password_hash
    assert user.last_login_at is not None


def test_missing_fields_use_the_error_format_the_app_reads(client):
    response = client.post(f"{API}/auth/login", json={})
    assert response.status_code == 422
    assert response.json() == {
        "message": "Data yang dikirim tidak valid.",
        "errors": {"email": "Kolom ini wajib diisi.", "password": "Kolom ini wajib diisi."},
    }


def test_me_requires_a_valid_token(client, db):
    make_guru(db, "me@contoh.id")
    expired_message = "Sesi Anda telah berakhir. Silakan masuk kembali."

    assert client.get(f"{API}/auth/me").status_code == 401
    assert client.get(f"{API}/auth/me", headers=bearer("bukan-token")).json()["message"] == expired_message


def test_me_returns_the_same_session_as_login(client, db):
    rina = make_guru(db, "me@contoh.id", "Bu Rina")
    make_class(db, "5A", wali=rina)
    logged = login(client, "me@contoh.id").json()

    me = client.get(f"{API}/auth/me", headers=bearer(logged["token"])).json()

    assert me == {k: v for k, v in logged.items() if k != "token"}


def test_expired_and_forged_tokens_are_rejected(client, db, settings):
    guru = make_guru(db, "tok@contoh.id")
    kwargs = dict(user_id=guru.user_id, role="guru", version=0, minutes=60)
    old = datetime.now(timezone.utc) - timedelta(hours=3)

    expired = create_access_token(secret=settings.secret_key, now=old, **kwargs)
    forged = create_access_token(secret="y" * 48, **kwargs)
    valid = create_access_token(secret=settings.secret_key, **kwargs)

    assert client.get(f"{API}/auth/me", headers=bearer(expired)).status_code == 401
    assert client.get(f"{API}/auth/me", headers=bearer(forged)).status_code == 401
    assert client.get(f"{API}/auth/me", headers=bearer(valid)).status_code == 200


def test_token_stops_working_when_the_account_is_deactivated(client, db):
    guru = make_guru(db, "gone@contoh.id")
    token = token_for(client, "gone@contoh.id")

    db.get(User, guru.user_id).is_active = False
    db.commit()

    assert client.get(f"{API}/auth/me", headers=bearer(token)).status_code == 401


def test_logout_revokes_that_token_but_a_new_login_works(client, db):
    make_guru(db, "out@contoh.id")
    first = token_for(client, "out@contoh.id")

    assert client.post(f"{API}/auth/logout", headers=bearer(first)).status_code == 204

    assert client.get(f"{API}/auth/me", headers=bearer(first)).status_code == 401
    second = token_for(client, "out@contoh.id")
    assert client.get(f"{API}/auth/me", headers=bearer(second)).status_code == 200


def test_forced_password_change_keeps_the_session_alive(client, db):
    guru = make_guru(db, "baru@contoh.id", must_change=True)
    token = token_for(client, "baru@contoh.id")

    response = client.put(
        f"{API}/auth/password", json={"new_password": "PasswordBaru1"}, headers=bearer(token)
    )

    assert response.status_code == 204
    assert client.get(f"{API}/auth/me", headers=bearer(token)).json()["user"]["must_change_password"] is False
    assert login(client, "baru@contoh.id", PASSWORD).status_code == 401
    assert login(client, "baru@contoh.id", "PasswordBaru1").status_code == 200
    assert guru is not None


def test_short_new_password_is_rejected_with_a_field_error(client, db):
    make_guru(db, "pendek@contoh.id", must_change=True)
    token = token_for(client, "pendek@contoh.id")

    response = client.put(f"{API}/auth/password", json={"new_password": "abc"}, headers=bearer(token))

    assert response.status_code == 422
    assert response.json()["errors"] == {"new_password": "Minimal 8 karakter."}


def test_password_cannot_be_changed_without_the_old_one_once_it_is_permanent(client, db):
    make_guru(db, "tetap@contoh.id", must_change=False)
    token = token_for(client, "tetap@contoh.id")

    response = client.put(
        f"{API}/auth/password", json={"new_password": "PasswordBaru1"}, headers=bearer(token)
    )

    assert response.status_code == 403
    assert login(client, "tetap@contoh.id").status_code == 200


def test_forgot_password_never_reveals_whether_the_email_exists(client, db):
    make_guru(db, "ada@contoh.id")

    known = client.post(f"{API}/auth/forgot-password", json={"email": "ada@contoh.id"})
    unknown = client.post(f"{API}/auth/forgot-password", json={"email": "tidak@contoh.id"})

    assert known.status_code == unknown.status_code == 202
    assert known.json() == unknown.json()


def test_cors_allows_local_web_dev_but_not_other_origins(client):
    allowed = client.options(
        f"{API}/auth/login",
        headers={
            "Origin": "http://localhost:5555",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    blocked = client.options(
        f"{API}/auth/login",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )

    assert allowed.headers.get("access-control-allow-origin") == "http://localhost:5555"
    assert "access-control-allow-origin" not in blocked.headers


def test_unknown_route_uses_the_message_format(client):
    response = client.get(f"{API}/tidak-ada")
    assert response.status_code == 404
    assert response.json() == {"message": "Data tidak ditemukan."}


def test_health_reports_the_database(client, db):
    assert client.get("/health").json() == {"status": "ok"}
    assert db.scalar(select(User.id).limit(1)) is None
