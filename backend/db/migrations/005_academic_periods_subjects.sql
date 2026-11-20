-- Periode akademik terpusat, mata pelajaran (umum + muatan lokal), komponen penilaian, dan
-- klasifikasi per periode. Jalankan SETELAH 004. Idempoten: aman dijalankan ulang.
--
-- Ringkasan desain (detail di revisi-output/REVISION_REPORT.md):
--   * periode_akademik: satu baris = satu semester dalam satu tahun ajaran. Rentang tanggal antar
--     periode tidak boleh tumpang tindih dan paling banyak satu periode aktif.
--   * Absensi TIDAK diberi kolom periode: tanggal absensi sudah menentukan periodenya lewat rentang
--     tanggal periode, sehingga tidak ada backfill dan tidak mungkin tidak konsisten.
--   * nilai.periode_id diisi otomatis oleh trigger: dari komponen penilaiannya, atau (untuk nilai
--     lama tanpa komponen) dari periode yang rentang tanggalnya memuat tanggal nilai. Nilai yang
--     tanggalnya belum tercakup periode mana pun dibiarkan NULL (tidak ditebak).
--   * mapel_guru.mapel_id: penugasan lama (sebelum ada mata pelajaran) tetap ada dengan mapel_id
--     NULL. Penugasan seperti itu tetap memberi hak absensi kelas, tetapi tidak memberi hak input
--     nilai sampai admin menetapkan mata pelajarannya.
--   * riwayat_klasifikasi (bulanan, lama) tidak diubah. Hasil perhitungan per semester disimpan di
--     klasifikasi_siswa karena butirnya berbeda (per periode akademik, dengan skor sumbernya).
--   * TIDAK ada aturan klasifikasi bawaan: ambang Mahir/Cukup ditetapkan admin per periode.

BEGIN;

-- Periode akademik

CREATE TABLE IF NOT EXISTS periode_akademik (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tahun_ajaran    text        NOT NULL CHECK (
    CASE WHEN tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$'
      THEN substring(tahun_ajaran FROM 6 FOR 4)::int = substring(tahun_ajaran FROM 1 FOR 4)::int + 1
      ELSE false
    END
  ),
  semester        smallint    NOT NULL CHECK (semester IN (1, 2)),
  tanggal_mulai   date        NOT NULL,
  tanggal_selesai date        NOT NULL,
  aktif           boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tahun_ajaran, semester),
  CHECK (tanggal_selesai > tanggal_mulai)
);
CREATE UNIQUE INDEX IF NOT EXISTS periode_akademik_satu_aktif_uq
  ON periode_akademik (aktif) WHERE aktif;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'periode_akademik_tanpa_tumpang_tindih') THEN
    ALTER TABLE periode_akademik ADD CONSTRAINT periode_akademik_tanpa_tumpang_tindih
      EXCLUDE USING gist (daterange(tanggal_mulai, tanggal_selesai, '[]') WITH &&);
  END IF;
END
$$;

-- Mata pelajaran

