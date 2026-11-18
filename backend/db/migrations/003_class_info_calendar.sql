-- Informasi per kelas (1-6) dan kalender akademik terstruktur. Jalankan SETELAH 001 dan 002.
-- Idempoten: aman dijalankan ulang.

BEGIN;

CREATE TABLE IF NOT EXISTS informasi_kelas (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tingkat    smallint    NOT NULL CHECK (tingkat BETWEEN 1 AND 6),
  jenis      text        NOT NULL CHECK (jenis IN ('Pembelajaran', 'Kegiatan')),
  judul      text        NOT NULL CHECK (btrim(judul) <> ''),
  deskripsi  text        NOT NULL DEFAULT '',
  urutan     int         NOT NULL DEFAULT 0,
  tampil     boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS informasi_kelas_tingkat_idx ON informasi_kelas (tingkat, jenis, urutan);

CREATE TABLE IF NOT EXISTS kalender_akademik (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  judul           text        NOT NULL CHECK (btrim(judul) <> ''),
  deskripsi       text        NOT NULL DEFAULT '',
  kategori        text        NOT NULL CHECK (kategori IN ('Kegiatan', 'Libur', 'Ujian', 'Rapat')),
  tanggal_mulai   date        NOT NULL,
  tanggal_selesai date,
  tampil          boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (tanggal_selesai IS NULL OR tanggal_selesai >= tanggal_mulai)
);
CREATE INDEX IF NOT EXISTS kalender_akademik_tanggal_idx ON kalender_akademik (tanggal_mulai);

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['informasi_kelas', 'kalender_akademik'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_' || t || '_updated_at') THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
        'trg_' || t || '_updated_at', t
      );
    END IF;
  END LOOP;
END
$$;

-- Teks bebas "kelas-1".."kelas-6" digantikan tabel di atas: isi yang sudah ada dipindahkan
-- menjadi satu entri Pembelajaran per kelas agar tidak hilang, lalu barisnya dihapus.
INSERT INTO informasi_kelas (tingkat, jenis, judul, deskripsi)
SELECT substring(kunci FROM 7)::smallint, 'Pembelajaran', 'Informasi Kelas ' || substring(kunci FROM 7), isi
FROM halaman_situs
WHERE kunci ~ '^kelas-[1-6]$' AND btrim(isi) <> '';

DELETE FROM halaman_situs WHERE kunci ~ '^kelas-[1-6]$';

COMMIT;
