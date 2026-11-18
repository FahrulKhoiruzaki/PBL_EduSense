from datetime import date, datetime, time
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select, update

from app.models import Absensi, PengaturanSekolah, WajahSiswa
from app.models.base import MetodeInput, StatusAbsensi, UserRole
from tests.factories import make_class, make_guru, make_student, make_user
from tests.test_auth import bearer, token_for

API = "/api/v1/guru/classes"
JKT = ZoneInfo("Asia/Jakarta")


def image(seed: int, kind: str = "jpeg") -> bytes:
    header = {"jpeg": b"\xff\xd8\xff\xe0", "png": b"\x89PNG\r\n\x1a\n"}[kind]
    return header + bytes([seed % 256]) * 80 + seed.to_bytes(4, "big")


def upload(data: bytes, name: str = "scan.jpg"):
    # Dio mengirim application/octet-stream bila tipe tidak diset; server tidak boleh bergantung padanya.
    return {"foto": (name, data, "application/octet-stream")}


@pytest.fixture
def school(app, db):
    app.state.clock = lambda: datetime(2026, 10, 8, 7, 41, 5, tzinfo=JKT)
    rina = make_guru(db, "rina@contoh.id", "Bu Rina")
    andi = make_guru(db, "andi@contoh.id", "Pak Andi")
    sari = make_guru(db, "sari@contoh.id", "Bu Sari")
    kelas_a = make_class(db, "5A", wali=rina, mapel=(andi,))
    kelas_b = make_class(db, "5B", wali=sari, mapel=(andi, rina))
    ahmad = make_student(db, "Ahmad Rizky", kelas_a)
    siti = make_student(db, "Siti Aulia", kelas_a)
    budi = make_student(db, "Budi Santoso", kelas_b)
    return {
        "rina": rina, "andi": andi, "sari": sari, "a": kelas_a, "b": kelas_b,
        "ahmad": ahmad, "siti": siti, "budi": budi,
    }


@pytest.fixture
def auth(client, school):
    def headers(email: str) -> dict[str, str]:
        return bearer(token_for(client, email))

    return headers


def enroll(client, auth, school, siswa, data, wali="rina@contoh.id", kode="5A"):
    return client.post(
        f"{API}/{kode}/students/{siswa.id}/face", files=upload(data), headers=auth(wali)
    )


def scan(client, auth, data, guru="andi@contoh.id", kode="5A"):
    return client.post(f"{API}/{kode}/attendance/face", files=upload(data), headers=auth(guru))


def attendance_rows(db):
    db.expire_all()
    return list(db.scalars(select(Absensi).order_by(Absensi.id)))


def test_enrolled_face_is_recorded_present_with_the_face_method(client, db, auth, school):
    assert enroll(client, auth, school, school["ahmad"], image(1)).status_code == 201

    response = scan(client, auth, image(1))

    assert response.status_code == 200
    assert response.json() == {
        "hasil": "cocok",
        "kode": None,
        "pesan": None,
        "siswa_id": school["ahmad"].id,
        "nama": "Ahmad Rizky",
        "kelas": "5A",
        "waktu": "07:41:05",
        "status": "H",
    }
    (row,) = attendance_rows(db)
    assert row.siswa_id == school["ahmad"].id
    assert row.tanggal == date(2026, 10, 8)
    assert row.status is StatusAbsensi.HADIR
    assert row.metode_input is MetodeInput.FACE_RECOGNITION
    assert row.dicatat_oleh == school["andi"].id


def test_scanning_the_same_student_twice_reports_a_duplicate_and_keeps_one_row(client, db, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))
    scan(client, auth, image(1))

    second = scan(client, auth, image(1)).json()

    assert second["hasil"] == "duplikat" and second["kode"] == "FaceDuplicate"
    assert second["nama"] == "Ahmad Rizky" and second["waktu"] == "07:41:05"
    assert len(attendance_rows(db)) == 1


def test_unregistered_face_returns_FaceNotRecognized_without_recording(client, db, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))

    response = scan(client, auth, image(99))

    assert response.status_code == 200
    body = response.json()
    assert body["hasil"] == "tidak_dikenali"
    assert body["kode"] == "FaceNotRecognized"
    assert body["siswa_id"] is None and body["nama"] is None
    assert attendance_rows(db) == []