CREATE TABLE IF NOT EXISTS mata_pelajaran (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kode       text        NOT NULL UNIQUE CHECK (kode ~ '^[A-Z0-9]{2,12}$'),
  nama       text        NOT NULL CHECK (btrim(nama) <> ''),
  deskripsi  text        NOT NULL DEFAULT '',
  jenis      text        NOT NULL DEFAULT 'umum' CHECK (jenis IN ('umum', 'muatan_lokal')),
  -- Jenjang kelas (1-6) tempat mata pelajaran ini diajarkan.
  tingkat    smallint[]  NOT NULL DEFAULT '{1,2,3,4,5,6}' CHECK (
    cardinality(tingkat) > 0 AND tingkat <@ '{1,2,3,4,5,6}'::smallint[]
  ),
  aktif      boolean     NOT NULL DEFAULT true,
  urutan     int         NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS mata_pelajaran_nama_uq ON mata_pelajaran (lower(nama));

-- Template awal mata pelajaran umum SD (struktur Kurikulum Merdeka). Hanya titik awal: admin dapat
-- mengubah nama, jenjang, menonaktifkan, dan menambah muatan lokal. Tidak menimpa data yang ada.
INSERT INTO mata_pelajaran (kode, nama, deskripsi, jenis, tingkat, aktif, urutan) VALUES
  ('PABP', 'Pendidikan Agama dan Budi Pekerti', 'Template awal; sesuaikan dengan agama yang dilayani sekolah.', 'umum', '{1,2,3,4,5,6}', true, 10),
  ('PP',   'Pendidikan Pancasila', 'Template awal.', 'umum', '{1,2,3,4,5,6}', true, 20),
  ('BIN',  'Bahasa Indonesia', 'Template awal.', 'umum', '{1,2,3,4,5,6}', true, 30),
  ('MTK',  'Matematika', 'Template awal.', 'umum', '{1,2,3,4,5,6}', true, 40),
  ('IPAS', 'Ilmu Pengetahuan Alam dan Sosial', 'Template awal; pada Kurikulum Merdeka diajarkan mulai kelas 3. Sesuaikan bila berbeda.', 'umum', '{3,4,5,6}', true, 50),
  ('SBD',  'Seni dan Budaya', 'Template awal; seni musik, rupa, teater, atau tari sesuai pilihan sekolah.', 'umum', '{1,2,3,4,5,6}', true, 60),
  ('PJOK', 'Pendidikan Jasmani, Olahraga, dan Kesehatan', 'Template awal.', 'umum', '{1,2,3,4,5,6}', true, 70),
  ('BING', 'Bahasa Inggris', 'Template awal; mata pelajaran pilihan. Aktifkan bila diterapkan sekolah.', 'umum', '{1,2,3,4,5,6}', false, 80)
ON CONFLICT (kode) DO NOTHING;

-- Penugasan guru mata pelajaran per kelas

ALTER TABLE mapel_guru ADD COLUMN IF NOT EXISTS
  mapel_id bigint REFERENCES mata_pelajaran (id) ON DELETE RESTRICT;
ALTER TABLE mapel_guru DROP CONSTRAINT IF EXISTS mapel_guru_guru_id_kelas_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS mapel_guru_guru_kelas_mapel_uq
  ON mapel_guru (guru_id, kelas_id, mapel_id) WHERE mapel_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS mapel_guru_guru_kelas_tanpa_mapel_uq
  ON mapel_guru (guru_id, kelas_id) WHERE mapel_id IS NULL;
CREATE INDEX IF NOT EXISTS mapel_guru_mapel_idx ON mapel_guru (mapel_id);

-- Komponen penilaian (definisi), terpisah dari nilai siswa (hasil)

CREATE TABLE IF NOT EXISTS komponen_penilaian (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  periode_id bigint         NOT NULL REFERENCES periode_akademik (id) ON DELETE RESTRICT,
  mapel_id   bigint         NOT NULL REFERENCES mata_pelajaran (id) ON DELETE RESTRICT,
  -- Literasi/Numerasi bila nilai komponen ini dipakai untuk klasifikasi; NULL bila tidak.
  kategori   kategori_nilai,
  nama       text           NOT NULL CHECK (btrim(nama) <> ''),
  deskripsi  text           NOT NULL DEFAULT '',
  -- Bobot relatif (opsional). Total bobot komponen aktif per mapel per periode maksimal 100.
  bobot      numeric(5, 2)  CHECK (bobot > 0 AND bobot <= 100),
  aktif      boolean        NOT NULL DEFAULT true,
  urutan     int            NOT NULL DEFAULT 0,
  created_at timestamptz    NOT NULL DEFAULT now(),
  updated_at timestamptz    NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS komponen_penilaian_nama_uq
  ON komponen_penilaian (periode_id, mapel_id, lower(nama));
CREATE INDEX IF NOT EXISTS komponen_penilaian_mapel_idx ON komponen_penilaian (mapel_id);

-- Nilai: periode, mapel, dan komponen

ALTER TABLE nilai ADD COLUMN IF NOT EXISTS
  periode_id bigint REFERENCES periode_akademik (id) ON DELETE RESTRICT;
ALTER TABLE nilai ADD COLUMN IF NOT EXISTS
  mapel_id bigint REFERENCES mata_pelajaran (id) ON DELETE RESTRICT;
ALTER TABLE nilai ADD COLUMN IF NOT EXISTS
  komponen_id bigint REFERENCES komponen_penilaian (id) ON DELETE RESTRICT;
-- Komponen di luar Literasi/Numerasi (mis. PJOK) tidak memiliki kategori.
ALTER TABLE nilai ALTER COLUMN kategori DROP NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'nilai_kategori_atau_komponen') THEN
    ALTER TABLE nilai ADD CONSTRAINT nilai_kategori_atau_komponen
      CHECK (komponen_id IS NOT NULL OR kategori IS NOT NULL);
  END IF;
END
$$;
CREATE INDEX IF NOT EXISTS nilai_periode_siswa_idx ON nilai (periode_id, siswa_id);
CREATE INDEX IF NOT EXISTS nilai_komponen_idx ON nilai (komponen_id);
CREATE INDEX IF NOT EXISTS nilai_mapel_idx ON nilai (mapel_id);

CREATE OR REPLACE FUNCTION nilai_sinkron_periode() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  k record;
BEGIN
  IF NEW.komponen_id IS NOT NULL THEN
    SELECT periode_id, mapel_id, kategori INTO k FROM komponen_penilaian WHERE id = NEW.komponen_id;
    NEW.periode_id := k.periode_id;
    NEW.mapel_id := k.mapel_id;
    NEW.kategori := k.kategori;
  ELSIF NEW.periode_id IS NULL THEN
    SELECT id INTO NEW.periode_id FROM periode_akademik
    WHERE NEW.tanggal BETWEEN tanggal_mulai AND tanggal_selesai;
  END IF;

  IF NEW.periode_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM periode_akademik
    WHERE id = NEW.periode_id AND NEW.tanggal BETWEEN tanggal_mulai AND tanggal_selesai
  ) THEN
    RAISE EXCEPTION 'Tanggal nilai % berada di luar rentang periode akademiknya.', NEW.tanggal
      USING ERRCODE = 'check_violation', CONSTRAINT = 'nilai_tanggal_dalam_periode';
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_nilai_sinkron_periode ON nilai;
CREATE TRIGGER trg_nilai_sinkron_periode
  BEFORE INSERT OR UPDATE OF komponen_id, periode_id, tanggal ON nilai
  FOR EACH ROW EXECUTE FUNCTION nilai_sinkron_periode();

