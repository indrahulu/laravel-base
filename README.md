# indrahulu/laravel-base

Base image Laravel production-ready berbasis `php-fpm-bookworm` dengan:

- `nginx`, `php-fpm`, `supervisor`, `composer`
- Extensions: `opcache`, `gd`, `imagick`, `sockets`, `redis`
- 4 runtime roles: `web`, `worker`, `scheduler`, `all`
- Self-signed SSL certificate (sudah di-generate di `docker/ssl/`)
- Dukungan multi versi PHP: `8.2`, `8.3`, `8.4`, `8.5`

Image ini dibangun dari [https://github.com/indrahulu/laravel-base](https://github.com/indrahulu/laravel-base).

Image final hasil build dan push bisa diakses di:

- https://hub.docker.com/r/indrahulu/laravel-base

## Image Tags

| Tag | Deskripsi | Push Otomatis |
|-----|-----------|:----------:|
| `php8.5` | Latest per versi PHP | ✅ |
| `php8.5-v1.2.3` | Versioned, immutable | ❌ |
| `php8.5-nightly` | Nightly build | ✅ |
| `php8.4` | Latest per versi PHP | ✅ |
| `php8.4-v1.2.3` | Versioned, immutable | ❌ |
| `php8.4-nightly` | Nightly build | ✅ |
| `php8.3` | Latest per versi PHP | ✅ |
| `php8.3-v1.2.3` | Versioned, immutable | ❌ |
| `php8.3-nightly` | Nightly build | ✅ |
| `php8.2` | Latest per versi PHP | ✅ |
| `php8.2-v1.2.3` | Versioned, immutable | ❌ |
| `php8.2-nightly` | Nightly build | ✅ |

Contoh pull:

```bash
docker pull indrahulu/laravel-base:php8.5
docker pull indrahulu/laravel-base:php8.5-v1.0.0
docker pull indrahulu/laravel-base:php8.5-nightly
docker pull indrahulu/laravel-base:php8.4
docker pull indrahulu/laravel-base:php8.4-v1.0.0
docker pull indrahulu/laravel-base:php8.4-nightly
```

## Lifecycle Rilis

Workflow CI menjalankan build dan smoke test untuk PHP 8.2, 8.3, 8.4, dan 8.5 sebelum image dipublikasikan. Jalur publikasi ditentukan oleh pemicu berikut:

| Pemicu | Build dan smoke test | Tag yang di-push |
|--------|----------------------|------------------|
| Pull request ke `master` | Ya | Tidak ada |
| Push ke `master` | Ya | Tidak ada |
| `workflow_dispatch` | Ya | `php<versi>` (latest per versi) |
| Jadwal harian | Ya | `php<versi>-nightly` |
| Push tag `v*` | Ya | `php<versi>-v<versi>` (versioned) dan `php<versi>` (latest), lalu cleanup tag lama |

Release dilakukan dengan membuat tag Git seperti `v1.1.0`. Tag versioned digunakan untuk deployment yang immutable, sedangkan tag `php<versi>` mengikuti release terbaru. Gunakan tag `-nightly` hanya untuk validasi build harian, bukan deployment produksi. Perubahan README saja tidak memicu workflow karena CI mengabaikan path tersebut.

`workflow_dispatch` berguna untuk mem-push ulang tag latest secara manual setelah build dan smoke test lulus. Pull request dan push branch hanya memvalidasi perubahan; keduanya tidak mengubah Docker Hub.

## Build

Versi PHP ditentukan secara eksplisit via `--build-arg`. Build tanpa menentukan versi akan gagal.

```bash
docker build --build-arg PHP_VERSION=8.5 -t indrahulu/laravel-base:php8.5 .
docker build --build-arg PHP_VERSION=8.4 -t indrahulu/laravel-base:php8.4 .
docker build --build-arg PHP_VERSION=8.3 -t indrahulu/laravel-base:php8.3 .
docker build --build-arg PHP_VERSION=8.2 -t indrahulu/laravel-base:php8.2 .
```

## Smoke Test

Smoke test menjalankan stack Compose dengan container untuk setiap role dan cabang konfigurasi penting, lalu memverifikasi:

- Container `running` dan `healthy`
- Strict health path untuk role `web` dan `all`
- PHP version sesuai ekspektasi
- Process `queue:work` dan `schedule:work` aktif
- Batas upload PHP dan Nginx
- HTTP dan HTTPS endpoint merespons

Container logs otomatis di-dump saat test selesai (sukses atau gagal).

```bash
IMAGE=indrahulu/laravel-base:php8.5 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.4 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.3 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.2 bash tests/smoke-test.sh
```

Dengan verifikasi PHP version:

```bash
IMAGE=indrahulu/laravel-base:php8.5 EXPECTED_PHP_VERSION=8.5 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.4 EXPECTED_PHP_VERSION=8.4 bash tests/smoke-test.sh
```

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `IMAGE` | *(wajib)* | Image yang akan di-test |
| `EXPECTED_PHP_VERSION` | *(kosong = skip)* | Verifikasi PHP version di container |
| `WEB_HTTP_PORT` | `18080` | Port HTTP untuk role `web` |
| `WEB_HTTPS_PORT` | `18443` | Port HTTPS untuk role `web` |
| `ALL_HTTP_PORT` | `28080` | Port HTTP untuk role `all` |
| `ALL_HTTPS_PORT` | `28443` | Port HTTPS untuk role `all` |

## Usage

### Runtime Roles

Diatur via environment variable `APP_ROLE`:

| Role | Proses yang Berjalan |
|------|---------------------|
| `web` | `php-fpm` + `nginx` |
| `worker` | `php artisan queue:work` |
| `scheduler` | `php artisan schedule:work` |
| `all` | Semua proses via `supervisor` |

Queue role `worker` menjalankan tepat satu proses `queue:work` per container. Untuk meningkatkan throughput, jalankan beberapa replica container `worker`; `QUEUE_CONCURRENCY` tidak lagi digunakan dan nilai lama akan diabaikan. Role `all` juga menjalankan tepat satu queue worker saat `QUEUE_ENABLED=true`.

Role `scheduler` sebaiknya dijalankan sebagai satu replica per deployment. Jika membutuhkan lebih dari satu replica, aplikasi harus memakai distributed lock Laravel seperti `onOneServer` agar jadwal tidak berjalan ganda.

### Bind Mount

Pola ini cocok untuk development atau staging. Source code di-mount langsung dari host ke container.

**Single container (semua role):**

```yaml
services:
  app:
    image: indrahulu/laravel-base:php8.5
    ports:
      - "8080:8080"
      - "8443:8443"
    environment:
      APP_ROLE: all
      APP_UID: "1000"
      APP_GID: "1000"
    volumes:
      - ./your-laravel-app:/var/www/html
```

**Split roles (production-like):**

```yaml
services:
  web:
    image: indrahulu/laravel-base:php8.5
    ports:
      - "8080:8080"
      - "8443:8443"
    environment:
      APP_ROLE: web
    volumes:
      - ./your-laravel-app:/var/www/html

  worker:
    image: indrahulu/laravel-base:php8.5
    environment:
      APP_ROLE: worker
    volumes:
      - ./your-laravel-app:/var/www/html

  scheduler:
    image: indrahulu/laravel-base:php8.5
    environment:
      APP_ROLE: scheduler
    volumes:
      - ./your-laravel-app:/var/www/html
```

### Build Immutable Image

Pola ini cocok untuk production. Source code di-COPY ke dalam image, menghasilkan image yang immutable dan reproducible.

**Dockerfile aplikasi:**

```dockerfile
FROM indrahulu/laravel-base:php8.5

COPY --chown=www-data:www-data . /var/www/html

RUN composer install --no-dev --optimize-autoloader \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache
```

Build:

```bash
docker build -t yourorg/your-laravel-app:v1 .
```

**Single container:**

```yaml
services:
  app:
    image: yourorg/your-laravel-app:v1
    ports:
      - "8080:8080"
      - "8443:8443"
    environment:
      APP_ROLE: all
```

**Split roles:**

```yaml
services:
  web:
    image: yourorg/your-laravel-app:v1
    ports:
      - "8080:8080"
      - "8443:8443"
    environment:
      APP_ROLE: web

  worker:
    image: yourorg/your-laravel-app:v1
    environment:
      APP_ROLE: worker

  scheduler:
    image: yourorg/your-laravel-app:v1
    environment:
      APP_ROLE: scheduler
```

### Override UID/GID

Default-nya container memakai user `www-data`. Untuk bind mount di Linux host, Anda bisa menyelaraskan UID/GID container dengan user host agar permission file konsisten:

```yaml
environment:
  APP_UID: "1000"
  APP_GID: "1000"
```

Perilaku:

- Jika `APP_UID` dan/atau `APP_GID` diisi, entrypoint akan mengubah UID/GID `www-data` saat startup
- Hanya merapikan permission `${APP_ROOT}/storage` dan `${APP_ROOT}/bootstrap/cache`
- Tidak otomatis `chown` seluruh source tree yang di-mount (sengaja, agar bind mount tidak kena `chown -R` besar)

Untuk immutable image (`COPY`), UID/GID override biasanya tidak diperlukan.

### Boot Hooks

Boot hook dijalankan sebelum service utama start. Default-nya non-aktif dan hanya relevan untuk role `web` dan `all`.

| Flag | Command |
|------|---------|
| `RUN_OPTIMIZE_CLEAR_ON_BOOT=true` | `php artisan optimize:clear` |
| `RUN_STORAGE_LINK_ON_BOOT=true` | `php artisan storage:link` |
| `RUN_MIGRATIONS_ON_BOOT=true` | `php artisan migrate --force` |
| `RUN_SEEDERS_ON_BOOT=true` | `php artisan db:seed --force` |
| `RUN_QUEUE_RESTART_ON_BOOT=true` | `php artisan queue:restart` |

Urutan eksekusi sesuai tabel di atas. Jika command gagal, image mencetak warning dan tetap melanjutkan startup.

```yaml
environment:
  APP_ROLE: all
  RUN_OPTIMIZE_CLEAR_ON_BOOT: "true"
  RUN_STORAGE_LINK_ON_BOOT: "true"
  RUN_MIGRATIONS_ON_BOOT: "true"
```

### Environment Variables

**App**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `APP_ROLE` | `web` | Runtime role: `web`, `worker`, `scheduler`, `all` |
| `APP_ROOT` | `/var/www/html` | Path ke Laravel application root |
| `APP_UID` | *(kosong)* | Override UID `www-data` |
| `APP_GID` | *(kosong)* | Override GID `www-data` |
| `APP_HEALTHCHECK_PATH` | *(kosong)* | Optional absolute path untuk HTTP application health probe |
| `TZ` | `Asia/Jakarta` | IANA timezone runtime; dapat di-override tanpa rebuild image |

Entrypoint memvalidasi role, boolean flag, path absolut, UID/GID numerik, nilai PHP-FPM numerik, serta opsi queue numerik sebelum service dimulai. `TZ` harus berupa IANA timezone yang tersedia di image.

Docker healthcheck tetap memeriksa proses internal. Untuk role `web` dan `all`, HTTP application probe hanya dijalankan jika `APP_HEALTHCHECK_PATH` diisi; nilainya diperiksa secara strict tanpa fallback ke `/`. Jika kosong atau tidak diset, probe HTTP dilewati. Untuk menonaktifkan seluruh Docker healthcheck, override pada deployment dengan `healthcheck: disable: true`.

**PHP**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `PHP_MEMORY_LIMIT` | `512M` | PHP memory limit |
| `PHP_OPCACHE_ENABLE` | `true` | Aktifkan opcache |

PHP menetapkan ceiling `upload_max_filesize=500G` dan `post_max_size=501G`. Keduanya bukan environment variable; limit operasional ditentukan oleh Nginx.

**PHP-FPM**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `PHP_FPM_PM_MAX_CHILDREN` | `20` | Max worker processes |
| `PHP_FPM_PM_START_SERVERS` | `4` | Jumlah worker saat start |
| `PHP_FPM_PM_MIN_SPARE_SERVERS` | `2` | Min idle workers |
| `PHP_FPM_PM_MAX_SPARE_SERVERS` | `6` | Max idle workers |
| `PHP_FPM_PM_MAX_REQUESTS` | `500` | Max request per worker sebelum restart |

**Nginx**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `NGINX_CLIENT_MAX_BODY_SIZE` | `5m` | Limit body request Nginx; dapat dinaikkan hingga ceiling PHP |
| `SSL_SELF_SIGNED_ENABLE` | `true` | Aktifkan HTTPS dengan self-signed cert |

Default upload efektif adalah `5 MB` dari Nginx. Untuk upload lebih besar, override `NGINX_CLIENT_MAX_BODY_SIZE` secara eksplisit, maksimal hingga ceiling PHP `500G`/`501G`. Upload besar tetap bergantung pada reverse proxy, timeout, temporary disk, dan storage aplikasi.

**Queue**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `QUEUE_ENABLED` | `true` | Aktifkan queue worker |
| `QUEUE_CONNECTION` | `database` | Laravel queue connection |
| `QUEUE_NAMES` | `default` | Queue names (comma-separated) |
| `QUEUE_SLEEP` | `3` | Detik tidur jika tidak ada job |
| `QUEUE_TRIES` | `3` | Max retry per job |
| `QUEUE_TIMEOUT` | `90` | Detik timeout per job |
| `QUEUE_MAX_JOBS` | `0` | Max jobs per worker (0 = unlimited) |
| `QUEUE_MAX_TIME` | `0` | Max waktu worker dalam detik (0 = unlimited) |
| `QUEUE_BACKOFF` | `0` | Detik delay antar retry |

**Boot Hooks**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `RUN_OPTIMIZE_CLEAR_ON_BOOT` | `false` | Jalankan `php artisan optimize:clear` |
| `RUN_STORAGE_LINK_ON_BOOT` | `false` | Jalankan `php artisan storage:link` |
| `RUN_MIGRATIONS_ON_BOOT` | `false` | Jalankan `php artisan migrate --force` |
| `RUN_SEEDERS_ON_BOOT` | `false` | Jalankan `php artisan db:seed --force` |
| `RUN_QUEUE_RESTART_ON_BOOT` | `false` | Jalankan `php artisan queue:restart` |

## Migration Notes

Bagian ini diperlukan saat memindahkan aplikasi dari image atau konfigurasi lama.

### Health check menjadi optional dan strict

`APP_HEALTHCHECK_PATH` sekarang opsional. Jika tidak diset atau bernilai kosong, role `web` dan `all` tetap memeriksa Supervisor, PHP-FPM, dan Nginx, tetapi tidak melakukan HTTP application probe.

Jika path diisi, hanya endpoint tersebut yang diperiksa; fallback otomatis ke `/` tidak ada. Aplikasi lama yang sebelumnya mengandalkan default `/up` harus menetapkannya secara eksplisit agar HTTP probe tetap aktif:

```yaml
environment:
  APP_HEALTHCHECK_PATH: /up
```

Aplikasi yang hanya memiliki route `/` dapat menetapkan:

```yaml
environment:
  APP_HEALTHCHECK_PATH: /
```

Jika path yang dipilih mengembalikan status HTTP non-2xx atau tidak dapat diakses, container menjadi `unhealthy`. Untuk menonaktifkan seluruh Docker healthcheck, bukan hanya HTTP probe, gunakan konfigurasi deployment berikut:

```yaml
healthcheck:
  disable: true
```

### Queue tidak lagi memakai internal concurrency

`QUEUE_CONCURRENCY` sudah dihapus dari kontrak image dan tidak lagi membuat beberapa proses `queue:work` dalam satu container. Hapus variable tersebut dari deployment lama. Untuk menaikkan throughput, scale replica role `worker`, misalnya:

```bash
docker compose up -d --scale worker=3 worker
```

Setiap replica menjalankan tepat satu worker. Jalankan scheduler sebagai satu replica; bila harus menjalankan lebih dari satu, aplikasi wajib memakai distributed lock Laravel seperti `onOneServer` agar jadwal tidak diproses ganda.

### Default upload turun menjadi 5 MB

Default operasional Nginx sekarang `NGINX_CLIENT_MAX_BODY_SIZE=5m`, sehingga request upload yang tidak dikonfigurasi ulang dibatasi sekitar 5 MB. PHP menyediakan ceiling `upload_max_filesize=500G` dan `post_max_size=501G`, tetapi limit efektif juga bergantung pada reverse proxy, timeout, temporary disk, dan storage aplikasi.

Untuk aplikasi yang memang membutuhkan upload lebih besar, override limit Nginx secara eksplisit dan pastikan seluruh proxy di depannya memakai limit yang sama:

```yaml
environment:
  NGINX_CLIENT_MAX_BODY_SIZE: 100m
```

### Timezone runtime

Default timezone adalah `Asia/Jakarta`. `TZ` dapat diubah ke nama timezone IANA yang tersedia di image; entrypoint menerapkannya saat container start. Pastikan nilai `TZ` konsisten pada seluruh role aplikasi.
