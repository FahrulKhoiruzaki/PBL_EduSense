# Backend SDN 02 Pakunden (FastAPI + PostgreSQL)

API untuk aplikasi Guru (mobile), Portal Orang Tua, Panel Admin, dan Website. Kontraknya (path dan
field JSON) mengikuti yang sudah dipakai kode Flutter di `../aplikasi_guru`.

## Menjalankan (untuk tes manual)

Prasyarat: Python 3 (diuji dengan 3.14), PostgreSQL 13+ yang sudah berjalan, Flutter.

### 1. Database dan data awal

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

createdb sdn02                       # atau lewat psql/pgAdmin
cp .env.example .env                 # isi DATABASE_URL dan SECRET_KEY (lihat petunjuk di berkasnya)

python -m scripts.init_db            # schema.sql + semua migrasi (aman diulang; jalankan lagi
                                     # setiap kali ada migrasi baru di db/migrations/)
python -m scripts.seed               # data demo; menolak berjalan bila database sudah berisi
```

`python -m scripts.seed --reset` mengosongkan SEMUA data lalu mengisi ulang dari awal (meminta
konfirmasi; tambah `--yes` untuk melewatinya). Seeder menolak berjalan bila `ENVIRONMENT=production`.

Akun demo (seeder):

| Peran | Email | Password | Catatan |
|---|---|---|---|
| Admin | `admin@sdn02.test` | `Password123` | masuk lewat "Login Admin" di website |
| Guru: wali 5A + mapel 5B | `rina@sdn02.test` | `Password123` | wali hanya melihat 5A; boleh mencatat di 5B |
| Guru: mapel 5A dan 5B | `andi@sdn02.test` | `Password123` | absen, nilai, scan wajah |
| Guru: wali 5B + mapel 5A | `sari@sdn02.test` | `Password123` | |
| Guru: password sementara | `hadi@sdn02.test` | `Sementara123` | wajib ganti password; belum punya kelas |
| Orang tua, 2 anak (5A dan 5B) | `ortu.wijaya@sdn02.test` | `Password123` | Ahmad dan Salsa |
| Orang tua, 1 anak | `ortu.siti@sdn02.test` | `Password123` | juga `ortu.dimas`, `ortu.nadia`, `ortu.budi`, `ortu.citra`, `ortu.eko` |

Data demo: 3 kelas (5A, 5B, 6A kosong), 8 siswa dengan 28 hari absensi dan 6 nilai per kategori,
notifikasi, log aktivitas, dan konten website (berita, pengumuman, kegiatan, fasilitas, FAQ, teks
halaman). Absensi **hari ini sengaja kosong** supaya alur absen bisa dicoba.

Data akademik demo (periode, mapel termasuk contoh muatan lokal Bahasa Jawa, kelas 1-6, komponen
penilaian, nilai, absensi, aturan klasifikasi CONTOH) diisi `python -m scripts.seed_akademik`
(juga dipanggil oleh seeder utama). Idempoten dan tidak menghapus apa pun; menolak berjalan bila
`ENVIRONMENT=production`. Ambang klasifikasi dan bobot di seeder hanya contoh demo, bukan ketetapan
sekolah. Klasifikasi dihitung otomatis dari nilai (lihat `app/services/grading_service.py`) setelah
admin menetapkan aturan periode.

#### Backfill periode untuk nilai lama (database yang sudah berisi sebelum migrasi 005)

Nilai lama belum punya `periode_id`. Setelah admin membuat periode akademik yang sesuai:

```bash
python -m scripts.backfill_periode_nilai                      # DRY-RUN (bawaan): hanya laporan
python -m scripts.backfill_periode_nilai --report backfill.csv  # + laporan per baris (CSV)
python -m scripts.backfill_periode_nilai --apply              # terapkan; minta ketik "ya"
```

Nilai hanya dipetakan bila tanggalnya berada di dalam rentang tepat satu periode; tanggal yang
tidak tercakup dilaporkan "tidak dapat dipetakan" dan dibiarkan kosong (tidak ditebak). Mapel nilai
lama tidak diisi. `updated_at` nilai dipertahankan; klasifikasi periode aktif dihitung ulang
(periode lama hanya dengan `--hitung-ulang-periode-lama`). Satu transaksi: gagal = tidak ada yang
berubah. Backup database dulu sebelum `--apply` di data produksi.

Admin pertama untuk database produksi (tanpa seeder):
`python -m scripts.create_user --role admin --email admin@sekolah.id --nama "Admin Sekolah"`.

### 2. Server API

```bash
uvicorn app.main:create_app --factory --reload --port 8081
# agar bisa dijangkau perangkat lain di jaringan yang sama (iPad/HP), tambahkan: --host 0.0.0.0
```

API ada di `http://localhost:8081/api/v1` (sama dengan `API_BASE_URL` bawaan Flutter). Dokumentasi
interaktif di `/docs` (dimatikan bila `ENVIRONMENT=production`). Cek kesehatan: `GET /health`.
Gambar unggahan admin disimpan di folder `uploads/` (atur dengan `MEDIA_DIR`) dan disajikan di
`/media/...`; folder itu perlu dicadangkan bersama database.

