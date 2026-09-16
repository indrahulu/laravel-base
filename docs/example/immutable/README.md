# Metode Immutable

Panduan ini menjelaskan cara menjalankan aplikasi Laravel sebagai image immutable untuk production. Source code dan asset frontend dibangun ke dalam image; saat runtime tidak ada bind mount source code.

File berikut harus diletakkan di root repository aplikasi:

```text
Dockerfile
docker-compose.yml
.dockerignore
```

## 1. Salin file

Salin ketiga file tersebut ke root repository aplikasi. Repository harus memiliki `composer.json`, `package.json`, dan `package-lock.json`.

Pastikan `.env` sudah dibuat dari `.env.example` dan memiliki `APP_KEY` yang valid. File ini tidak ikut dibangun ke image, tetapi di-mount read-only saat container berjalan.

## 2. Sesuaikan `config/app.php`

Pastikan konfigurasi berikut ada. Jangan menambahkan key yang sama dua kali.

```php
'asset_url' => env('ASSET_URL', env('APP_URL')),
```

### Mengapa perlu diubah?

Laravel memakai konfigurasi ini sebagai basis URL untuk `asset()` dan asset production.

Pada Compose, port internal container berbeda dengan port yang dilihat browser. Contohnya:

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

Fallback ke `APP_URL` membuat asset memakai alamat yang dapat dijangkau browser. Isi `ASSET_URL` hanya bila asset disajikan dari URL terpisah.

## 3. Tambahkan variable ke `.env`

Gunakan contoh berikut untuk Docker Compose lokal:

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

Jika aplikasi diakses dari komputer lain, gunakan alamat publik yang sama dengan alamat yang diketik di browser. Contoh:

```env
APP_URL=http://192.168.0.1:8888

PUBLISHED_HTTP_PORT=8888
PUBLISHED_HTTPS_PORT=4444
TZ=Asia/Jakarta
```

Atau menggunakan hostname:

```env
APP_URL=http://server1:8888
```

Hostname tersebut harus dapat di-resolve oleh komputer pengguna. Port aplikasi juga harus diizinkan oleh firewall.

### Keterangan variable

| Variable | Fungsi |
|---|---|
| `APP_URL` | URL publik aplikasi yang digunakan Laravel dan URL asset. Sertakan hostname serta port. |
| `PUBLISHED_HTTP_PORT` | Port host untuk HTTP aplikasi. Dipetakan ke port `8080` di container `app`. |
| `PUBLISHED_HTTPS_PORT` | Port host untuk HTTPS aplikasi. Dipetakan ke port `8443` di container `app`. |
| `TZ` | Timezone container aplikasi dan PostgreSQL. Default Compose: `Asia/Jakarta`. |
| `APP_UID` | UID user container. Opsional; biasanya tidak diperlukan untuk image immutable. |
| `APP_GID` | GID group container. Opsional; digunakan bersama `APP_UID`. |
| `DB_CONNECTION` | Driver database Laravel. Untuk Compose: `pgsql`. |
| `DB_HOST` | Host database dari dalam container app. Gunakan `db`, bukan `localhost`. |
| `DB_PORT` | Port PostgreSQL dari dalam network Compose. Gunakan `5432`. |
| `DB_DATABASE` | Nama database PostgreSQL. Wajib diisi oleh Compose. |
| `DB_USERNAME` | Username PostgreSQL. Wajib diisi oleh Compose. |
| `DB_PASSWORD` | Password PostgreSQL. Wajib diisi oleh Compose. |

`DB_DATABASE`, `DB_USERNAME`, dan `DB_PASSWORD` wajib tersedia. Compose akan berhenti dengan error jika salah satunya kosong.

`ASSET_URL` tidak perlu ditambahkan ke `.env` karena `config/app.php` menggunakan `APP_URL` sebagai fallback. Isi hanya bila asset disajikan dari URL terpisah.

### `.env.example`

Tambahkan variable yang sama ke `.env.example` agar user berikutnya tahu konfigurasi yang diperlukan. Jangan menyimpan password production asli di `.env.example`.

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

## Menjalankan production

Build dan jalankan stack:

```bash
docker compose up -d --build
```

Proses build menginstal dependency PHP, membangun asset frontend, lalu menyalin hasilnya ke image aplikasi. `.dockerignore` mengecualikan `.env`, dependency hasil install lokal, log, dan hasil asset lama agar image dibangun dari source yang bersih.

Buka URL yang ada pada `APP_URL`, bukan selalu `localhost`. Contoh:

```text
http://192.168.0.1:8888
```

Container `app` menunggu PostgreSQL sehat sebelum dijalankan. Contoh ini menjalankan migration saat boot melalui `RUN_MIGRATIONS_ON_BOOT=true`; gunakan hanya untuk single instance. Pada deployment multi-replica, jalankan migration job terpisah sebelum service aplikasi.

Image tidak membawa `.env`. Compose me-mount `.env` sebagai file read-only, sedangkan source code tetap berada di dalam image. Named volume `storage` menyimpan file runtime seperti upload, dan volume `db` menyimpan data PostgreSQL.

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

Jika database belum healthy, `app` belum dijalankan. Jika build gagal, jalankan kembali tanpa detached mode untuk melihat error lengkap:

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

Itu berarti `.env` belum berisi konfigurasi database yang diperlukan.
