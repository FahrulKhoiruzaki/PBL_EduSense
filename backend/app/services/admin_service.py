import re
import unicodedata
from datetime import time
from typing import Literal

from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.guru_access import get_class
from app.core.errors import AppError, conflict, not_found
from app.core.security import generate_temp_password, hash_password, verify_password
from app.models import (
    Admin,
    Guru,
    Kelas,
    MapelGuru,
    MataPelajaran,
    OrangTua,
    PengaturanSekolah,
    Siswa,
    User,
)
from app.models.base import LogTipe, UserRole
from app.schemas.admin import (
    AccountOut,
    CredentialsOut,
    GuruAdminOut,
    KelasAdminOut,
    PenugasanOut,
    SettingsOut,
    SiswaAdminOut,
)
from app.services import auth_service, grading_service, log_service, periods

AccountKind = Literal["guru", "siswa", "admin"]
EMAIL_TAKEN = "Email sudah dipakai akun lain."


def _email_taken() -> AppError:
    return AppError(409, EMAIL_TAKEN, errors={"email": EMAIL_TAKEN})


def _ensure_email_free(db: Session, email: str, *, except_user_id: int | None = None) -> None:
    existing = auth_service.find_user_by_email(db, email)
    if existing is not None and existing.id != except_user_id:
        raise _email_taken()


def _commit_unique_email(db: Session) -> None:
    """Dua permintaan bersamaan dengan email sama lolos pemeriksaan awal; indeks unik yang memutuskan."""
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _email_taken() from None


def _staff(db: Session, model: type[Guru] | type[Admin], account_id: int):
    row = db.execute(
        select(model, User).join(User, User.id == model.user_id).where(model.id == account_id)
    ).first()
    if row is None:
        raise not_found("Akun tidak ditemukan.")
    return row


def _siswa(db: Session, siswa_id: int) -> Siswa:
    siswa = db.get(Siswa, siswa_id)
    if siswa is None:
        raise not_found("Siswa tidak ditemukan.")
    return siswa


def _target_user(db: Session, kind: AccountKind, account_id: int) -> User:
    if kind == "guru":
        return _staff(db, Guru, account_id)[1]
    if kind == "admin":
        return _staff(db, Admin, account_id)[1]
    siswa = _siswa(db, account_id)
    return db.get(User, siswa.orang_tua.user_id)


def _not_self(actor: User, user: User, action: str) -> None:
    if user.id == actor.id:
        raise conflict(f"Anda tidak dapat {action} akun Anda sendiri.")


def _active_guru(db: Session, guru_id: int) -> Guru:
    guru, user = _staff(db, Guru, guru_id)
    if not user.is_active:
        raise AppError(
            422, "Guru ini sedang dinonaktifkan.", errors={"guru_id": "Guru ini sedang dinonaktifkan."}
        )
    return guru


# Daftar


def list_guru(db: Session) -> list[GuruAdminOut]:
    wali_ids = set(
        db.scalars(select(Kelas.wali_kelas_id).where(Kelas.wali_kelas_id.is_not(None)))
    )
    rows = db.execute(
        select(Guru, User).join(User, User.id == Guru.user_id).order_by(Guru.nama, Guru.id)
    ).all()
    return [
        GuruAdminOut(
            id=g.id,
            nama=g.nama,
            email=u.email,
            peran="wali" if g.id in wali_ids else "mapel",
            aktif=u.is_active,
            wajib_ganti_password=u.must_change_password,
        )
        for g, u in rows
    ]


def list_admins(db: Session) -> list[AccountOut]:
    rows = db.execute(
        select(Admin, User).join(User, User.id == Admin.user_id).order_by(Admin.nama, Admin.id)
    ).all()
    return [
        AccountOut(
            id=a.id, nama=a.nama, email=u.email, aktif=u.is_active,
            wajib_ganti_password=u.must_change_password,
        )
        for a, u in rows
    ]


