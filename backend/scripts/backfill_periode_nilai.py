"""Backfill `nilai.periode_id` untuk nilai lama (dibuat sebelum ada periode akademik).

    python -m scripts.backfill_periode_nilai                      # DRY-RUN (default): hanya laporan
    python -m scripts.backfill_periode_nilai --report hasil.csv   # dry-run + laporan per baris (CSV)
    python -m scripts.backfill_periode_nilai --apply              # terapkan, minta konfirmasi "ya"
    python -m scripts.backfill_periode_nilai --apply --yes        # terapkan tanpa prompt (otomasi)

Aturan pemetaan (tidak ada tebakan):
  * Hanya nilai dengan `periode_id` kosong dan TANPA komponen yang diproses (nilai berkomponen
    selalu mendapat periode dari komponennya lewat trigger database).
  * Nilai dipetakan hanya bila tanggalnya berada di dalam rentang TEPAT SATU periode akademik
    (tanggal_mulai <= tanggal <= tanggal_selesai). Rentang periode tidak boleh tumpang tindih
    (constraint database), jadi kecocokan ini pasti.
  * Tanggal yang tidak tercakup periode mana pun dilaporkan "tidak dapat dipetakan" dan dibiarkan
    NULL. Buat periode yang sesuai di menu admin, lalu jalankan ulang script ini.
  * `mapel_id` nilai lama TIDAK diisi: data lama tidak menyimpan mata pelajaran, sehingga tidak
    dapat ditentukan tanpa menebak.
  * Baris yang datanya tidak konsisten dilaporkan "bermasalah" dan tidak pernah diubah.

Mode --apply: satu transaksi; semua perubahan dibatalkan bila ada yang gagal. Kolom `updated_at`
nilai dipertahankan (backfill bukan perubahan nilai oleh guru, jadi tidak boleh muncul sebagai
"Nilai diperbarui" di aktivitas guru). Setelah pemetaan, klasifikasi periode AKTIF yang terdampak
dihitung ulang. Periode lama tidak dihitung ulang secara default karena hasil klasifikasi menyimpan
kelas siswa saat dihitung, dan kelas siswa pada periode lama tidak tercatat di data lama; gunakan
--hitung-ulang-periode-lama bila kelas siswa tidak berubah sejak periode tersebut.
"""

import argparse
import csv
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from sqlalchemy import select, text, update
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.database import build_engine, build_session_factory
from app.models import KomponenPenilaian, Nilai, PeriodeAkademik, Siswa
from app.services import grading_service

MAPPED = "dipetakan"
UNMAPPED = "tidak_dapat_dipetakan"
PROBLEM = "bermasalah"


@dataclass
class Row:
    nilai_id: int
    siswa_id: int
    siswa: str
    tanggal: date
    kategori: str | None
    status: str
    periode_id: int | None
    periode: str | None
    keterangan: str


@dataclass
class Plan:
    rows: list[Row]

    def by_status(self, status: str) -> list[Row]:
        return [r for r in self.rows if r.status == status]


def _covering(periods: list[PeriodeAkademik], day: date) -> list[PeriodeAkademik]:
    return [p for p in periods if p.tanggal_mulai <= day <= p.tanggal_selesai]


