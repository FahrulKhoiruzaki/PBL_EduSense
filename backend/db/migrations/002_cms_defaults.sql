-- Isi awal teks website yang sebelumnya tertanam di aplikasi. Jalankan SETELAH 001.
-- Idempoten: tidak menimpa teks yang sudah diubah admin.

BEGIN;

INSERT INTO halaman_situs (kunci, isi) VALUES
  ('hero-kicker', 'Kota Blitar'),
  ('hero-title', E'SDN 02 Pakunden\nKota Blitar'),
  ('hero-subtitle', 'Informasi sekolah dalam satu tempat: profil, kegiatan, akademik, dan penerimaan peserta didik baru.'),
  ('ppdb-banner', 'Jadwal, persyaratan, dan alur pendaftaran diumumkan oleh pihak sekolah.'),
  ('kontak-ajakan', 'Hubungi admin sekolah melalui WhatsApp.')
ON CONFLICT (kunci) DO NOTHING;

COMMIT;
