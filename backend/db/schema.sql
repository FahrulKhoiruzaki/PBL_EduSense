-- SDN 02 Pakunden: skema PostgreSQL 13+ (jalankan pada database kosong)
-- psql -v ON_ERROR_STOP=1 -d <db> -f schema.sql

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Tipe enum

CREATE TYPE user_role AS ENUM ('admin', 'guru', 'ortu');
CREATE TYPE klasifikasi AS ENUM ('Mahir', 'Cukup', 'Perlu Pendampingan');
CREATE TYPE status_absensi AS ENUM ('H', 'T', 'I', 'S', 'A');
CREATE TYPE metode_input AS ENUM ('manual', 'face_recognition');
CREATE TYPE kategori_nilai AS ENUM ('Literasi', 'Numerasi');
CREATE TYPE konten_status AS ENUM ('draft', 'terbit', 'arsip');
CREATE TYPE berita_kategori AS ENUM ('Berita', 'Akademik', 'PPDB', 'Kegiatan');
CREATE TYPE kegiatan_kategori AS ENUM (
  'Akademik', 'Ekstrakurikuler', 'Upacara', 'Kegiatan Siswa', 'Sosial', 'Acara Sekolah'
);
CREATE TYPE faq_kategori AS ENUM ('Umum', 'PPDB', 'Keuangan', 'Akademik', 'Kegiatan');
CREATE TYPE log_tipe AS ENUM ('Kelas', 'Akun', 'Siswa', 'Sistem');

-- Fungsi bersama

CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

-- Akun dan profil

CREATE TABLE users (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email                text        NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$'),
  password_hash        text        NOT NULL,
  role                 user_role   NOT NULL,
  is_active            boolean     NOT NULL DEFAULT true,
  must_change_password boolean     NOT NULL DEFAULT true,
  last_login_at        timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, role)
);
CREATE UNIQUE INDEX users_email_lower_uq ON users (lower(email));
CREATE INDEX users_role_active_idx ON users (role, is_active);
CREATE INDEX users_email_trgm_idx ON users USING gin (email gin_trgm_ops);

CREATE TABLE admin (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id bigint    NOT NULL UNIQUE,
  role    user_role NOT NULL DEFAULT 'admin' CHECK (role = 'admin'),
  nama    text      NOT NULL CHECK (btrim(nama) <> ''),
  FOREIGN KEY (user_id, role) REFERENCES users (id, role) ON DELETE CASCADE
);

CREATE TABLE guru (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    bigint      NOT NULL UNIQUE,
  role       user_role   NOT NULL DEFAULT 'guru' CHECK (role = 'guru'),
  nip        text        CHECK (nip ~ '^[0-9]{18}$'),
  nama       text        NOT NULL CHECK (btrim(nama) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id, role) REFERENCES users (id, role) ON DELETE CASCADE
);
CREATE UNIQUE INDEX guru_nip_uq ON guru (nip) WHERE nip IS NOT NULL;
CREATE INDEX guru_nama_trgm_idx ON guru USING gin (nama gin_trgm_ops);

CREATE TABLE orang_tua (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      bigint      NOT NULL UNIQUE,
  role         user_role   NOT NULL DEFAULT 'ortu' CHECK (role = 'ortu'),
  nama_lengkap text        NOT NULL CHECK (btrim(nama_lengkap) <> ''),
  no_hp        text        CHECK (no_hp ~ '^\+?[0-9]{8,15}$'),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id, role) REFERENCES users (id, role) ON DELETE CASCADE
);
CREATE INDEX orang_tua_nama_trgm_idx ON orang_tua USING gin (nama_lengkap gin_trgm_ops);

-- Struktur kelas

