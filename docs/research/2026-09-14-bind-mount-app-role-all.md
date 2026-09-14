# Riset: `APP_ROLE=all` dengan bind mount

## Kesimpulan

Bisa. Bind mount hanya menentukan dari mana source code Laravel dibaca; bind mount tidak membatasi `APP_ROLE`. Image ini memang mendukung `APP_ROLE=all` dengan source code yang di-mount ke `/var/www/html`.

`all` menjalankan proses berikut dalam satu container:

- PHP-FPM
- Nginx
- Laravel scheduler (`php artisan schedule:work`)
- Satu queue worker jika `QUEUE_ENABLED=true`

## Bukti dari repository

- `docker/bin/entrypoint.sh:275-285` membuat konfigurasi Supervisor untuk PHP-FPM, Nginx, scheduler, dan queue worker opsional saat role `all`.
- `docker/bin/entrypoint.sh:294-303` memvalidasi `artisan` dan `public/index.php` dari `APP_ROOT`. Ini kompatibel dengan source code yang di-bind mount ke `/var/www/html`.
- `Dockerfile:6-7` menetapkan `APP_ROOT=/var/www/html` dan default role `web`; keduanya dapat dioverride melalui Compose.
- `README.md:129-144` sudah mendokumentasikan single-container bind mount menggunakan `APP_ROLE: all`.
- `tests/docker-compose-smoke.yml:32-42` menguji role `all` dengan file aplikasi yang di-bind mount. Smoke test juga memiliki service `all-health-failing` untuk memverifikasi healthcheck role tersebut.

## Syarat saat memakai `all`

1. Bind mount harus berisi minimal:
   - `public/index.php`
   - `artisan`
   - dependency Laravel, terutama `vendor/autoload.php`
2. `QUEUE_ENABLED=true` adalah default image. Karena default `QUEUE_CONNECTION=database`, aplikasi harus memiliki konfigurasi database dan queue yang siap jika queue worker diaktifkan. Jika tabel `jobs` belum ada, Laravel dapat melaporkan exception saat polling queue dan tetap membiarkan worker hidup; status container belum tentu berubah menjadi `unhealthy` karena healthcheck memeriksa proses, bukan kesiapan schema.
3. Jika hanya membutuhkan web dan scheduler tanpa queue, gunakan `QUEUE_ENABLED=false`.
4. `APP_HEALTHCHECK_PATH` tetap opsional. Jika diisi, endpoint tersebut harus merespons sukses; jika kosong, healthcheck hanya memeriksa proses internal.
5. `APP_UID` dan `APP_GID` dapat disamakan dengan user host agar `storage` dan `bootstrap/cache` pada bind mount tidak bermasalah permission-nya.

Image tidak menjalankan `composer install` otomatis saat startup. Untuk bind mount, jalankan dependency installation di host atau sediakan `vendor` melalui workflow development yang digunakan.

## Trade-off

### Cocok untuk development

`APP_ROLE=all` praktis karena satu container langsung menyediakan web, scheduler, dan queue. Ini juga sesuai dengan Docker guidance bahwa bind mounts cocok untuk berbagi source code dari host ke container.

### Kurang cocok untuk production

Semua proses memiliki lifecycle dan kebutuhan scaling berbeda:

- Web biasanya perlu di-scale berdasarkan traffic.
- Queue worker perlu di-scale berdasarkan beban job.
- Scheduler sebaiknya hanya satu replica kecuali aplikasi memakai distributed lock.

Jika semuanya memakai `APP_ROLE=all`, scaling web juga menggandakan scheduler dan queue worker. Karena itu pola split `web`, `worker`, dan `scheduler` lebih aman untuk staging/production.

## Rekomendasi

- Development sederhana: `APP_ROLE=all` dengan bind mount.
- Development tanpa queue backend: `APP_ROLE=all` dan `QUEUE_ENABLED=false`.
- Staging/production: bind mount tetap bisa digunakan, tetapi gunakan role terpisah agar scaling dan failure isolation jelas.
- Production immutable: gunakan image aplikasi hasil `COPY`, bukan bind mount.

## Sumber

1. Docker Docs, **Bind mounts** — menjelaskan bahwa bind mount memasukkan file/directory host ke container dan cocok untuk berbagi source code development: <https://docs.docker.com/engine/storage/bind-mounts/>
2. Laravel Docs, **Running the Queue Worker** — dokumentasi resmi perintah `php artisan queue:work`: <https://laravel.com/docs/12.x/queues#running-the-queue-worker>
3. Laravel Docs, **Running the Scheduler Locally** — dokumentasi resmi perintah `php artisan schedule:work`: <https://laravel.com/docs/12.x/scheduling#running-the-scheduler-locally>
4. Laravel application skeleton, default `.env.example` (SQLite, database session/cache/queue): <https://github.com/laravel/laravel/blob/12.x/.env.example>
5. Laravel framework source, `Worker::getNextJob()` yang melaporkan exception polling queue lalu tidur kembali: <https://github.com/laravel/framework/blob/12.x/src/Illuminate/Queue/Worker.php>
6. Repository source, `docker/bin/entrypoint.sh`, `Dockerfile`, `README.md`, dan `tests/docker-compose-smoke.yml`.