-- Mengubah tanggal periode tidak boleh membuat nilai yang sudah ada keluar dari periodenya.
CREATE OR REPLACE FUNCTION periode_jaga_rentang_nilai() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM nilai
    WHERE periode_id = NEW.id AND NOT (tanggal BETWEEN NEW.tanggal_mulai AND NEW.tanggal_selesai)
  ) THEN
    RAISE EXCEPTION 'Ada nilai di periode ini yang tanggalnya di luar rentang baru.'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'periode_memuat_nilai';
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_periode_jaga_rentang_nilai ON periode_akademik;
CREATE TRIGGER trg_periode_jaga_rentang_nilai
  BEFORE UPDATE OF tanggal_mulai, tanggal_selesai ON periode_akademik
  FOR EACH ROW EXECUTE FUNCTION periode_jaga_rentang_nilai();

-- Komponen yang sudah berisi nilai tidak boleh pindah periode/mapel; perubahan kategorinya
-- diteruskan ke nilai agar kolom nilai.kategori tidak basi.
CREATE OR REPLACE FUNCTION komponen_jaga_nilai() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.periode_id, NEW.mapel_id) IS DISTINCT FROM (OLD.periode_id, OLD.mapel_id)
     AND EXISTS (SELECT 1 FROM nilai WHERE komponen_id = OLD.id) THEN
    RAISE EXCEPTION 'Komponen yang sudah memiliki nilai tidak dapat dipindah periode atau mapel.'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'komponen_terpakai';
  END IF;
  IF NEW.kategori IS DISTINCT FROM OLD.kategori THEN
    UPDATE nilai SET kategori = NEW.kategori WHERE komponen_id = NEW.id;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_komponen_jaga_nilai ON komponen_penilaian;
CREATE TRIGGER trg_komponen_jaga_nilai
  BEFORE UPDATE OF periode_id, mapel_id, kategori ON komponen_penilaian
  FOR EACH ROW EXECUTE FUNCTION komponen_jaga_nilai();

-- Aturan klasifikasi per periode (ditetapkan admin; tidak ada nilai bawaan)

CREATE TABLE IF NOT EXISTS aturan_klasifikasi (
  periode_id  bigint        PRIMARY KEY REFERENCES periode_akademik (id) ON DELETE CASCADE,
  -- rata_rata: (skor Literasi + skor Numerasi) / 2; terendah: skor yang lebih rendah.
  metode      text          NOT NULL CHECK (metode IN ('rata_rata', 'terendah')),
  batas_mahir numeric(5, 2) NOT NULL CHECK (batas_mahir BETWEEN 0 AND 100),
  batas_cukup numeric(5, 2) NOT NULL CHECK (batas_cukup BETWEEN 0 AND 100),
  diubah_oleh bigint        REFERENCES users (id) ON DELETE SET NULL,
  updated_at  timestamptz   NOT NULL DEFAULT now(),
  CHECK (batas_cukup < batas_mahir)
);

-- Hasil klasifikasi per siswa per periode

CREATE TABLE IF NOT EXISTS klasifikasi_siswa (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siswa_id      bigint        NOT NULL REFERENCES siswa (id) ON DELETE CASCADE,
  periode_id    bigint        NOT NULL REFERENCES periode_akademik (id) ON DELETE RESTRICT,
  -- Kelas siswa saat dihitung, agar perbandingan antarkelas periode lama tetap benar.
  kelas_id      bigint        REFERENCES kelas (id) ON DELETE SET NULL,
  skor_literasi numeric(5, 2),
  skor_numerasi numeric(5, 2),
  skor_akhir    numeric(5, 2),
  -- NULL: siswa punya nilai di periode ini tetapi datanya belum lengkap untuk diklasifikasi.
  klasifikasi   klasifikasi,
  dihitung_pada timestamptz   NOT NULL DEFAULT now(),
  UNIQUE (siswa_id, periode_id),
  CHECK (klasifikasi IS NULL OR skor_akhir IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS klasifikasi_siswa_periode_kelas_idx
  ON klasifikasi_siswa (periode_id, kelas_id, klasifikasi);

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['periode_akademik', 'mata_pelajaran', 'komponen_penilaian', 'aturan_klasifikasi'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_' || t || '_updated_at') THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
        'trg_' || t || '_updated_at', t
      );
    END IF;
  END LOOP;
END
$$;

-- View lama dibuat ulang agar ikut memuat kolom baru nilai (n.* dibekukan saat CREATE VIEW).
DROP VIEW IF EXISTS v_nilai;
CREATE VIEW v_nilai AS
SELECT n.*,
       lag(n.nilai) OVER (
         PARTITION BY n.siswa_id, n.kategori ORDER BY n.tanggal, n.id
       ) AS nilai_sebelumnya
FROM nilai n;

COMMIT;