CREATE TABLE kelas (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nama_kelas    text        NOT NULL UNIQUE CHECK (nama_kelas ~ '^[1-6][A-Z]$'),
  wali_kelas_id bigint      UNIQUE REFERENCES guru (id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE mapel_guru (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  guru_id    bigint      NOT NULL REFERENCES guru (id) ON DELETE CASCADE,
  kelas_id   bigint      NOT NULL REFERENCES kelas (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (guru_id, kelas_id)
);
CREATE INDEX mapel_guru_kelas_idx ON mapel_guru (kelas_id);

CREATE TABLE siswa (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nis               text        CHECK (nis ~ '^[0-9]{4,20}$'),
  nama              text        NOT NULL CHECK (btrim(nama) <> ''),
  kelas_id          bigint      NOT NULL REFERENCES kelas (id) ON DELETE RESTRICT,
  orang_tua_id      bigint      NOT NULL REFERENCES orang_tua (id) ON DELETE RESTRICT,
  status_klasifikasi klasifikasi,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX siswa_nis_uq ON siswa (nis) WHERE nis IS NOT NULL;
CREATE INDEX siswa_kelas_klasifikasi_idx ON siswa (kelas_id, status_klasifikasi);
CREATE INDEX siswa_orang_tua_idx ON siswa (orang_tua_id);
CREATE INDEX siswa_nama_trgm_idx ON siswa USING gin (nama gin_trgm_ops);

CREATE TABLE riwayat_klasifikasi (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siswa_id    bigint      NOT NULL REFERENCES siswa (id) ON DELETE CASCADE,
  periode     date        NOT NULL CHECK (periode = date_trunc('month', periode)::date),
  klasifikasi klasifikasi NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (siswa_id, periode)
);

-- Absensi dan nilai

CREATE TABLE absensi (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siswa_id     bigint         NOT NULL REFERENCES siswa (id) ON DELETE CASCADE,
  tanggal      date           NOT NULL,
  waktu        time,
  status       status_absensi NOT NULL,
  metode_input metode_input   NOT NULL DEFAULT 'manual',
  catatan      text,
  dicatat_oleh bigint         REFERENCES guru (id) ON DELETE SET NULL,
  created_at   timestamptz    NOT NULL DEFAULT now(),
  updated_at   timestamptz    NOT NULL DEFAULT now(),
  UNIQUE (siswa_id, tanggal),
  CHECK (status IN ('H', 'T') OR waktu IS NULL)
);
CREATE INDEX absensi_tanggal_status_idx ON absensi (tanggal, status);
CREATE INDEX absensi_dicatat_oleh_idx ON absensi (dicatat_oleh);

CREATE TABLE nilai (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siswa_id     bigint         NOT NULL REFERENCES siswa (id) ON DELETE CASCADE,
  kategori     kategori_nilai NOT NULL,
  jenis_ujian  text           NOT NULL CHECK (btrim(jenis_ujian) <> ''),
  nilai        numeric(5, 2)  NOT NULL CHECK (nilai BETWEEN 0 AND 100),
  tanggal      date           NOT NULL,
  catatan_guru text,
  dicatat_oleh bigint         REFERENCES guru (id) ON DELETE SET NULL,
  created_at   timestamptz    NOT NULL DEFAULT now(),
  updated_at   timestamptz    NOT NULL DEFAULT now()
);
CREATE INDEX nilai_siswa_kategori_tanggal_idx ON nilai (siswa_id, kategori, tanggal DESC);
CREATE INDEX nilai_tanggal_idx ON nilai (tanggal DESC);
CREATE INDEX nilai_dicatat_oleh_idx ON nilai (dicatat_oleh);

-- Konten website

CREATE TABLE pengumuman (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug          text          NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  judul         text          NOT NULL CHECK (btrim(judul) <> ''),
  ringkasan     text          NOT NULL DEFAULT '',
  isi           text          NOT NULL DEFAULT '',
  gambar_url    text,
  tanggal       date          NOT NULL DEFAULT CURRENT_DATE,
  status        konten_status NOT NULL DEFAULT 'draft',
  dibuat_oleh   bigint        REFERENCES users (id) ON DELETE SET NULL,
  created_at    timestamptz   NOT NULL DEFAULT now(),
  updated_at    timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX pengumuman_terbit_idx ON pengumuman (status, tanggal DESC);
CREATE INDEX pengumuman_judul_trgm_idx ON pengumuman USING gin (judul gin_trgm_ops);

CREATE TABLE berita (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug          text            NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  kategori      berita_kategori NOT NULL DEFAULT 'Berita',
  judul         text            NOT NULL CHECK (btrim(judul) <> ''),
  ringkasan     text            NOT NULL DEFAULT '',
  isi           text            NOT NULL DEFAULT '',
  gambar_url    text,
  tanggal       date            NOT NULL DEFAULT CURRENT_DATE,
  status        konten_status   NOT NULL DEFAULT 'draft',
  dibuat_oleh   bigint          REFERENCES users (id) ON DELETE SET NULL,
  created_at    timestamptz     NOT NULL DEFAULT now(),
  updated_at    timestamptz     NOT NULL DEFAULT now()
);
CREATE INDEX berita_terbit_idx ON berita (status, kategori, tanggal DESC);
CREATE INDEX berita_judul_trgm_idx ON berita USING gin (judul gin_trgm_ops);

CREATE TABLE kegiatan (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug        text              NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  kategori    kegiatan_kategori NOT NULL,
  judul       text              NOT NULL CHECK (btrim(judul) <> ''),
  deskripsi   text              NOT NULL DEFAULT '',
  tanggal     date              NOT NULL DEFAULT CURRENT_DATE,
  status      konten_status     NOT NULL DEFAULT 'draft',
  dibuat_oleh bigint            REFERENCES users (id) ON DELETE SET NULL,
  created_at  timestamptz       NOT NULL DEFAULT now(),
  updated_at  timestamptz       NOT NULL DEFAULT now()
);
CREATE INDEX kegiatan_terbit_idx ON kegiatan (status, kategori, tanggal DESC);

CREATE TABLE kegiatan_foto (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kegiatan_id bigint NOT NULL REFERENCES kegiatan (id) ON DELETE CASCADE,
  url         text   NOT NULL,
  keterangan  text,
  urutan      int    NOT NULL DEFAULT 0
);
CREATE INDEX kegiatan_foto_kegiatan_idx ON kegiatan_foto (kegiatan_id, urutan);

CREATE TABLE fasilitas (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nama       text        NOT NULL CHECK (btrim(nama) <> ''),
  deskripsi  text        NOT NULL DEFAULT '',
  gambar_url text,
  urutan     int         NOT NULL DEFAULT 0,
  tampil     boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX fasilitas_tampil_idx ON fasilitas (tampil, urutan);

CREATE TABLE faq (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kategori   faq_kategori NOT NULL,
  pertanyaan text         NOT NULL CHECK (btrim(pertanyaan) <> ''),
  jawaban    text         NOT NULL DEFAULT '',
  urutan     int          NOT NULL DEFAULT 0,
  tampil     boolean      NOT NULL DEFAULT true,
  created_at timestamptz  NOT NULL DEFAULT now(),
  updated_at timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX faq_tampil_idx ON faq (tampil, kategori, urutan);
CREATE INDEX faq_pertanyaan_trgm_idx ON faq USING gin (pertanyaan gin_trgm_ops);

-- Pengaturan, log, notifikasi

CREATE TABLE pengaturan_sekolah (
  id                  boolean PRIMARY KEY DEFAULT true CHECK (id),
  tahun_ajaran        text        NOT NULL CHECK (tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$'),
  batas_jam_terlambat time,
  updated_at          timestamptz NOT NULL DEFAULT now()
);
INSERT INTO pengaturan_sekolah (tahun_ajaran) VALUES ('2026/2027');

CREATE TABLE log_aktivitas (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    bigint      REFERENCES users (id) ON DELETE SET NULL,
  tipe       log_tipe    NOT NULL,
  pesan      text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX log_aktivitas_waktu_idx ON log_aktivitas (created_at DESC);
CREATE INDEX log_aktivitas_tipe_idx ON log_aktivitas (tipe, created_at DESC);
CREATE INDEX log_aktivitas_pesan_trgm_idx ON log_aktivitas USING gin (pesan gin_trgm_ops);

CREATE TABLE notifikasi (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  judul      text        NOT NULL,
  target     text,
  target_id  bigint,
  dibaca     boolean     NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifikasi_user_idx ON notifikasi (user_id, dibaca, created_at DESC);

-- Trigger updated_at

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users', 'guru', 'orang_tua', 'kelas', 'siswa', 'absensi', 'nilai',
    'pengumuman', 'berita', 'kegiatan', 'fasilitas', 'faq', 'pengaturan_sekolah'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
      'trg_' || t || '_updated_at', t
    );
  END LOOP;
END
$$;

-- View

CREATE VIEW v_nilai AS
SELECT n.*,
       lag(n.nilai) OVER (
         PARTITION BY n.siswa_id, n.kategori ORDER BY n.tanggal, n.id
       ) AS nilai_sebelumnya
FROM nilai n;

CREATE VIEW v_rekap_kehadiran_bulanan AS
SELECT siswa_id,
       date_trunc('month', tanggal)::date AS bulan,
       count(*) FILTER (WHERE status = 'H') AS hadir,
       count(*) FILTER (WHERE status = 'T') AS terlambat,
       count(*) FILTER (WHERE status = 'I') AS izin,
       count(*) FILTER (WHERE status = 'S') AS sakit,
       count(*) FILTER (WHERE status = 'A') AS alpa,
       count(*) AS total
FROM absensi
GROUP BY siswa_id, date_trunc('month', tanggal);

CREATE VIEW v_informasi AS
SELECT id, slug, 'Pengumuman'::text AS kategori, judul, ringkasan, gambar_url, tanggal
FROM pengumuman WHERE status = 'terbit'
UNION ALL
SELECT id, slug, kategori::text, judul, ringkasan, gambar_url, tanggal
FROM berita WHERE status = 'terbit';

COMMIT;
