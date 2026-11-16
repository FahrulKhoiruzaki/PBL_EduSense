-- Foto sekolah untuk beranda website. Jalankan SETELAH 003. Hanya menambah kolom; idempoten.

BEGIN;

ALTER TABLE profil_sekolah ADD COLUMN IF NOT EXISTS foto_url text;

COMMIT;