### 3. Aplikasi Flutter

Jalankan dari `../aplikasi_guru`. Alamat server diberikan lewat `--dart-define=API_BASE_URL=...`:

| Target | Alamat server |
|---|---|
| Chrome, macOS, iOS Simulator | `http://localhost:8081/api/v1` |
| Android Emulator | `http://10.0.2.2:8081/api/v1` |
| Perangkat sungguhan (iPad/HP, satu Wi-Fi) | `http://<IP-komputer>:8081/api/v1` (server dengan `--host 0.0.0.0`) |

```bash
cd ../aplikasi_guru && flutter pub get

# Aplikasi Guru / Wali Kelas (mobile)
flutter run -t lib/main.dart -d <perangkat> --dart-define=API_BASE_URL=http://localhost:8081/api/v1

# Website publik + Portal Orang Tua + Panel Admin (web)
flutter run -t lib/main_website.dart -d chrome --dart-define=API_BASE_URL=http://localhost:8081/api/v1
```

`flutter devices` menampilkan nilai `<perangkat>`. Di website: "Login Orang Tua" ada di footer dan
menu, "Login Admin" ada di footer. Scan wajah butuh kamera (perangkat sungguhan atau webcam di
macOS/Chrome). Build debug Android mengizinkan HTTP polos; build rilis harus memakai HTTPS.

Origin `localhost` (port apa pun) otomatis diizinkan CORS di luar production; untuk production isi
`CORS_ORIGINS`.

## Tes

```bash
pytest
```

Tes berjalan di PostgreSQL sungguhan: klaster sementara dibuat otomatis bila `initdb` ditemukan
(atur `PG_BIN` bila tidak), atau gunakan `TEST_DATABASE_URL` yang namanya berakhiran `_test`
(isinya akan dikosongkan).

## Struktur

```
app/
  main.py            create_app(): middleware, format galat, router
  core/              config, database (SQLAlchemy), security (argon2 + JWT), errors
  models/            model SQLAlchemy untuk seluruh tabel
  schemas/           bentuk request/response (Pydantic)
  services/          logika bisnis: auth, absensi, pencocokan wajah, ml_service (placeholder)
  api/deps.py        autentikasi dan otorisasi peran
  api/routers/       auth, public, guru, guru_face, ortu, admin, admin_cms
db/schema.sql        salinan ../aplikasi_guru/database/schema.sql
db/migrations/       tambahan khusus backend (jalankan setelah schema.sql): 001 tambahan, 002 teks awal,
                     003 info kelas & kalender, 004 foto sekolah, 005 periode akademik, mapel,
                     komponen penilaian, klasifikasi per periode
scripts/             init_db, create_user, seed, seed_akademik, backfill_periode_nilai
```

`db/schema.sql` adalah salinan; bila `aplikasi_guru/database/schema.sql` berubah, salin ulang.

## Endpoint yang sudah ada

