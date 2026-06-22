# indrahulu/laravel-base

Image ini dibangun dari [https://github.com/indrahulu/laravel-base](https://github.com/indrahulu/laravel-base). Base image Laravel production-ready berbasis `php-fpm-bookworm` dengan:

- `nginx`, `php-fpm`, `supervisor`, `composer`
- Extensions: `opcache`, `gd`, `imagick`, `sockets`, `redis`
- 4 runtime roles: `web`, `worker`, `scheduler`, `all`
- Self-signed SSL certificate (sudah di-generate di `docker/ssl/`)
- Dukungan multi versi PHP: `8.2`, `8.3`, `8.4`

## Image Tags

| Tag | Keterangan | Overwrite? |
|-----|-----------|:----------:|
| `php8.4` | Latest per versi PHP | ✅ |
| `php8.4-v1.2.3` | Versioned, immutable | ❌ |
| `php8.4-nightly` | Nightly build | ✅ |

Contoh pull:

```bash
docker pull indrahulu/laravel-base:php8.4
docker pull indrahulu/laravel-base:php8.4-v1.0.0
docker pull indrahulu/laravel-base:php8.4-nightly
```

## Build

Versi PHP ditentukan secara eksplisit via `--build-arg`. Build tanpa menentukan versi akan gagal.

```bash
docker build --build-arg PHP_VERSION=8.4 -t indrahulu/laravel-base:php8.4 .
docker build --build-arg PHP_VERSION=8.3 -t indrahulu/laravel-base:php8.3 .
docker build --build-arg PHP_VERSION=8.2 -t indrahulu/laravel-base:php8.2 .
```

## Smoke Test

Smoke test menjalankan 4 container (satu per role) dan memverifikasi:

- Container `running` dan `healthy`
- PHP version sesuai ekspektasi
- Process `queue:work` dan `schedule:work` aktif
- HTTP dan HTTPS endpoint merespons

Container logs otomatis di-dump saat test selesai (sukses atau gagal).

```bash
IMAGE=indrahulu/laravel-base:php8.4 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.3 bash tests/smoke-test.sh
IMAGE=indrahulu/laravel-base:php8.2 bash tests/smoke-test.sh
```

Dengan verifikasi PHP version:

```bash
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

### Bind Mount

Pola ini cocok untuk development atau staging. Source code di-mount langsung dari host ke container.

**Single container (semua role):**

```yaml
services:
  app:
    image: indrahulu/laravel-base:php8.4
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
    image: indrahulu/laravel-base:php8.4
    ports:
      - "8080:8080"
      - "8443:8443"
    environment:
      APP_ROLE: web
    volumes:
      - ./your-laravel-app:/var/www/html

  worker:
    image: indrahulu/laravel-base:php8.4
    environment:
      APP_ROLE: worker
      QUEUE_CONNECTION: redis
    volumes:
      - ./your-laravel-app:/var/www/html

  scheduler:
    image: indrahulu/laravel-base:php8.4
    environment:
      APP_ROLE: scheduler
    volumes:
      - ./your-laravel-app:/var/www/html
```

### Build Immutable Image

Pola ini cocok untuk production. Source code di-COPY ke dalam image, menghasilkan image yang immutable dan reproducible.

**Dockerfile aplikasi:**

```dockerfile
FROM indrahulu/laravel-base:php8.4

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
      QUEUE_CONNECTION: redis

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
| `APP_HEALTHCHECK_PATH` | `/up` | Path endpoint healthcheck |

**PHP**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `PHP_MEMORY_LIMIT` | `512M` | PHP memory limit |
| `PHP_OPCACHE_ENABLE` | `true` | Aktifkan opcache |

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
| `NGINX_CLIENT_MAX_BODY_SIZE` | `64m` | Max upload size |
| `SSL_SELF_SIGNED_ENABLE` | `true` | Aktifkan HTTPS dengan self-signed cert |

**Queue**

| Variable | Default | Deskripsi |
|----------|---------|----------|
| `QUEUE_ENABLED` | `true` | Aktifkan queue worker |
| `QUEUE_CONNECTION` | `redis` | Laravel queue connection |
| `QUEUE_NAMES` | `default` | Queue names (comma-separated) |
| `QUEUE_CONCURRENCY` | `1` | Jumlah concurrent queue workers |
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
