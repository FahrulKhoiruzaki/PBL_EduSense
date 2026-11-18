from typing import Any


class AppError(Exception):
    """Galat yang dikirim ke klien dengan format {"message": ..., "errors": {...}}."""

    def __init__(
        self,
        status_code: int,
        message: str,
        *,
        code: str | None = None,
        errors: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.code = code
        self.errors = errors or {}

    def body(self) -> dict[str, Any]:
        body: dict[str, Any] = {"message": self.message}
        if self.code:
            body["kode"] = self.code
        if self.errors:
            body["errors"] = self.errors
        return body


def unauthorized(message: str = "Sesi Anda telah berakhir. Silakan masuk kembali.") -> AppError:
    return AppError(401, message)


def forbidden(message: str = "Anda tidak memiliki akses untuk tindakan ini.") -> AppError:
    return AppError(403, message)


def not_found(message: str = "Data tidak ditemukan.") -> AppError:
    return AppError(404, message)


def conflict(message: str, *, code: str | None = None) -> AppError:
    return AppError(409, message, code=code)