| Metode | Path | Keterangan |
|---|---|---|
| POST | `/auth/login` | semua peran; mengembalikan token, `user`, `guru`, `pengaturan` |
| GET | `/auth/me` | sesi saat ini |
| PUT | `/auth/password` | ganti password sementara (tanpa password lama) |
| POST | `/auth/logout` | mencabut semua token akun itu |
| POST | `/auth/forgot-password` | selalu 202; pengiriman email belum terhubung |
| GET | `/public/informasi`, `/public/informasi/{slug}` | pengumuman + berita terbit |
| GET | `/public/kegiatan`, `/public/kegiatan/{slug}` | |
| GET | `/public/fasilitas`, `/public/faq`, `/public/guru` | |
| GET | `/public/sekolah`, `/public/halaman` | profil sekolah dan teks halaman |
| POST | `/guru/classes/{kode}/attendance/face` | scan wajah, langsung mencatat hadir |
| POST/GET/DELETE | `/guru/classes/{kode}/students/{id}/face` | wali kelas mendaftarkan wajah |
| GET | `/guru/classes`, `/guru/classes/{kode}` | kelas yang diampu/diwalikan; detail: siswa, nilai, rata-rata, tren |
| PUT | `/guru/classes/{kode}/attendance/{siswa_id}` | absensi manual (204); menimpa catatan hari itu |
| POST | `/guru/classes/{kode}/attendance/finish` | siswa yang belum diabsen dicatat Alpa; `{jumlah_alpa}` |
| POST | `/guru/classes/{kode}/grades` | tambah nilai (201, `{id}`); wali kelas diberi notifikasi |
| PUT/DELETE | `/guru/grades/{id}` | ubah / hapus nilai (204) |
| GET | `/guru/notifications`, `/guru/activities` | milik guru yang login |
| POST | `/guru/notifications/{id}/read`, `/guru/notifications/read-all` | 204 |

Wali kelas yang bukan guru mapel kelas itu hanya boleh **melihat**; mencatat absensi, nilai, dan
scan wajah hanya untuk guru mapel kelas tersebut (403 selain itu).

### Orang tua (`/ortu/*`)

| Metode | Path | Keterangan |
|---|---|---|
| GET | `/ortu/children` | anak-anak akun ini: nilai rata-rata, kehadiran, tren mingguan, riwayat klasifikasi, daftar nilai |
| GET | `/ortu/children/{id}/attendance` | hari per hari, 366 hari terakhir (urut lama ke baru) |
| GET | `/ortu/children/{id}/history` | nilai, kehadiran selain Hadir, dan perubahan klasifikasi (terbaru dulu) |
| GET | `/ortu/notifications` | milik akun itu; `POST .../{id}/read` dan `.../read-all` (204) |

Anak milik orang tua lain dijawab 404 (bukan 403). Persen kehadiran dan jumlah terlambat dihitung
sejak 1 Juli tahun pertama `tahun_ajaran`. Notifikasi orang tua dibuat otomatis saat nilai
ditambahkan, absensi berubah status, scan wajah mencatat hadir, atau absensi diselesaikan (Alpa).

### Admin (`/admin/*`)

| Metode | Path | Keterangan |
|---|---|---|
| GET/PUT | `/admin/me`, `/admin/me/password` | PUT butuh password lama; salah = 422 (bukan 401) |
| GET/POST | `/admin/guru`, `/admin/admins`, `/admin/siswa` | POST mengembalikan `{id, email, password_sementara}` |
| PUT/DELETE | `/admin/{guru,admins,siswa}/{id}` | ubah / hapus akun |
| POST | `/admin/{guru,admins,siswa}/{id}/reset-password` | password sementara baru; sesi lama dicabut |
| PUT | `/admin/{guru,admins,siswa}/{id}/active` | `{aktif}`; akun siswa = akun orang tuanya |
| POST | `/admin/siswa/move` | `{siswa_ids, kelas_tujuan}`; nilai dan absensi ikut pindah |
| GET/POST/DELETE | `/admin/classes`, `/admin/classes/{kode}` | hapus hanya bila kelas kosong |
| PUT | `/admin/classes/{kode}/wali` | `{guru_id}`; kosong/null melepas wali |
| POST/DELETE | `/admin/classes/{kode}/mapel`, `.../mapel/{guru_id}?mapel_id=` | penugasan `{guru_id, mapel_id}`; tanpa `mapel_id` = penugasan lama (absensi saja, belum boleh input nilai) |
| GET/PUT | `/admin/settings` | `tahun_ajaran` mengikuti periode aktif (bila ada), `batas_jam_terlambat` (`HH:MM` atau null) |
| GET | `/admin/logs?limit=` | log aktivitas, terbaru dulu (1-1000, bawaan 100) |

- Menambah siswa otomatis membuat akun orang tua dengan email
  `ortu.<nama-siswa>@<PARENT_EMAIL_DOMAIN>` (angka ditambahkan bila sudah dipakai) dan password
  sementara yang wajib diganti saat login pertama.