def test_scan_with_nobody_enrolled_is_simply_not_recognized(client, db, auth, school):
    assert scan(client, auth, image(1)).json()["hasil"] == "tidak_dikenali"


def test_a_student_from_another_class_is_reported_without_naming_them(client, db, auth, school):
    enroll(client, auth, school, school["budi"], image(7), wali="sari@contoh.id", kode="5B")

    body = scan(client, auth, image(7), kode="5A").json()

    assert body["hasil"] == "kelas_lain" and body["kode"] == "FaceOtherClass"
    assert body["nama"] is None and body["siswa_id"] is None
    assert attendance_rows(db) == []


def test_arrival_after_the_school_limit_is_recorded_as_late(client, db, auth, school):
    db.execute(update(PengaturanSekolah).values(batas_jam_terlambat=time(7, 15)))
    db.commit()
    enroll(client, auth, school, school["ahmad"], image(1))

    body = scan(client, auth, image(1)).json()

    assert body["hasil"] == "cocok" and body["status"] == "T"
    assert attendance_rows(db)[0].status is StatusAbsensi.TERLAMBAT


def test_arrival_before_the_limit_is_present_on_time(client, db, auth, school):
    db.execute(update(PengaturanSekolah).values(batas_jam_terlambat=time(7, 45)))
    db.commit()
    enroll(client, auth, school, school["ahmad"], image(1))

    assert scan(client, auth, image(1)).json()["status"] == "H"


def test_an_excused_absence_is_overwritten_when_the_student_shows_up(client, db, auth, school):
    db.add(Absensi(siswa_id=school["ahmad"].id, tanggal=date(2026, 10, 8), status=StatusAbsensi.IZIN,
                   catatan="Acara keluarga"))
    db.commit()
    enroll(client, auth, school, school["ahmad"], image(1))

    body = scan(client, auth, image(1)).json()

    assert body["hasil"] == "cocok"
    (row,) = attendance_rows(db)
    assert row.status is StatusAbsensi.HADIR and row.catatan is None
    assert row.metode_input is MetodeInput.FACE_RECOGNITION


def test_yesterdays_attendance_does_not_block_today(client, db, auth, school):
    db.add(Absensi(siswa_id=school["ahmad"].id, tanggal=date(2026, 10, 7), status=StatusAbsensi.HADIR,
                   waktu=time(7, 0)))
    db.commit()
    enroll(client, auth, school, school["ahmad"], image(1))

    assert scan(client, auth, image(1)).json()["hasil"] == "cocok"
    assert len(attendance_rows(db)) == 2


def test_the_attendance_date_follows_the_school_timezone_not_utc(client, db, auth, school, app):
    # 23.30 WIB tanggal 8 = 16.30 UTC tanggal 8; 00.10 WIB tanggal 9 = 17.10 UTC tanggal 8.
    app.state.clock = lambda: datetime(2026, 10, 9, 0, 10, tzinfo=JKT)
    enroll(client, auth, school, school["ahmad"], image(1))

    scan(client, auth, image(1))

    assert attendance_rows(db)[0].tanggal == date(2026, 10, 9)


@pytest.mark.parametrize(
    ("email", "expected"),
    [
        ("rina@contoh.id", 403),  # wali kelas 5A tetapi bukan guru mapel 5A: hanya melihat
        ("sari@contoh.id", 403),  # guru lain
    ],
)
def test_only_the_classes_subject_teacher_can_record_attendance(client, db, auth, school, email, expected):
    assert scan(client, auth, image(1), guru=email).status_code == expected
    assert attendance_rows(db) == []


def test_scan_rejects_anonymous_parent_and_admin_callers(client, db, school):
    make_user(db, UserRole.ORTU, "ortu@contoh.id")
    make_user(db, UserRole.ADMIN, "admin@contoh.id")

    assert client.post(f"{API}/5A/attendance/face", files=upload(image(1))).status_code == 401
    for email in ("ortu@contoh.id", "admin@contoh.id"):
        headers = bearer(token_for(client, email))
        assert client.post(f"{API}/5A/attendance/face", files=upload(image(1)), headers=headers).status_code == 403


def test_scan_in_an_unknown_class_is_404(client, auth, school):
    assert scan(client, auth, image(1), kode="9Z").status_code == 404


def test_class_code_is_case_insensitive(client, auth, school):
    assert scan(client, auth, image(1), kode="5a").status_code == 200


