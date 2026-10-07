# Metode Immutable

Panduan ini menjelaskan cara menjalankan aplikasi Laravel dengan image immutable di production. Source code dan asset frontend masuk ke dalam image, sehingga source code tidak perlu di-bind mount saat runtime.

Letakkan file berikut di root repository aplikasi:

```text
Dockerfile
docker-compose.yml
.dockerignore
```

## 1. Salin file

Salin ketiga file tersebut ke root repository. Buat `.env` dari `.env.example` dan pastikan `APP_KEY` sudah diisi dengan nilai yang valid.

## 2. Sesuaikan `config/app.php`

Pastikan konfigurasi berikut tercantum satu kali:

```php
'asset_url' => env('ASSET_URL', env('APP_URL')),
```

### Konfigurasi URL asset

Laravel menggunakan konfigurasi ini sebagai basis URL untuk `asset()` dan asset production. Di Compose, port internal container bisa berbeda dari port yang digunakan browser. Contoh:

```text
Container app: 8080
Port host:     8888
```

Tanpa fallback, Laravel dapat menghasilkan URL seperti:

```text
http://localhost/build/assets/app.css
```

Padahal URL yang benar adalah:

```text
http://localhost:8888/build/assets/app.css
```

Dengan fallback ke `APP_URL`, URL asset dapat dijangkau browser. Isi `ASSET_URL` jika asset disajikan dari URL terpisah.

## 3. Tambahkan variabel ke `.env`

Untuk Docker Compose lokal, gunakan konfigurasi berikut:

```env
APP_URL=http://localhost:8080

PUBLISHED_HTTP_PORT=8080
PUBLISHED_HTTPS_PORT=8443

DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel
```

Jika pengguna mengakses aplikasi dari komputer lain, atur `APP_URL` ke alamat dan port yang mereka masukkan di browser. Contoh:

```env
APP_URL=http://192.168.0.1:8888
```

Atau menggunakan hostname:

```env
APP_URL=http://server1:8888
```

Pastikan komputer pengguna dapat me-resolve hostname tersebut dan firewall mengizinkan port aplikasi.

### Keterangan variabel

| Variabel | Fungsi |
|---|---|
| `APP_URL` | URL publik aplikasi yang digunakan Laravel dan URL asset. Sertakan hostname serta port. |
| `PUBLISHED_HTTP_PORT` | Port host untuk HTTP aplikasi. Dipetakan ke port `8080` di container `app`. |
| `PUBLISHED_HTTPS_PORT` | Port host untuk HTTPS aplikasi. Dipetakan ke port `8443` di container `app`. |
| `DB_CONNECTION` | Driver database Laravel. Untuk Compose: `pgsql`. |
| `DB_HOST` | Host database dari dalam container app. Gunakan `db`, bukan `localhost`. |
| `DB_PORT` | Port PostgreSQL dari dalam network Compose. Gunakan `5432`. |
| `DB_DATABASE` | Nama database PostgreSQL. Wajib diisi oleh Compose. |
| `DB_USERNAME` | Username PostgreSQL. Wajib diisi oleh Compose. |
| `DB_PASSWORD` | Password PostgreSQL. Wajib diisi oleh Compose. |

Compose akan berhenti dengan error jika `DB_DATABASE`, `DB_USERNAME`, atau `DB_PASSWORD` tidak diisi.

Tambahkan `ASSET_URL` ke `.env` hanya jika asset disajikan dari URL terpisah. Jika tidak, `config/app.php` memakai `APP_URL`.

## Menjalankan production

Build dan jalankan stack:

```bash
docker compose up -d --build
```

Build menginstal dependency PHP, membuat asset frontend, lalu menyalinnya ke image aplikasi. `.dockerignore` mengecualikan `.env`, dependency lokal, log, dan asset lama dari proses build.

Buka alamat yang tercantum di `APP_URL`, misalnya:

```text
http://192.168.0.1:8888
```

Container `app` menunggu PostgreSQL sehat sebelum mulai. Contoh ini menjalankan migration saat boot dengan `RUN_MIGRATIONS_ON_BOOT=true`, yang hanya cocok untuk single instance. Untuk deployment multi-replica, jalankan migration job terpisah sebelum service aplikasi.

Image tidak menyertakan `.env`. Compose me-mount file tersebut dalam mode read-only. Source code tetap berada di dalam image, named volume `storage` menyimpan file runtime seperti upload, dan volume `db` menyimpan data PostgreSQL.

Setelah source code atau dependency berubah, build ulang image:

```bash
docker compose up -d --build
```

## Troubleshooting

Periksa status dan log container:

```bash
docker compose ps -a
docker compose logs app db
```

Jika database belum healthy, container `app` belum mulai. Untuk melihat error build secara lengkap, jalankan perintah tanpa detached mode:

```bash
docker compose up --build
```

## Pemeriksaan konfigurasi

Sebelum build, validasi file Compose:

```bash
docker compose config
```

Jika variable database wajib belum diisi, Compose akan menampilkan error seperti:

```text
DB_DATABASE is required
```

Isi konfigurasi database yang diperlukan di `.env`.