def list_siswa(db: Session) -> list[SiswaAdminOut]:
    rows = db.execute(
        select(Siswa, Kelas.nama_kelas, OrangTua.nama_lengkap, User)
        .join(Kelas, Kelas.id == Siswa.kelas_id)
        .join(OrangTua, OrangTua.id == Siswa.orang_tua_id)
        .join(User, User.id == OrangTua.user_id)
        .order_by(Kelas.nama_kelas, Siswa.nama, Siswa.id)
    ).all()
    return [
        SiswaAdminOut(
            id=s.id, nama=s.nama, email=u.email, kelas=kelas, nama_orang_tua=parent,
            aktif=u.is_active, wajib_ganti_password=u.must_change_password,
        )
        for s, kelas, parent, u in rows
    ]


def list_classes(db: Session) -> list[KelasAdminOut]:
    assignments: dict[int, list[PenugasanOut]] = {}
    for kelas_id, guru_id, mapel_id, mapel in db.execute(
        select(MapelGuru.kelas_id, MapelGuru.guru_id, MapelGuru.mapel_id, MataPelajaran.nama)
        .outerjoin(MataPelajaran, MataPelajaran.id == MapelGuru.mapel_id)
        .order_by(MapelGuru.id)
    ):
        assignments.setdefault(kelas_id, []).append(
            PenugasanOut(guru_id=guru_id, mapel_id=mapel_id, mapel=mapel)
        )
    result = []
    for k in db.scalars(select(Kelas).order_by(Kelas.nama_kelas)):
        rows = assignments.get(k.id, [])
        result.append(
            KelasAdminOut(
                kode=k.nama_kelas,
                wali_id=k.wali_kelas_id,
                mapel_ids=list(dict.fromkeys(a.guru_id for a in rows)),
                penugasan=rows,
            )
        )
    return result


# Akun


def _parent_email(db: Session, student_name: str, domain: str) -> str:
    ascii_name = unicodedata.normalize("NFKD", student_name).encode("ascii", "ignore").decode()
    slug = re.sub(r"[^a-z0-9]+", ".", ascii_name.lower()).strip(".") or "siswa"
    for number in range(1, 1000):
        email = f"ortu.{slug}{'' if number == 1 else number}@{domain}"
        if auth_service.find_user_by_email(db, email) is None:
            return email
    raise conflict("Tidak dapat membuat email orang tua otomatis. Coba nama siswa yang berbeda.")


def create_staff(
    db: Session, actor: User, role: UserRole, nama: str, email: str
) -> CredentialsOut:
    _ensure_email_free(db, email)
    password = generate_temp_password()
    user = auth_service.create_user(
        db, role=role, email=email, nama=nama, password=password, commit=False
    )
    label = "guru" if role is UserRole.GURU else "admin"
    log_service.record(
        db, actor, LogTipe.AKUN, f"{log_service.actor_name(actor)} membuat akun {label} {nama}."
    )
    _commit_unique_email(db)
    profile = user.guru_profile if role is UserRole.GURU else user.admin_profile
    return CredentialsOut(id=profile.id, email=user.email, password_sementara=password)


def create_siswa(
    db: Session, actor: User, nama: str, kelas_code: str, parent_name: str, email_domain: str
) -> CredentialsOut:
    kelas = get_class(db, kelas_code)
    email = _parent_email(db, nama, email_domain)
    password = generate_temp_password()
    parent = auth_service.create_user(
        db, role=UserRole.ORTU, email=email, nama=parent_name, password=password, commit=False
    )
    siswa = Siswa(nama=nama, kelas_id=kelas.id, orang_tua_id=parent.ortu_profile.id)
    db.add(siswa)
    db.flush()
    log_service.record(
        db,
        actor,
        LogTipe.SISWA,
        f"{log_service.actor_name(actor)} menambahkan siswa {nama} ke kelas {kelas.nama_kelas}.",
    )
    _commit_unique_email(db)
    return CredentialsOut(id=siswa.id, email=email, password_sementara=password)