@pytest.mark.parametrize(
    "payload",
    [b"", b"ini bukan gambar sama sekali", b"%PDF-1.4 dokumen"],
)
def test_non_images_and_empty_files_are_refused_with_a_field_error(client, auth, school, payload):
    response = scan(client, auth, payload)
    assert response.status_code == 422
    assert "foto" in response.json()["errors"]


def test_missing_file_field_is_a_validation_error(client, auth, school):
    response = client.post(f"{API}/5A/attendance/face", headers=auth("andi@contoh.id"))
    assert response.status_code == 422
    assert response.json()["errors"] == {"foto": "Kolom ini wajib diisi."}


def test_oversized_upload_is_rejected(client, auth, school):
    response = scan(client, auth, image(1) + b"\x00" * (70 * 1024))
    assert response.status_code == 413


def test_png_images_are_accepted_too(client, auth, school):
    assert enroll(client, auth, school, school["ahmad"], image(3, "png")).status_code == 201


def test_only_the_homeroom_teacher_can_enroll_faces(client, db, auth, school):
    for email in ("andi@contoh.id", "sari@contoh.id"):
        assert enroll(client, auth, school, school["ahmad"], image(1), wali=email).status_code == 403
    assert db.scalars(select(WajahSiswa)).all() == []


def test_enrolling_a_student_from_another_class_is_404(client, auth, school):
    assert enroll(client, auth, school, school["budi"], image(1)).status_code == 404


def test_enrolment_reports_progress_and_the_status_endpoint_matches(client, db, auth, school):
    first = enroll(client, auth, school, school["ahmad"], image(1)).json()
    second = enroll(client, auth, school, school["ahmad"], image(2)).json()

    assert (first["jumlah_foto"], second["jumlah_foto"]) == (1, 2)
    assert second["model_version"] == "mock-v0"
    status = client.get(f"{API}/5A/students/{school['ahmad'].id}/face", headers=auth("rina@contoh.id"))
    assert status.json() == {"siswa_id": school["ahmad"].id, "jumlah_foto": 2, "maksimum": 3}


def test_only_embeddings_are_stored_never_the_photo(client, db, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))

    row = db.scalar(select(WajahSiswa))
    assert len(row.embedding) == 128
    assert row.didaftarkan_oleh == school["rina"].id
    assert not hasattr(row, "foto")


def test_the_same_face_cannot_be_registered_for_two_students(client, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))

    response = enroll(client, auth, school, school["siti"], image(1))

    assert response.status_code == 409
    assert response.json()["kode"] == "FaceAlreadyEnrolled"
    assert "Ahmad" not in response.text


def test_the_same_student_may_add_more_photos_up_to_the_limit(client, auth, school):
    for seed in (1, 2, 3):
        assert enroll(client, auth, school, school["ahmad"], image(seed)).status_code == 201

    response = enroll(client, auth, school, school["ahmad"], image(4))

    assert response.status_code == 409 and response.json()["kode"] == "FaceLimitReached"


def test_resetting_a_students_faces_makes_them_unrecognised_again(client, db, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))

    response = client.delete(f"{API}/5A/students/{school['ahmad'].id}/face", headers=auth("rina@contoh.id"))

    assert response.status_code == 204
    assert scan(client, auth, image(1)).json()["hasil"] == "tidak_dikenali"
    assert db.scalars(select(WajahSiswa)).all() == []


def test_only_the_homeroom_teacher_can_reset_faces(client, auth, school):
    enroll(client, auth, school, school["ahmad"], image(1))
    response = client.delete(f"{API}/5A/students/{school['ahmad'].id}/face", headers=auth("andi@contoh.id"))
    assert response.status_code == 403


def test_the_unique_constraint_blocks_concurrent_double_recording(db, school):
    from app.services.attendance_service import AlreadyPresent, Recorded, mark_present_by_face

    now = datetime(2026, 10, 8, 7, 41, tzinfo=JKT)
    kwargs = dict(siswa_id=school["ahmad"].id, guru_id=school["andi"].id, now=now, late_limit=None)

    first = mark_present_by_face(db, **kwargs)
    second = mark_present_by_face(db, **kwargs)

    assert isinstance(first, Recorded) and isinstance(second, AlreadyPresent)
    assert len(attendance_rows(db)) == 1
