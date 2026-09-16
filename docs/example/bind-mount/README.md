# Metode Bind Mount

Panduan ini menjelaskan cara menjalankan repository dalam dua mode dengan bind mount:

- **Development:** Docker Compose menjalankan Laravel, PostgreSQL, dan Vite dev server.
- **Production-like:** Docker Compose menjalankan Laravel dan PostgreSQL. Asset frontend dibuild oleh container Node sekali jalan.

Kedua file Compose harus diletakkan di root repository:

```text
docker-compose.dev.yml
docker-compose.prod.yml
```

Karena tidak ada file bernama `docker-compose.yml`, setiap perintah Compose harus menggunakan opsi `-f`.

## 1. Salin file Compose

Dapatkan file berikut, lalu copy ke root repository aplikasi:

```text
docker-compose.dev.yml
docker-compose.prod.yml
```

Repository harus berisi aplikasi Laravel dengan `composer.json` dan `package.json`. Mode production-like juga memerlukan `package-lock.json` karena memakai `npm ci`.

## 2. Sesuaikan `config/app.php`

Pastikan konfigurasi berikut ada. Jangan menambahkan key yang sama dua kali.

```php
'asset_url' => env('ASSET_URL'),
```

### Mengapa perlu diubah?

#### `asset_url`

Laravel memakai konfigurasi ini sebagai basis URL untuk `asset()` dan asset production yang dihasilkan oleh directive `@vite`.

Pada Compose, port internal container berbeda dengan port yang dilihat browser. Contohnya:

```text
Container app: 8080
Port host:     8888
```

Tanpa `asset_url`, Laravel dapat menghasilkan URL seperti:

```text
http://localhost/build/assets/app.css
```

Padahal URL yang benar adalah:

```text
http://localhost:8888/build/assets/app.css
```

Compose mengisi `ASSET_URL` berdasarkan `APP_URL`, sehingga asset memakai alamat yang dapat dijangkau browser.

## 3. Sesuaikan `vite.config.js`

Pertahankan plugin, input asset, dan opsi proyek yang sudah ada. Tambahkan `loadEnv`, callback `defineConfig`, serta konfigurasi `server` berikut ke konfigurasi Vite:

```js
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), '');
    const { PUBLISHED_VITE_PORT = '5173' } = env;
    const appUrl = new URL(env.APP_URL || 'http://localhost:8080');

    return {
        // plugins dan konfigurasi proyek yang sudah ada
        server: {
            host: '0.0.0.0',
            port: Number(PUBLISHED_VITE_PORT),
            strictPort: true,
            origin: `${appUrl.protocol}//${appUrl.hostname}:${PUBLISHED_VITE_PORT}`,
            cors: { origin: appUrl.origin },
            // pertahankan opsi server proyek yang sudah ada
        },
    };
});
```

### Mengapa perlu diubah?

#### `loadEnv`

Vite membaca `APP_URL` dan `PUBLISHED_VITE_PORT` dari `.env`. Prefix kosong pada `loadEnv(..., '')` diperlukan karena variable tersebut tidak diawali `VITE_`.

#### `host: '0.0.0.0'`

Container harus menerima koneksi dari luar container. Tanpa konfigurasi ini, Vite biasanya hanya listen pada `localhost` di dalam container.

#### `origin`

`origin` adalah alamat Vite yang ditulis Laravel ke `public/hot` saat mode dev.

Jika aplikasi diakses melalui:

```text
http://192.168.0.1:8888
```

dan `PUBLISHED_VITE_PORT=5555`, URL Vite harus menjadi:

```text
http://192.168.0.1:5555
```

Hostname diambil dari `APP_URL`, sedangkan port diambil dari `PUBLISHED_VITE_PORT`.

#### `cors`

Halaman Laravel dan Vite berada pada port berbeda, sehingga browser menganggapnya sebagai origin berbeda. CORS harus mengizinkan origin aplikasi, bukan origin Vite.

Contoh:

```text
Origin aplikasi: http://192.168.0.1:8888
Origin Vite:     http://192.168.0.1:5555
```

`server.port` dan mapping Compose harus memakai nilai yang sama:

```yaml
ports:
  - "${PUBLISHED_VITE_PORT:-5173}:${PUBLISHED_VITE_PORT:-5173}"