def update_staff(
    db: Session, actor: User, model: type[Guru] | type[Admin], account_id: int, nama: str, email: str
) -> None:
    profile, user = _staff(db, model, account_id)
    _ensure_email_free(db, email, except_user_id=user.id)
    profile.nama = nama
    user.email = email
    log_service.record(
        db, actor, LogTipe.AKUN, f"{log_service.actor_name(actor)} memperbarui akun {nama}."
    )
    _commit_unique_email(db)


def update_siswa(
    db: Session, actor: User, siswa_id: int, nama: str, kelas_code: str, parent_name: str
) -> None:
    siswa = _siswa(db, siswa_id)
    kelas = get_class(db, kelas_code)
    moved = siswa.kelas_id != kelas.id
    siswa.nama = nama
    siswa.kelas_id = kelas.id
    siswa.orang_tua.nama_lengkap = parent_name
    if moved:
        _refresh_active_classification(db, [siswa.id])
    log_service.record(
        db, actor, LogTipe.SISWA, f"{log_service.actor_name(actor)} memperbarui data siswa {nama}."
    )
    db.commit()


def reset_password(db: Session, actor: User, kind: AccountKind, account_id: int) -> CredentialsOut:
    user = _target_user(db, kind, account_id)
    _not_self(actor, user, "mereset password")
    password = generate_temp_password()
    user.password_hash = hash_password(password)
    user.must_change_password = True
    user.token_version += 1
    log_service.record(
        db, actor, LogTipe.AKUN, f"{log_service.actor_name(actor)} mereset password {user.email}."
    )
    db.commit()
    return CredentialsOut(id=account_id, email=user.email, password_sementara=password)


def set_active(db: Session, actor: User, kind: AccountKind, account_id: int, active: bool) -> None:
    user = _target_user(db, kind, account_id)
    if not active:
        _not_self(actor, user, "menonaktifkan")
    user.is_active = active
    action = "mengaktifkan" if active else "menonaktifkan"
    log_service.record(
        db, actor, LogTipe.AKUN, f"{log_service.actor_name(actor)} {action} akun {user.email}."
    )
    db.commit()


def delete_account(db: Session, actor: User, kind: AccountKind, account_id: int) -> None:
    # Hapus lewat SQL agar ON DELETE CASCADE/SET NULL di database yang bekerja, bukan cascade ORM.
    if kind == "siswa":
        siswa = _siswa(db, account_id)
        name, parent_id, parent_user_id = siswa.nama, siswa.orang_tua_id, siswa.orang_tua.user_id
        db.execute(delete(Siswa).where(Siswa.id == siswa.id))
        siblings = db.scalar(
            select(func.count()).select_from(Siswa).where(Siswa.orang_tua_id == parent_id)
        )
        if not siblings:
            db.execute(delete(User).where(User.id == parent_user_id))
        log_service.record(
            db, actor, LogTipe.SISWA, f"{log_service.actor_name(actor)} menghapus siswa {name}."
        )
    else:
        model = Guru if kind == "guru" else Admin
        profile, user = _staff(db, model, account_id)
        _not_self(actor, user, "menghapus")
        name = profile.nama
        db.execute(delete(User).where(User.id == user.id))
        log_service.record(
            db, actor, LogTipe.AKUN, f"{log_service.actor_name(actor)} menghapus akun {kind} {name}."
        )
    db.commit()


def change_own_password(db: Session, user: User, old_password: str, new_password: str) -> None:
    if not verify_password(old_password, user.password_hash):
        raise AppError(
            422,
            "Data yang dikirim tidak valid.",
            errors={"old_password": "Password lama tidak sesuai."},
        )
    if old_password == new_password:
        raise AppError(
            422,
            "Data yang dikirim tidak valid.",
            errors={"new_password": "Password baru harus berbeda dari password lama."},
        )
    auth_service.change_password(db, user, new_password)
    log_service.record(
        db, user, LogTipe.AKUN, f"{log_service.actor_name(user)} mengganti password akunnya."
    )
    db.commit()


# Kelas


