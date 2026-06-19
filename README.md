# indrahulu/laravel-base:php8.3

Base image Laravel modern berbasis `php:8.3-fpm-bookworm` dengan:

- `nginx`
- `php-fpm`
- `supervisor`
- `composer`
- `opcache`
- `gd`
- `imagick`
- `sockets`
- `redis` PHP extension
- role `web`, `worker`, `scheduler`, `all`
- HTTP `8080` dan HTTPS `8443` dengan self-signed cert

## Runtime Roles

- `APP_ROLE=web`: `php-fpm + nginx`
- `APP_ROLE=worker`: `php artisan queue:work`
- `APP_ROLE=scheduler`: `php artisan schedule:work`
- `APP_ROLE=all`: semua proses aktif lewat `supervisor`

## Environment Variables

- `APP_ROLE`
- `APP_ROOT`
- `APP_UID`
- `APP_GID`
- `APP_HEALTHCHECK_PATH`
- `SSL_SELF_SIGNED_ENABLE`
- `PHP_MEMORY_LIMIT`
- `PHP_OPCACHE_ENABLE`
- `NGINX_CLIENT_MAX_BODY_SIZE`
- `PHP_FPM_PM_MAX_CHILDREN`
- `PHP_FPM_PM_START_SERVERS`
- `PHP_FPM_PM_MIN_SPARE_SERVERS`
- `PHP_FPM_PM_MAX_SPARE_SERVERS`
- `PHP_FPM_PM_MAX_REQUESTS`
- `RUN_OPTIMIZE_CLEAR_ON_BOOT`
- `RUN_STORAGE_LINK_ON_BOOT`
- `RUN_MIGRATIONS_ON_BOOT`
- `RUN_SEEDERS_ON_BOOT`
- `RUN_QUEUE_RESTART_ON_BOOT`
- `QUEUE_ENABLED`
- `QUEUE_CONNECTION`
- `QUEUE_NAMES`
- `QUEUE_SLEEP`
- `QUEUE_TRIES`
- `QUEUE_TIMEOUT`
- `QUEUE_MAX_JOBS`
- `QUEUE_MAX_TIME`
- `QUEUE_BACKOFF`
- `QUEUE_CONCURRENCY`

## Cron Build And Push

Script `scripts/cron-build-and-push.sh` membaca environment langsung, dan kalau ada file `.env` di root repo, file itu juga akan di-load otomatis.

Untuk konfigurasi lokal:

```bash
cp .env.example .env
```

Variabel yang dipakai oleh wrapper cron:

- `NTFY_URL`: endpoint ntfy tujuan, contoh `https://ntfy.sh/your-topic`
- `NTFY_TITLE`: judul notifikasi, default `laravel-base cron build and push`
- `LOCK_FILE`: file lock untuk mencegah dua job jalan bersamaan
- `NO_CACHE`: diteruskan ke `push-image.sh`, default `true`

Kalau `NTFY_URL` tidak diisi, script tetap berjalan normal tanpa notifikasi.

## Pakai Dengan Bind Mount

Pola ini cocok untuk development atau environment yang source code-nya ingin langsung di-mount ke container.

```bash
docker compose -f docker-compose-example.yml up -d
```

`docker-compose-example.yml` mengasumsikan source aplikasi Laravel tersedia di `./example-app` dan memakai image `indrahulu/laravel-base:php8.3` yang sudah ada di registry lokal atau Docker Hub. Ganti path volume itu sesuai struktur repo aplikasi Anda.

Contoh inti:

```yaml
services:
  app:
    image: indrahulu/laravel-base:php8.3
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

Untuk mode bind mount di Linux host, Anda biasanya juga ingin menyelaraskan UID/GID container dengan user host lewat `APP_UID` dan `APP_GID`.

## Pakai Dengan Application Image Sendiri

Pola ini lebih cocok untuk deployment yang ingin image aplikasi immutable.

Contoh `Dockerfile` aplikasi:

```dockerfile
FROM indrahulu/laravel-base:php8.3

COPY --chown=www-data:www-data . /var/www/html

RUN composer install --no-dev --optimize-autoloader \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache
```

Lalu build image aplikasi Anda:

```bash
docker build -t yourorg/your-laravel-app:latest .
```

Setelah itu jalankan image aplikasi tersebut seperti biasa, misalnya dengan `APP_ROLE=all` atau dipisah menjadi `web`, `worker`, dan `scheduler`.

## User And Permissions

Default-nya container memakai user internal `www-data` untuk proses PHP-FPM, sedangkan `supervisord` berjalan sebagai `root`.

- Untuk application image hasil `COPY`, pola ini biasanya sudah cukup.
- Untuk bind mount di Linux host, Anda bisa menyelaraskan UID/GID `www-data` dengan user host:

```yaml
environment:
  APP_UID: "1000"
  APP_GID: "1000"
```

Perilakunya:

- jika `APP_UID` dan/atau `APP_GID` diisi, entrypoint akan mengubah UID/GID `www-data` saat startup
- image ini tetap hanya merapikan permission `${APP_ROOT}/storage` dan `${APP_ROOT}/bootstrap/cache`
- image ini tidak otomatis `chown` seluruh source tree yang di-mount

Ini sengaja supaya bind mount tidak kena `chown -R` besar saat container start.

## Boot Hooks

Semua boot hook default-nya non-aktif dan hanya relevan untuk role `web` dan `all`.

- `RUN_OPTIMIZE_CLEAR_ON_BOOT=true` menjalankan `php artisan optimize:clear`
- `RUN_STORAGE_LINK_ON_BOOT=true` menjalankan `php artisan storage:link`
- `RUN_MIGRATIONS_ON_BOOT=true` menjalankan `php artisan migrate --force`
- `RUN_SEEDERS_ON_BOOT=true` menjalankan `php artisan db:seed --force`
- `RUN_QUEUE_RESTART_ON_BOOT=true` menjalankan `php artisan queue:restart`

Urutan eksekusi saat beberapa flag aktif:

1. `optimize:clear`
2. `storage:link`
3. `migrate --force`
4. `db:seed --force`
5. `queue:restart`

Jika command gagal, image ini akan mencetak warning dan tetap melanjutkan startup service utama.

Contoh:

```yaml
environment:
  APP_ROLE: all
  RUN_OPTIMIZE_CLEAR_ON_BOOT: "true"
  RUN_STORAGE_LINK_ON_BOOT: "true"
  RUN_MIGRATIONS_ON_BOOT: "true"
  RUN_SEEDERS_ON_BOOT: "true"
  RUN_QUEUE_RESTART_ON_BOOT: "true"
```