```

Dengan demikian, `PUBLISHED_VITE_PORT` adalah port Vite pada host dan di dalam container. `strictPort: true` membuat Vite berhenti dengan error jika port tersebut sudah dipakai, alih-alih diam-diam pindah ke port lain yang tidak dipublish Compose.

### Dampak perubahan

- Vite dapat diakses dari PC lain melalui jaringan.
- URL asset dev mengikuti alamat publik aplikasi.
- CSS, JavaScript, font, dan HMR tidak gagal karena hostname atau port yang salah.
- `npm run dev` tanpa Docker tetap menggunakan port dan URL yang berasal dari `.env`.

Mode dev Compose saat ini menggunakan HTTP. Jika `APP_URL` diubah menjadi HTTPS, Vite juga harus dikonfigurasi dengan TLS atau ditempatkan di belakang reverse proxy HTTPS.

## 4. Tambahkan variable ke `.env`

Pastikan `.env` sudah dibuat dari `.env.example` dan memiliki `APP_KEY` yang valid sebelum menjalankan Compose.

Gunakan contoh berikut untuk Docker Compose lokal:

```env
APP_URL=http://localhost:8080

PUBLISHED_HTTP_PORT=8080
PUBLISHED_HTTPS_PORT=8443
PUBLISHED_VITE_PORT=5173

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
PUBLISHED_VITE_PORT=5555
TZ=Asia/Jakarta
```

Atau menggunakan hostname:

```env
APP_URL=http://server1:8888
```

Hostname tersebut harus dapat di-resolve oleh komputer pengguna. Port aplikasi dan port Vite juga harus diizinkan oleh firewall.

### Keterangan variable

| Variable | Fungsi |
|---|---|
| `APP_URL` | URL publik aplikasi yang digunakan Laravel, Vite, dan URL asset. Sertakan hostname serta port. |
| `PUBLISHED_HTTP_PORT` | Port host untuk HTTP aplikasi. Dipetakan ke port `8080` di container `app`. |
| `PUBLISHED_HTTPS_PORT` | Port host untuk HTTPS aplikasi. Dipetakan ke port `8443` di container `app`. |
| `PUBLISHED_VITE_PORT` | Port Vite dev server pada host dan container. Nilai ini juga dipakai Vite saat dijalankan tanpa Docker. |
| `TZ` | Timezone semua container dan timezone Laravel. Default Compose: `Asia/Jakarta`. |
| `APP_UID` | UID user host untuk proses Laravel. Opsional; berguna pada Linux bila ada masalah permission bind mount. |
| `APP_GID` | GID group host untuk proses Laravel. Opsional; digunakan bersama `APP_UID`. |
| `DB_CONNECTION` | Driver database Laravel. Untuk Compose: `pgsql`. |
| `DB_HOST` | Host database dari dalam container app. Gunakan `db`, bukan `localhost`. |
| `DB_PORT` | Port PostgreSQL dari dalam network Compose. Gunakan `5432`. |
| `DB_DATABASE` | Nama database PostgreSQL. Wajib diisi oleh Compose. |
| `DB_USERNAME` | Username PostgreSQL. Wajib diisi oleh Compose. |
| `DB_PASSWORD` | Password PostgreSQL. Wajib diisi oleh Compose. |

`DB_DATABASE`, `DB_USERNAME`, dan `DB_PASSWORD` wajib tersedia. Compose akan berhenti dengan error jika salah satunya kosong.

Jika `storage` atau `bootstrap/cache` tidak dapat ditulis pada Linux, tambahkan UID dan GID user host ke `.env`:

```env
APP_UID=1000
APP_GID=1000
```

Gunakan hasil `id -u` dan `id -g`, bukan selalu `1000`.

`ASSET_URL` tidak perlu ditambahkan ke `.env` untuk konfigurasi ini. Kedua file Compose mengisi `ASSET_URL` dari nilai `APP_URL`.

### `.env.example`

Tambahkan variable yang sama ke `.env.example` agar user berikutnya tahu konfigurasi yang diperlukan. Jangan menyimpan password production asli di `.env.example`.

Contoh bagian Docker:

```env
APP_URL=http://localhost:8080

PUBLISHED_HTTP_PORT=8080
PUBLISHED_HTTPS_PORT=8443
PUBLISHED_VITE_PORT=5173

# Linux bind mount saja; sesuaikan dengan `id -u` dan `id -g`.
# APP_UID=1000
# APP_GID=1000

DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel
```

Untuk penggunaan Artisan atau Laravel Herd tanpa Docker, `DB_HOST` dan konfigurasi database mungkin perlu disesuaikan kembali dengan database lokal.

## Menjalankan mode development

Mode development memakai `docker-compose.dev.yml`. Service yang dijalankan:

- `app`: Laravel dan web server.
- `composer-install`: menginstal dependency PHP sebelum `app` dijalankan.
- `db`: PostgreSQL.
- `frontend`: Vite dev server dengan HMR.

Jalankan:

```bash
docker compose -f docker-compose.dev.yml up -d
```

Lihat log Vite:

```bash
docker compose -f docker-compose.dev.yml logs -f frontend
```

Buka URL yang ada pada `APP_URL`. Jika `APP_URL` memakai IP atau hostname server, buka URL tersebut dari browser; jangan menggantinya dengan `localhost`.

Vite berjalan pada `PUBLISHED_VITE_PORT` dan tidak perlu dibuka sebagai halaman utama. Jika `app` tetap berstatus `Created`, periksa `composer-install`:

```bash
docker compose -f docker-compose.dev.yml logs composer-install
```

## Menjalankan mode production-like

Mode ini memakai bind mount, membangun asset di checkout host, dan menjalankan migration saat boot. Gunakan untuk single instance atau pengujian yang menyerupai production, bukan deployment production multi-replica.

Mode production-like memakai `docker-compose.prod.yml`. Service `composer-install` dan `frontend-build` hanya berjalan selama proses persiapan:

```text
composer install --no-dev
npm ci
npm run build
```

Hasil build ditulis ke `public/build`. File `public/hot` juga dihapus agar Laravel tidak mencoba memakai Vite dev server. `app` menunggu kedua service selesai dengan sukses.

Jalankan:

```bash
docker compose -f docker-compose.prod.yml up -d
```

Container `frontend-build` akan berstatus `Exited (0)` setelah build berhasil. Itu normal. Container `app` akan dijalankan setelah build selesai sukses.

Buka URL yang ada pada `APP_URL`, bukan selalu `localhost`. Contoh:

```text
http://192.168.0.1:8888
```

Mode production tidak membutuhkan Node.js atau npm di komputer host.

### Troubleshooting build production

`composer-install` dan `frontend-build` tidak memiliki healthcheck. Jika salah satunya gagal, `app` dapat tetap berstatus `Created` karena menunggu kondisi `service_completed_successfully`.

Periksa status dan log berikut:

```bash
docker compose -f docker-compose.prod.yml ps -a
docker compose -f docker-compose.prod.yml logs composer-install frontend-build
```

Status `Exited (137)` berarti proses build menerima `SIGKILL`, bukan dianggap tidak healthy. Periksa resource atau timeout Docker/host; build Tailwind pada bind mount Windows dapat memerlukan waktu lebih lama.

### Dampak `node_modules` host

Kedua Compose bind-mount seluruh repository. Karena itu `composer-install` membuat `vendor`, sedangkan `npm install` pada mode dev dan `npm ci` pada mode production membuat atau mengganti `node_modules` di komputer host.

Jangan menjalankan Composer atau npm di host dan di container secara bergantian pada folder checkout yang sama. Jika perlu kembali memakai dependency host atau berganti OS, hapus `vendor` dan/atau `node_modules`, lalu install ulang pada environment yang akan dipakai.

### Batas resource

`composer-install`, `frontend`, dan `frontend-build` masing-masing dibatasi hingga `0.75` CPU dan `1G` memory. Pada tiap mode, dua service persiapan dapat berjalan bersamaan; sediakan setidaknya `2G` memory Docker. Jika build berakhir `Exited (137)`, naikkan `deploy.resources.limits.memory` pada service yang gagal.

## Berpindah antara dev dan production

Jangan menjalankan kedua mode bersamaan karena keduanya memakai port aplikasi yang sama.

Dari dev ke production:

```bash
docker compose -f docker-compose.dev.yml down --remove-orphans
docker compose -f docker-compose.prod.yml up -d
```

Dari production ke dev:

```bash
docker compose -f docker-compose.prod.yml down --remove-orphans
docker compose -f docker-compose.dev.yml up -d
```

Jika nilai port atau `APP_URL` diubah, recreate container:

```bash
docker compose -f docker-compose.dev.yml up -d --force-recreate
```

Untuk production, jalankan kembali Compose production agar proses build dijalankan ulang:

```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate
```

## Pemeriksaan konfigurasi

Sebelum menjalankan container, validasi file Compose:

```bash
docker compose -f docker-compose.dev.yml config

docker compose -f docker-compose.prod.yml config
```

Jika variable database wajib belum diisi, Compose akan menampilkan error seperti:

```text
DB_DATABASE is required
```

Itu berarti `.env` belum berisi konfigurasi database yang diperlukan.