def create_class(db: Session, actor: User, code: str) -> None:
    if db.scalar(select(Kelas.id).where(Kelas.nama_kelas == code)) is not None:
        raise AppError(409, f"Kelas {code} sudah ada.", errors={"kode": "Kelas sudah ada."})
    db.add(Kelas(nama_kelas=code))
    log_service.record(db, actor, LogTipe.KELAS, f"{log_service.actor_name(actor)} membuat kelas {code}.")
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise AppError(409, f"Kelas {code} sudah ada.", errors={"kode": "Kelas sudah ada."}) from None


def delete_class(db: Session, actor: User, code: str) -> None:
    kelas = get_class(db, code)
    students = db.scalar(select(func.count()).select_from(Siswa).where(Siswa.kelas_id == kelas.id))
    if students:
        raise conflict(
            f"Kelas {kelas.nama_kelas} masih memiliki {students} siswa. Pindahkan siswa terlebih dahulu."
        )
    name = kelas.nama_kelas
    db.execute(delete(Kelas).where(Kelas.id == kelas.id))
    log_service.record(db, actor, LogTipe.KELAS, f"{log_service.actor_name(actor)} menghapus kelas {name}.")
    db.commit()


def set_wali(db: Session, actor: User, code: str, guru_id: int | None) -> None:
    kelas = get_class(db, code)
    who = log_service.actor_name(actor)
    if guru_id is None:
        kelas.wali_kelas_id = None
        message = f"{who} mengosongkan wali kelas {kelas.nama_kelas}."
    else:
        guru = _active_guru(db, guru_id)
        if kelas.wali_kelas_id == guru.id:
            return
        # Satu guru hanya boleh menjadi wali satu kelas; kelas lamanya menjadi tanpa wali.
        db.execute(
            update(Kelas)
            .where(Kelas.wali_kelas_id == guru.id, Kelas.id != kelas.id)
            .values(wali_kelas_id=None)
        )
        kelas.wali_kelas_id = guru.id
        message = f"{who} menetapkan {guru.nama} sebagai wali kelas {kelas.nama_kelas}."
    log_service.record(db, actor, LogTipe.KELAS, message)
    db.commit()


