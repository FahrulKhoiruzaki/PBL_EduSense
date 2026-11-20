from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import AppError, unauthorized
from app.core.security import hash_password, needs_rehash, verify_password
from app.models import Admin, Guru, Kelas, MapelGuru, OrangTua, PengaturanSekolah, User
from app.models.base import UserRole

MIN_PASSWORD_LENGTH = 8
INVALID_CREDENTIALS = "Email atau password tidak sesuai."


def normalize_email(email: str) -> str:
    return email.strip().lower()


def find_user_by_email(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(func.lower(User.email) == normalize_email(email)))


def authenticate(db: Session, email: str, password: str) -> User:
    user = find_user_by_email(db, email)
    # Selalu verifikasi (juga untuk email yang tidak ada) agar waktu respons tidak membocorkan akun.
    valid = verify_password(password, user.password_hash if user else None)
    if user is None or not valid:
        raise unauthorized(INVALID_CREDENTIALS)
    if not user.is_active:
        raise AppError(403, "Akun Anda dinonaktifkan. Hubungi admin sekolah.")

    user.last_login_at = datetime.now(timezone.utc)
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)
    db.commit()
    return user


def display_name(user: User) -> str:
    profile = user.admin_profile or user.guru_profile or user.ortu_profile
    if profile is None:
        return user.email
    return getattr(profile, "nama", None) or getattr(profile, "nama_lengkap", user.email)


def guru_assignments(db: Session, guru: Guru) -> tuple[list[str], list[str]]:
    wali = db.scalars(
        select(Kelas.nama_kelas).where(Kelas.wali_kelas_id == guru.id).order_by(Kelas.nama_kelas)
    ).all()
    mapel = db.scalars(
        select(Kelas.nama_kelas)
        .join(MapelGuru, MapelGuru.kelas_id == Kelas.id)
        .where(MapelGuru.guru_id == guru.id)
        .distinct()  # satu kelas bisa memiliki beberapa mapel untuk guru yang sama
        .order_by(Kelas.nama_kelas)
    ).all()
    return list(wali), list(mapel)


def late_limit_text(db: Session) -> str | None:
    limit = db.scalar(select(PengaturanSekolah.batas_jam_terlambat))
    return limit.strftime("%H:%M") if limit else None


def change_password(db: Session, user: User, new_password: str) -> None:
    if len(new_password) < MIN_PASSWORD_LENGTH:
        raise AppError(
            422,
            "Data yang dikirim tidak valid.",
            errors={"new_password": f"Minimal {MIN_PASSWORD_LENGTH} karakter."},
        )
    user.password_hash = hash_password(new_password)
    user.must_change_password = False
    db.commit()


def revoke_tokens(db: Session, user: User) -> None:
    user.token_version += 1
    db.commit()


def create_user(
    db: Session,
    *,
    role: UserRole,
    email: str,
    nama: str,
    password: str,
    must_change_password: bool = True,
    nip: str | None = None,
    no_hp: str | None = None,
    commit: bool = True,
) -> User:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError(f"Password minimal {MIN_PASSWORD_LENGTH} karakter.")

    user = User(
        email=normalize_email(email),
        password_hash=hash_password(password),
        role=role,
        must_change_password=must_change_password,
    )
    if role is UserRole.ADMIN:
        user.admin_profile = Admin(nama=nama)
    elif role is UserRole.GURU:
        user.guru_profile = Guru(nama=nama, nip=nip)
    else:
        user.ortu_profile = OrangTua(nama_lengkap=nama, no_hp=no_hp)
    db.add(user)
    if commit:
        db.commit()
    else:
        db.flush()
    return user
