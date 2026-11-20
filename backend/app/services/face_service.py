import math
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import WajahSiswa


@dataclass(frozen=True)
class FaceMatch:
    siswa_id: int
    similarity: float


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        return -1.0
    dot = sum(x * y for x, y in zip(a, b))
    norm = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
    return dot / norm if norm else -1.0


def find_best_match(
    db: Session, embedding: list[float], *, model_version: str, threshold: float
) -> FaceMatch | None:
    """Siswa dengan kemiripan tertinggi, atau None bila tidak ada yang mencapai ambang."""
    rows = db.execute(
        select(WajahSiswa.siswa_id, WajahSiswa.embedding).where(
            WajahSiswa.model_version == model_version
        )
    ).all()

    best: FaceMatch | None = None
    for siswa_id, stored in rows:
        similarity = cosine_similarity(embedding, stored)
        if best is None or similarity > best.similarity:
            best = FaceMatch(siswa_id, similarity)
    return best if best is not None and best.similarity >= threshold else None
