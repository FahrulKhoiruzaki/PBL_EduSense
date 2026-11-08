# EduSense Backend

Kerangka kerja backend bersama untuk proyek EduSense.

Folder ini hanya menyediakan struktur direktori dan konfigurasi awal. Implementasi API, autentikasi, database, model, service, dan fitur lainnya akan dikerjakan oleh anggota sesuai pembagian tugas.

## Persyaratan
- macOS
- Python 3.12 atau lebih baru
- PostgreSQL 13 atau lebih baru
- Git

## Persiapan lokal

Buat virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
```

Instal dependency:
```bash
python -m pip install --upgrade pip
pip install -r requirements.txt -r requirements-dev.txt
```

Salin konfigurasi:
```bash
cp .env.example .env
```

Buat secret key:
```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Masukkan hasilnya ke SECRET_KEY dalam file .env. Sesuaikan DATABASE_URL dengan PostgreSQL lokal masing-masing.

Jangan pernah mengunggah .env ke GitHub.

## Database dan aplikasi

Database schema, migration, entry point FastAPI, dan implementasi aplikasi belum disediakan. Bagian tersebut akan dikerjakan oleh anggota yang bertanggung jawab.

Konvensi port pengembangan: 8081.

## Kontribusi anggota
1. Gunakan branch fitur masing-masing.
2. Jangan commit langsung ke main atau develop.
3. Jangan mengunggah .env, .venv, cache, atau file upload lokal.
4. Koordinasikan perubahan struktur bersama.
5. Push branch dan ajukan Pull Request ke develop.
