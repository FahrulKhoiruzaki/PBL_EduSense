"""Penyimpanan gambar konten website. Hanya JPEG/PNG/WebP; tipe ditentukan dari isi berkas."""

import re
import uuid
from pathlib import Path

MEDIA_URL_PREFIX = "/media"

_SIGNATURES = (
    (b"\xff\xd8\xff", "jpg"),
    (b"\x89PNG\r\n\x1a\n", "png"),
)


def detect_extension(data: bytes) -> str | None:
    for signature, extension in _SIGNATURES:
        if data.startswith(signature):
            return extension
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def save_media(media_dir: Path, data: bytes) -> str | None:
    """Menyimpan gambar dengan nama acak (nama dari klien tidak dipakai); None bila bukan gambar."""
    extension = detect_extension(data)
    if extension is None:
        return None
    name = f"{uuid.uuid4().hex}.{extension}"
    media_dir.mkdir(parents=True, exist_ok=True)
    (media_dir / name).write_bytes(data)
    return f"{MEDIA_URL_PREFIX}/{name}"


_OWN_FILE = re.compile(r"^" + re.escape(MEDIA_URL_PREFIX) + r"/([0-9a-f]{32}\.(?:jpg|png|webp))$")


def delete_media(media_dir: Path, url: str | None) -> None:
    """Menghapus berkas unggahan sendiri; tautan luar atau nama tak dikenal diabaikan (tidak ada path traversal)."""
    match = _OWN_FILE.match(url or "")
    if match:
        (media_dir / match.group(1)).unlink(missing_ok=True)