- `peran` guru (`wali`/`mapel`) diturunkan dari penugasan kelas; nilai `peran` saat membuat akun
  hanya petunjuk dan tidak disimpan. Satu guru hanya bisa menjadi wali satu kelas: menetapkannya di
  kelas lain mengosongkan wali kelas lamanya.
- Admin tidak dapat menghapus, menonaktifkan, atau mereset akunnya sendiri.
- Menghapus siswa juga menghapus akun orang tuanya bila tidak punya anak lain. Menghapus guru
  melepas semua penugasannya; nilai dan absensi yang pernah ia catat tetap ada.
- Setiap perubahan oleh admin masuk ke log aktivitas dalam transaksi yang sama.

### Akademik (`/admin/academic/*`, khusus admin)

| Metode | Path | Keterangan |
|---|---|---|
| GET/POST | `/admin/academic/periods` | periode = satu semester satu tahun ajaran; rentang tidak boleh tumpang tindih |
| PUT/DELETE | `/admin/academic/periods/{id}` | hapus hanya bila belum ada nilai/komponen/hasil klasifikasi dan tidak aktif |
| POST | `/admin/academic/periods/{id}/activate` | satu periode aktif; data periode lain tidak berubah |
| GET/PUT | `/admin/academic/periods/{id}/rule` | aturan klasifikasi `{metode: rata_rata/terendah, batas_mahir, batas_cukup}`; PUT menghitung ulang |
| POST | `/admin/academic/periods/{id}/recompute` | hitung ulang klasifikasi periode |
| GET/POST/PUT/DELETE | `/admin/academic/subjects[/{id}]` | mapel `{kode, nama, jenis: umum/muatan_lokal, tingkat, deskripsi}`; yang sudah dipakai hanya bisa dinonaktifkan |
| PUT | `/admin/academic/subjects/{id}/active` | `{aktif}` |
| GET | `/admin/academic/components?periode_id=&mapel_id=` | komponen penilaian per periode |
| POST/PUT/DELETE | `/admin/academic/components[/{id}]` | `{periode_id, mapel_id, nama, kategori, bobot, deskripsi}`; total bobot aktif per mapel maks 100 |
| PUT | `/admin/academic/components/{id}/active` | nonaktif = tidak bisa diisi nilai baru; nilai lama tetap dihitung |
| POST | `/admin/academic/components/copy` | `{dari_periode_id, ke_periode_id}` |
| GET | `/admin/academic/classification?periode_id=&kelas=` | distribusi Mahir/Cukup/Perlu Pendampingan (jumlah + persen), per kelas, perbandingan periode sebelumnya |

Guru: `GET /guru/periods`, `GET /guru/classes/{kode}?periode_id=`, `GET /guru/classes/{kode}/subjects`,
`GET /guru/classes/{kode}/recap?mapel_id=`, `GET /guru/classes/{kode}/classification`. Input nilai
(`POST /guru/classes/{kode}/grades`, `PUT /guru/grades/{id}`) memakai `komponen_id` (bukan
`kategori`); hanya guru yang ditugaskan mengajar mapel komponen itu di kelas itu.

### Kelola Website (`/admin/cms/*`, khusus admin)

Konten website tidak lagi tertanam di aplikasi; semuanya dibaca dari database lewat `/public/*` dan
diubah admin lewat endpoint ini. Tabelnya memakai yang sudah ada: `halaman_situs` (teks),
`profil_sekolah` (kontak), `pengumuman` + `berita`, `kegiatan` + `kegiatan_foto`, `fasilitas`, `faq`.