def build_plan(db: Session) -> Plan:
    """Analisis read-only: tidak mengubah apa pun."""
    periods = list(db.scalars(select(PeriodeAkademik).order_by(PeriodeAkademik.tanggal_mulai)))
    by_id = {p.id: p for p in periods}
    rows: list[Row] = []

    # 1. Kandidat backfill: periode kosong.
    pending = db.execute(
        select(Nilai.id, Nilai.siswa_id, Siswa.nama, Nilai.tanggal, Nilai.kategori, Nilai.komponen_id)
        .join(Siswa, Siswa.id == Nilai.siswa_id)
        .where(Nilai.periode_id.is_(None))
        .order_by(Nilai.tanggal, Nilai.id)
    ).all()
    for nilai_id, siswa_id, nama, tanggal, kategori, komponen_id in pending:
        label = kategori.value if kategori else None
        if komponen_id is not None:
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, PROBLEM, None, None,
                            "Punya komponen tetapi periode kosong; periksa trigger nilai."))
            continue
        if kategori is None:
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, PROBLEM, None, None,
                            "Tidak punya komponen maupun kategori."))
            continue
        matches = _covering(periods, tanggal)
        if len(matches) == 1:
            p = matches[0]
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, MAPPED, p.id, p.label,
                            f"Tanggal di dalam {p.tanggal_mulai} s.d. {p.tanggal_selesai}."))
        elif not matches:
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, UNMAPPED, None, None,
                            "Tanggal tidak tercakup periode akademik mana pun."))
        else:
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, PROBLEM, None, None,
                            "Tanggal tercakup lebih dari satu periode (rentang tumpang tindih)."))

    # 2. Pemeriksaan konsistensi nilai yang sudah punya periode (hanya dilaporkan).
    assigned = db.execute(
        select(Nilai.id, Nilai.siswa_id, Siswa.nama, Nilai.tanggal, Nilai.kategori,
               Nilai.periode_id, KomponenPenilaian.periode_id)
        .join(Siswa, Siswa.id == Nilai.siswa_id)
        .outerjoin(KomponenPenilaian, KomponenPenilaian.id == Nilai.komponen_id)
        .where(Nilai.periode_id.is_not(None))
    ).all()
    for nilai_id, siswa_id, nama, tanggal, kategori, periode_id, komponen_periode in assigned:
        p = by_id.get(periode_id)
        label = kategori.value if kategori else None
        problem = None
        if p is None:
            problem = "Periode yang dirujuk tidak ditemukan."
        elif not p.contains(tanggal):
            problem = f"Tanggal di luar rentang {p.label}."
        elif komponen_periode is not None and komponen_periode != periode_id:
            problem = "Periode nilai berbeda dengan periode komponennya."
        if problem:
            rows.append(Row(nilai_id, siswa_id, nama, tanggal, label, PROBLEM, periode_id,
                            p.label if p else None, problem))
    return Plan(rows)


def print_summary(plan: Plan, out=None) -> None:
    out = out or sys.stdout
    mapped, unmapped, problems = (plan.by_status(s) for s in (MAPPED, UNMAPPED, PROBLEM))
    print("Ringkasan backfill periode nilai", file=out)
    print(f"  Dapat dipetakan       : {len(mapped)}", file=out)
    for label, count in sorted(Counter(r.periode for r in mapped).items()):
        print(f"    - {label}: {count}", file=out)
    print(f"  Tidak dapat dipetakan : {len(unmapped)}", file=out)
    months = Counter(r.tanggal.strftime("%Y-%m") for r in unmapped)
    for month, count in sorted(months.items()):
        print(f"    - bulan {month}: {count} nilai (belum ada periode yang mencakup)", file=out)
    print(f"  Bermasalah            : {len(problems)}", file=out)
    for r in problems[:20]:
        print(f"    - nilai #{r.nilai_id} ({r.siswa}, {r.tanggal}): {r.keterangan}", file=out)
    if len(problems) > 20:
        print(f"    ... dan {len(problems) - 20} lainnya (lihat --report)", file=out)


def write_report(plan: Plan, path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["nilai_id", "siswa_id", "siswa", "tanggal", "kategori", "status",
                         "periode_id", "periode", "keterangan"])
        for r in plan.rows:
            writer.writerow([r.nilai_id, r.siswa_id, r.siswa, r.tanggal.isoformat(), r.kategori or "",
                             r.status, r.periode_id or "", r.periode or "", r.keterangan])


