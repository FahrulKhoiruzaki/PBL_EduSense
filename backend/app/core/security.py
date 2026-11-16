import secrets
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

_hasher = PasswordHasher()

# Dipakai agar login untuk email yang tidak ada sama lambatnya dengan email yang ada.
_DUMMY_HASH = _hasher.hash("tidak-pernah-dipakai")

ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


# Tanpa karakter yang mudah tertukar (0/O, 1/l/I) karena password sementara dibacakan atau diketik ulang.
_TEMP_ALPHABET = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def generate_temp_password(length: int = 10) -> str:
    return "".join(secrets.choice(_TEMP_ALPHABET) for _ in range(length))


def create_access_token(
    *, user_id: int, role: str, version: int, secret: str, minutes: int, now: datetime | None = None
) -> str:
    issued = now or datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "role": role,
        "ver": version,
        "iat": issued,
        "exp": issued + timedelta(minutes=minutes),
    }
    return jwt.encode(payload, secret, algorithm=ALGORITHM)


def decode_access_token(token: str, secret: str) -> dict:
    """Melempar jwt.PyJWTError bila token rusak atau kedaluwarsa."""
    return jwt.decode(
        token,
        secret,
        algorithms=[ALGORITHM],
        options={"require": ["sub", "exp", "ver"]},
    )