| Metode | Path | Keterangan |
|---|---|---|
| GET/PUT | `/admin/cms/pages` | daftar semua teks yang dapat diedit `{kunci,label,grup,baris,isi}`; PUT `{"halaman": {kunci: isi}}`, teks kosong dihapus |
| GET/PUT | `/admin/cms/school` | nama, kota, NPSN, alamat, akreditasi, telepon, email, media sosial, WhatsApp, gambar peta |
| GET/POST | `/admin/cms/posts` | berita dan pengumuman dalam satu daftar (semua status, tanpa isi) |
| GET/PUT/DELETE | `/admin/cms/posts/{slug}` | detail, ubah, hapus; slug dibuat dari judul dan tidak berubah |
| GET/POST, PUT/DELETE | `/admin/cms/kegiatan`, `.../{slug}` | `foto_urls` (maks 20) menggantikan seluruh galeri |
| GET/POST, PUT/DELETE | `/admin/cms/fasilitas`, `.../{id}` | `urutan` kosong = di akhir |
| GET/POST, PUT/DELETE | `/admin/cms/faq`, `.../{id}` | `urutan` kosong = di akhir |
| POST | `/admin/cms/media` | multipart field `file` (JPEG/PNG/WebP, maks `MAX_MEDIA_BYTES`); membalas `{url, ukuran}` |

- Daftar kunci teks ada di `app/services/cms_pages.py` dan dipakai juga oleh formulir admin; menambah
  teks baru cukup menambah satu baris di sana lalu memakainya di website.
- Status konten: `draft`, `terbit`, `arsip`; hanya `terbit` yang tampil di `/public/*`. Mengganti kategori
  antara Pengumuman dan Berita memindahkan baris antar tabel dengan slug yang sama.
- Nomor WhatsApp dinormalkan ke `62xxxxxxxxxx` (siap untuk `wa.me`).
- Gambar: jenis ditentukan dari isi berkas (bukan nama atau tipe kiriman), nama file diacak, SVG dan
  GIF ditolak. Kolom gambar hanya menerima `/media/...` atau tautan `http(s)://`. File lama tidak
  dihapus saat gambar diganti; bersihkan folder `uploads/` secara berkala bila perlu.
- Respons `/public/*` memakai `Cache-Control: no-cache` agar perubahan admin langsung terlihat.

## Face recognition

- Hasil bisnis dikembalikan dengan status **200** dan field `hasil` (`cocok`, `duplikat`,
  `kelas_lain`, `tidak_dikenali`) plus `kode` (`FaceNotRecognized`, `FaceDuplicate`,
  `FaceOtherClass`), sehingga Flutter tidak menganggapnya galat jaringan.
- Cocok langsung mencatat `absensi` dengan `metode_input = face_recognition`. Status **T** (terlambat)
  dipakai bila `pengaturan_sekolah.batas_jam_terlambat` diisi dan waktu scan melewatinya; bila batas
  itu kosong, selalu **H**. Izin/Sakit/Alpa pada hari yang sama ditimpa; Hadir/Terlambat tidak.
- Hanya **guru mapel** kelas itu yang boleh scan. Hanya **wali kelas** yang boleh mendaftarkan,
  melihat, dan menghapus wajah siswa kelasnya.
- Yang disimpan hanya embedding (`wajah_siswa`), bukan fotonya. Embedding hanya dibandingkan dengan
  yang berversi model sama (`model_version`).
- `app/services/ml_service.py` masih **MOCK**: vektor berasal dari hash isi berkas, jadi hanya foto
  yang persis sama yang cocok. Ganti `MockFaceEmbedder` dengan FaceNet; wajah harus didaftarkan
  ulang setelah itu.

### Data biometrik anak

Embedding wajah adalah data pribadi sensitif milik anak di bawah umur. Sebelum dipakai nyata:
dapatkan persetujuan orang tua (teks persetujuan sudah ada di aplikasi), tetapkan masa simpan,
batasi akses database, dan sediakan cara menghapus data saat siswa lulus atau pindah
(`DELETE .../face` sudah ada untuk satu siswa).

## Catatan keamanan dan batasan

- Token JWT (HS256) berlaku `ACCESS_TOKEN_MINUTES` (bawaan 12 jam) dan dicabut lewat
  `users.token_version` saat logout atau akun dinonaktifkan. Tidak ada refresh token.
- Belum ada pembatasan percobaan login (rate limiting); pasang di reverse proxy atau tambahkan
  sebelum production.
- Batas ukuran unggahan dicek dari `Content-Length` dan saat membaca, tetapi unggahan chunked
  tetap ditulis sementara ke disk; batasi juga di reverse proxy.
- Pencocokan wajah memuat seluruh embedding setiap scan (cukup untuk satu sekolah); untuk skala besar
  gunakan cache atau indeks vektor.
- Slug `berita` dan `pengumuman` harus unik di antara keduanya; `/public/informasi/{slug}` mencari
  di `berita` dulu.
