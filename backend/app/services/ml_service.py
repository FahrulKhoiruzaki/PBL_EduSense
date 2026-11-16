"""Layanan machine learning untuk pengenalan wajah.

SAAT INI hanya placeholder: `MockFaceEmbedder` menghasilkan vektor deterministik dari isi
file gambar (bukan dari wajah). Foto yang sama persis akan "cocok", foto lain dari orang yang
sama TIDAK. Ini cukup untuk menguji alur pendaftaran, pemindaian, dan pencatatan absensi,
tetapi tidak boleh dipakai untuk absensi sungguhan.

Titik sambung untuk model sungguhan:
  * `FaceEmbedder.embed` -> ganti dengan FaceNet (deteksi wajah + embedding 128/512-d).
    Lemparkan `NoFaceDetected` bila tidak ada wajah di gambar.
  * `model_version` harus berubah setiap model diganti. Embedding hanya dibandingkan dengan
    embedding berversi sama, sehingga model baru butuh pendaftaran ulang wajah.
  * Klasifikasi tambahan (misalnya scikit-learn) ditambahkan sebagai layanan terpisah di sini.
"""

import hashlib
import math
import random
from typing import Protocol

EMBEDDING_DIM = 128


class FaceError(Exception):
    pass


class InvalidImage(FaceError):
    """Berkas bukan gambar JPEG, PNG, atau WebP yang valid."""


class NoFaceDetected(FaceError):
    """Tidak ada wajah yang dapat dikenali pada gambar."""


class FaceEmbedder(Protocol):
    model_version: str

    def embed(self, image: bytes) -> list[float]: ...


def detect_image_type(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


class MockFaceEmbedder:
    model_version = "mock-v0"

    def embed(self, image: bytes) -> list[float]:
        if detect_image_type(image) is None or len(image) < 16:
            raise InvalidImage("Berkas bukan gambar yang valid.")

        seed = int.from_bytes(hashlib.sha256(image).digest(), "big")
        rng = random.Random(seed)
        vector = [rng.gauss(0.0, 1.0) for _ in range(EMBEDDING_DIM)]
        norm = math.sqrt(sum(v * v for v in vector))
        return [v / norm for v in vector]