def apply_plan(db: Session, plan: Plan, *, recompute_old: bool = False) -> dict[int, int]:
    """Menerapkan baris "dipetakan". Tidak melakukan commit; pemanggil yang memutuskan.

    Mengembalikan jumlah nilai yang diperbarui per periode.
    """
    targets: dict[int, list[int]] = defaultdict(list)
    for r in plan.by_status(MAPPED):
        targets[r.periode_id].append(r.nilai_id)
    if not targets:
        return {}

    # Pertahankan updated_at: nonaktifkan HANYA trigger updated_at nilai, di dalam transaksi ini.
    # Trigger validasi rentang periode (trg_nilai_sinkron_periode) tetap aktif.
    db.execute(text("ALTER TABLE nilai DISABLE TRIGGER trg_nilai_updated_at"))
    updated: dict[int, int] = {}
    affected: list[tuple[int, int]] = []
    for periode_id, ids in targets.items():
        result = db.execute(
            update(Nilai)
            .where(Nilai.id.in_(ids), Nilai.periode_id.is_(None), Nilai.komponen_id.is_(None))
            .values(periode_id=periode_id)
            .returning(Nilai.siswa_id)
        )
        siswa_ids = list(result.scalars())
        if len(siswa_ids) != len(ids):
            raise RuntimeError(
                f"Data berubah selama backfill (periode {periode_id}: {len(siswa_ids)} dari "
                f"{len(ids)} baris). Semua perubahan dibatalkan; jalankan ulang."
            )
        updated[periode_id] = len(ids)
        affected += [(periode_id, s) for s in siswa_ids]
    db.execute(text("ALTER TABLE nilai ENABLE TRIGGER trg_nilai_updated_at"))

    active = {p.id for p in db.scalars(select(PeriodeAkademik).where(PeriodeAkademik.aktif))}
    grading_service.recompute_for_grades(
        db, [(p, s) for p, s in affected if recompute_old or p in active]
    )
    return updated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Backfill periode akademik untuk nilai lama.")
    parser.add_argument("--apply", action="store_true", help="Terapkan perubahan (default: dry-run).")
    parser.add_argument("--yes", action="store_true", help="Lewati prompt konfirmasi (dengan --apply).")
    parser.add_argument("--report", type=Path, help="Tulis laporan per baris ke file CSV.")
    parser.add_argument("--hitung-ulang-periode-lama", action="store_true",
                        help="Hitung ulang klasifikasi periode nonaktif yang terdampak.")
    args = parser.parse_args(argv)

    engine = build_engine(get_settings().database_url)
    with build_session_factory(engine)() as db:
        if db.scalar(text("SELECT to_regclass('public.periode_akademik')")) is None:
            print("Tabel akademik belum ada. Jalankan dulu: python -m scripts.init_db", file=sys.stderr)
            return 1
        plan = build_plan(db)
        print_summary(plan)
        if args.report:
            write_report(plan, args.report)
            print(f"Laporan per baris ditulis ke {args.report}")

        mapped = plan.by_status(MAPPED)
        if not args.apply:
            db.rollback()
            print("\nDRY-RUN: tidak ada data yang diubah. Tambahkan --apply untuk menerapkan.")
            return 0
        if not mapped:
            print("\nTidak ada nilai yang dapat dipetakan. Tidak ada perubahan.")
            return 0
        if not args.yes:
            answer = input(f"\nTerapkan periode ke {len(mapped)} nilai? Ketik 'ya' untuk lanjut: ")
            if answer.strip().lower() != "ya":
                db.rollback()
                print("Dibatalkan. Tidak ada data yang diubah.")
                return 1
        try:
            updated = apply_plan(db, plan, recompute_old=args.hitung_ulang_periode_lama)
            db.commit()
        except Exception as exc:
            db.rollback()
            print(f"Gagal, semua perubahan dibatalkan: {exc}", file=sys.stderr)
            return 1
        print(f"Selesai: {sum(updated.values())} nilai diberi periode.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
