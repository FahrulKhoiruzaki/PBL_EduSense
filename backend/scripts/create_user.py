"""Membuat akun pertama (misalnya admin) karena belum ada pendaftaran mandiri.

    python -m scripts.create_user --role admin --email admin@sekolah.id --nama "Admin Sekolah"

Password diminta lewat prompt (tidak muncul di riwayat shell). Untuk otomasi, gunakan
variabel lingkungan CREATE_USER_PASSWORD.
"""

import argparse
import getpass
import os
import sys

from sqlalchemy.exc import IntegrityError

from app.core.config import get_settings
from app.core.database import build_engine, build_session_factory
from app.models.base import UserRole
from app.services.auth_service import MIN_PASSWORD_LENGTH, create_user, find_user_by_email


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--role", required=True, choices=[r.value for r in UserRole])
    parser.add_argument("--email", required=True)
    parser.add_argument("--nama", required=True)
    parser.add_argument("--nip", help="Hanya untuk guru")
    parser.add_argument(
        "--permanent",
        action="store_true",
        help="Password tidak perlu diganti saat login pertama (default: wajib diganti)",
    )
    args = parser.parse_args()

    password = os.environ.get("CREATE_USER_PASSWORD")
    if not password:
        password = getpass.getpass("Password: ")
        if password != getpass.getpass("Ulangi password: "):
            print("Password tidak sama.", file=sys.stderr)
            return 1
    if len(password) < MIN_PASSWORD_LENGTH:
        print(f"Password minimal {MIN_PASSWORD_LENGTH} karakter.", file=sys.stderr)
        return 1

    engine = build_engine(get_settings().database_url)
    with build_session_factory(engine)() as db:
        if find_user_by_email(db, args.email):
            print("Email sudah dipakai.", file=sys.stderr)
            return 1
        try:
            user = create_user(
                db,
                role=UserRole(args.role),
                email=args.email,
                nama=args.nama,
                password=password,
                must_change_password=not args.permanent,
                nip=args.nip,
            )
        except IntegrityError as exc:
            print(f"Gagal membuat akun: {exc.orig}", file=sys.stderr)
            return 1
    print(f"Akun {args.role} dibuat: {user.email} (id {user.id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
