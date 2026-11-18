-- Tambahan untuk backend FastAPI. Jalankan SETELAH schema.sql.
-- Idempoten: aman dijalankan ulang.

BEGIN;

-- Menolak token lama setelah logout (token membawa versi ini).
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version integer NOT NULL DEFAULT 0;

-- Profil publik guru untuk halaman "Guru dan Tenaga Kependidikan".
ALTER TABLE guru ADD COLUMN IF NOT EXISTS jabatan text;
ALTER TABLE guru ADD COLUMN IF NOT EXISTS foto_url text;
ALTER TABLE guru ADD COLUMN IF NOT EXISTS tampil_publik boolean NOT NULL DEFAULT false;

-- Embedding wajah siswa. Hanya vektor yang disimpan, bukan fotonya.
CREATE TABLE IF NOT EXISTS wajah_siswa (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siswa_id         bigint           NOT NULL REFERENCES siswa (id) ON DELETE CASCADE,
  embedding        double precision[] NOT NULL CHECK (cardinality(embedding) > 0),
  model_version    text             NOT NULL,
  didaftarkan_oleh bigint           REFERENCES guru (id) ON DELETE SET NULL,
  created_at       timestamptz      NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wajah_siswa_siswa_idx ON wajah_siswa (siswa_id);

-- Identitas dan kontak sekolah (satu baris).
CREATE TABLE IF NOT EXISTS profil_sekolah (
  id           boolean PRIMARY KEY DEFAULT true CHECK (id),
  nama         text        NOT NULL DEFAULT 'SDN 02 Pakunden',
  kota         text        NOT NULL DEFAULT 'Blitar',
  npsn         text,
  alamat       text,
  akreditasi   text,
  telepon      text,
  email        text,
  media_sosial text,
  whatsapp     text,
  peta_url     text,
  updated_at   timestamptz NOT NULL DEFAULT now()
);
INSERT INTO profil_sekolah (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- Teks halaman statis website (sambutan, sejarah, visi, ppdb-informasi, dst).
CREATE TABLE IF NOT EXISTS halaman_situs (
  kunci      text        PRIMARY KEY CHECK (kunci ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  isi        text        NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['profil_sekolah', 'halaman_situs'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_' || t || '_updated_at'
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
        'trg_' || t || '_updated_at', t
      );
    END IF;
  END LOOP;
END
$$;

COMMIT;