def add_mapel(db: Session, actor: User, code: str, guru_id: int, mapel_id: int | None = None) -> None:
    kelas = get_class(db, code)
    guru = _active_guru(db, guru_id)
    mapel = None
    if mapel_id is not None:
        mapel = db.get(MataPelajaran, mapel_id)
        if mapel is None:
            raise AppError(422, "Mata pelajaran tidak ditemukan.", errors={"mapel_id": "Pilih mata pelajaran."})
        if not mapel.aktif:
            raise AppError(422, "Mata pelajaran ini sedang nonaktif.",
                           errors={"mapel_id": "Mata pelajaran ini sedang nonaktif."})
        if int(kelas.nama_kelas[0]) not in mapel.tingkat:
            raise AppError(422, f"{mapel.nama} tidak diajarkan di kelas {kelas.nama_kelas[0]}.",
                           errors={"mapel_id": "Mata pelajaran ini tidak berlaku untuk jenjang kelas ini."})
    same = select(MapelGuru.id).where(MapelGuru.guru_id == guru.id, MapelGuru.kelas_id == kelas.id)
    same = same.where(MapelGuru.mapel_id == mapel_id) if mapel_id is not None else same.where(
        MapelGuru.mapel_id.is_(None)
    )
    if db.scalar(same) is not None:
        raise conflict(
            f"Guru sudah ditugaskan mengajar {mapel.nama} di kelas ini." if mapel
            else "Guru sudah ditugaskan di kelas ini."
        )
    db.add(MapelGuru(guru_id=guru.id, kelas_id=kelas.id, mapel_id=mapel_id))
    subject = f" {mapel.nama}" if mapel else ""
    log_service.record(
        db,
        actor,
        LogTipe.KELAS,
        f"{log_service.actor_name(actor)} menugaskan {guru.nama} sebagai guru mapel{subject} "
        f"kelas {kelas.nama_kelas}.",
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise conflict("Guru sudah ditugaskan untuk mata pelajaran ini di kelas ini.") from None


def remove_mapel(
    db: Session, actor: User, code: str, guru_id: int, mapel_id: int | None = None
) -> None:
    """Tanpa `mapel_id`: lepas semua penugasan guru di kelas itu (perilaku lama)."""
    kelas = get_class(db, code)
    stmt = delete(MapelGuru).where(MapelGuru.guru_id == guru_id, MapelGuru.kelas_id == kelas.id)
    if mapel_id is not None:
        stmt = stmt.where(MapelGuru.mapel_id == mapel_id)
    result = db.execute(stmt)
    if result.rowcount == 0:
        raise not_found("Guru tidak ditugaskan di kelas ini.")
    nama = db.scalar(select(Guru.nama).where(Guru.id == guru_id)) or "Guru"
    subject = ""
    if mapel_id is not None:
        subject = f" ({db.scalar(select(MataPelajaran.nama).where(MataPelajaran.id == mapel_id))})"
    log_service.record(
        db,
        actor,
        LogTipe.KELAS,
        f"{log_service.actor_name(actor)} melepas {nama}{subject} dari kelas {kelas.nama_kelas}.",
    )
    db.commit()


def move_students(db: Session, actor: User, student_ids: list[int], target_code: str) -> None:
    target = get_class(db, target_code)
    ids = list(dict.fromkeys(student_ids))
    students = list(db.scalars(select(Siswa).where(Siswa.id.in_(ids))))
    if len(students) != len(ids):
        raise not_found("Sebagian siswa tidak ditemukan.")

    to_move = [s for s in students if s.kelas_id != target.id]
    sources = sorted(
        set(db.scalars(select(Kelas.nama_kelas).where(Kelas.id.in_({s.kelas_id for s in to_move}))))
    )
    for siswa in to_move:
        siswa.kelas_id = target.id
    if to_move:
        _refresh_active_classification(db, [s.id for s in to_move])
        log_service.record(
            db,
            actor,
            LogTipe.SISWA,
            f"{log_service.actor_name(actor)} memindahkan {len(to_move)} siswa dari kelas "
            f"{', '.join(sources)} ke kelas {target.nama_kelas}.",
        )
    db.commit()


def _refresh_active_classification(db: Session, student_ids: list[int]) -> None:
    """Hasil klasifikasi periode aktif menyimpan kelas siswa; perbarui setelah siswa pindah kelas."""
    db.flush()
    active = periods.active_period(db)
    if active is not None:
        grading_service.recompute(db, active, student_ids)


# Pengaturan


def get_settings(db: Session) -> SettingsOut:
    row = db.get(PengaturanSekolah, True)
    active = periods.active_period(db)
    return SettingsOut(
        tahun_ajaran=active.tahun_ajaran if active else row.tahun_ajaran,
        periode_aktif=active.label if active else None,
        batas_jam_terlambat=row.batas_jam_terlambat.strftime("%H:%M") if row.batas_jam_terlambat else None,
    )


def save_settings(db: Session, actor: User, tahun_ajaran: str | None, late_limit: str | None) -> None:
    row = db.get(PengaturanSekolah, True)
    active = periods.active_period(db)
    if tahun_ajaran is not None and active is not None and tahun_ajaran != active.tahun_ajaran:
        message = (
            f"Tahun ajaran mengikuti periode aktif ({active.label}). Ubah lewat menu Periode Akademik."
        )
        raise AppError(422, message, errors={"tahun_ajaran": message})
    if tahun_ajaran is not None and active is None:
        row.tahun_ajaran = tahun_ajaran
    row.batas_jam_terlambat = time.fromisoformat(late_limit) if late_limit else None
    log_service.record(
        db,
        actor,
        LogTipe.SISTEM,
        f"{log_service.actor_name(actor)} mengubah pengaturan sekolah: tahun ajaran {row.tahun_ajaran}, "
        f"batas jam terlambat {late_limit or 'tidak ditentukan'}.",
    )
    db.commit()
