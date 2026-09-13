# Audit Docker Image: Build, penggunaan, dan konfigurasi runtime

**Tanggal:** 2026-09-13

**Status:** draf untuk ditinjau; belum ada perbaikan yang diterapkan atau di-commit.

**Metode:** audit statis atas `Dockerfile`, entrypoint dan script runtime, template Nginx/PHP-FPM/Supervisor, smoke test, workflow CI, serta `README.md`. Tidak mencakup benchmark, security/CVE scan, Docker Hub, atau menjalankan container.

## Ringkasan

Image ini memiliki satu jalur build dan empat jalur runtime yang jelas:

- `PHP_VERSION` memilih base image `php:<version>-fpm-bookworm`.
- CI menguji versi resmi 8.2, 8.3, 8.4, dan 8.5.
- `APP_ROLE` memilih `web`, `worker`, `scheduler`, atau `all`.
- Entrypoint menerjemahkan environment menjadi konfigurasi Nginx, PHP-FPM, Supervisor, dan perintah Laravel.

Struktur dasar konsisten dengan kontrak yang disepakati. Risiko utama berada pada kontrak konfigurasi: `TZ` tidak terdokumentasi sebagai environment publik, banyak nilai konfigurasi diteruskan tanpa validasi, dan beberapa perilaku health check/CI belum dijelaskan oleh README.

## Kontrak dan sumber kebenaran

| Area | Sumber perilaku aktual | Kontrak terdokumentasi |
| --- | --- | --- |
| Build image | `Dockerfile` | `README.md`, `.github/workflows/ci.yml` |
| Default runtime | `Dockerfile` `ENV` | `README.md` |
| Seleksi role dan konfigurasi hasil render | `docker/bin/entrypoint.sh` | `README.md` |
| Health check internal | `docker/bin/healthcheck.sh` | `README.md` |
| Validasi integrasi | `tests/docker-compose-smoke.yml`, `tests/smoke-test.sh` | `README.md`, CI |

Jika keduanya berbeda, code runtime adalah perilaku aktual, `Dockerfile` adalah sumber default, dan README/CI adalah kontrak yang harus diperbarui atau dipenuhi.

## Jalur build dan rilis

### Input build

`Dockerfile` menerima build argument wajib berikut:

| Input | Nilai/kontrak | Konsumen |
| --- | --- | --- |
| `PHP_VERSION` | Versi resmi yang diuji: 8.2, 8.3, 8.4, 8.5 | `FROM php:${PHP_VERSION}-fpm-bookworm` |
| `DEBIAN_FRONTEND` | `noninteractive`, build-only | `apt-get` |

`PHP_VERSION` tidak dibatasi secara eksplisit di Dockerfile. Nilai lain mungkin berhasil bila tag base image tersedia, tetapi berada di luar kontrak dukungan dan matriks CI.

### Tahapan build

1. Base image PHP-FPM Bookworm dipilih dari `PHP_VERSION`.
2. Paket OS untuk Nginx, Supervisor, Composer, build extension, dan runtime dipasang.
3. Extension PHP bawaan (`bcmath`, `curl`, `exif`, `gd`, `intl`, `mysqli`, `pcntl`, `pdo_mysql`, `pdo_pgsql`, `pgsql`, `sockets`, `zip`) serta PECL (`imagick`, `redis`) dibangun dan diaktifkan.
4. Dependensi build dibersihkan; package runtime `libpq5` dan `libzip4` dipertahankan.
5. Template konfigurasi, sertifikat self-signed, dan script runtime disalin ke image.
6. Image mengekspos port 8080/8443 dan memakai entrypoint + Supervisor sebagai proses utama.

### Jalur CI dan tag

| Pemicu | Build dan smoke test | Push Docker Hub |
| --- | --- | --- |
| Pull request / push ke `master` | Ya, untuk PHP 8.2–8.5 | Tidak |
| `workflow_dispatch` | Ya | Tag terbaru `php<versi>` |
| Jadwal harian | Ya | Tag `php<versi>-nightly` |
| Tag Git `v*` | Ya | Tag immutable `php<versi>-v<versi>` dan tag terbaru `php<versi>`; lalu cleanup tag lama |

## Jalur penggunaan image

| Jalur | Bentuk penggunaan | Konsekuensi startup |
| --- | --- | --- |
| Bind mount | Aplikasi Laravel dipasang ke `${APP_ROOT}`, umumnya `/var/www/html` | Entrypoint memeriksa file aplikasi dan menyesuaikan permission `storage` serta `bootstrap/cache`. Cocok untuk development/staging. |
| Immutable application image | Aplikasi di-`COPY` oleh Dockerfile turunan | Aplikasi dan cache dibangun bersama image. Tidak memerlukan override UID/GID pada umumnya. |
| Role mandiri | `APP_ROLE=web`, `worker`, atau `scheduler` | Satu fungsi deployment per container. |
| Role komposit | `APP_ROLE=all` | Menjalankan web dan scheduler, ditambah worker jika `QUEUE_ENABLED=true`. |

## Model runtime role

Entrypoint selalu re-exec sebagai root untuk setup, lalu menjalankan Supervisor sebagai `www-data`.

| Role | Prasyarat aplikasi | Program Supervisor | Health check |
| --- | --- | --- | --- |
| `web` | `public/index.php` | PHP-FPM + Nginx | Supervisor, PHP-FPM, Nginx, HTTP |
| `worker` | `artisan`; `QUEUE_ENABLED` harus `true` | Satu atau lebih `queue:work` | Supervisor + `queue-worker_00` |
| `scheduler` | `artisan` | `schedule:work` | Supervisor + scheduler |
| `all` | `artisan` dan `public/index.php` | PHP-FPM, Nginx, scheduler, serta worker bila diaktifkan | Semua program web/scheduler, HTTP, dan worker pertama bila queue aktif |

Urutan startup adalah: konfigurasi UID/GID → validasi aplikasi → permission aplikasi → boot hook → render Nginx/PHP-FPM → render Supervisor → siapkan direktori runtime → `gosu www-data supervisord`.

## Jejak environment publik

Semua `ENV` runtime dari Dockerfile diperlakukan sebagai konfigurasi image publik. `PHP_VERSION` adalah build argument dan variabel port/`IMAGE`/`EXPECTED_PHP_VERSION` pada smoke test adalah konfigurasi test harness, bukan konfigurasi image.

### Aplikasi dan health check

| Variabel | Default | Role | Consumer dan efek |
| --- | --- | --- | --- |
| `APP_ROOT` | `/var/www/html` | Semua | Validasi aplikasi, permission, lokasi Artisan, dan root Nginx. |
| `APP_ROLE` | `web` | Semua | Memilih program Supervisor, prasyarat aplikasi, boot hook yang diizinkan, dan health check. Nilai valid: `web`, `worker`, `scheduler`, `all`. |
| `APP_UID` | kosong | Semua | Entrypoint memvalidasi numerik dan mengubah UID `www-data`. |
| `APP_GID` | kosong | Semua | Entrypoint memvalidasi numerik dan mengubah GID `www-data`. |
| `APP_HEALTHCHECK_PATH` | `/up` | `web`, `all` | Target HTTP health check internal; bila gagal, script mencoba `/`. |

### Nginx, TLS, dan PHP

| Variabel | Default | Role | Consumer dan efek |
| --- | --- | --- | --- |
| `SSL_SELF_SIGNED_ENABLE` | `true` | `web`, `all` | Menambah virtual host HTTPS pada 8443 bila nilainya tepat `true`. |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `64m` | `web`, `all` | Dirender ke kedua template Nginx. |
| `PHP_MEMORY_LIMIT` | `512M` | Semua yang menjalankan PHP | Dirender ke `zz-runtime.ini`. |
| `PHP_OPCACHE_ENABLE` | `true` | Semua yang menjalankan PHP | Mengatur `opcache.enable`, `opcache.enable_cli`, timestamp, dan revalidate frequency pada `zz-runtime.ini`. Nilai selain tepat `true` menonaktifkan opcache. |
| `PHP_FPM_PM_MAX_CHILDREN` | `20` | `web`, `all` | Dirender sebagai `pm.max_children`. |
| `PHP_FPM_PM_START_SERVERS` | `4` | `web`, `all` | Dirender sebagai `pm.start_servers`. |
| `PHP_FPM_PM_MIN_SPARE_SERVERS` | `2` | `web`, `all` | Dirender sebagai `pm.min_spare_servers`. |
| `PHP_FPM_PM_MAX_SPARE_SERVERS` | `6` | `web`, `all` | Dirender sebagai `pm.max_spare_servers`. |
| `PHP_FPM_PM_MAX_REQUESTS` | `500` | `web`, `all` | Dirender sebagai `pm.max_requests`. |

### Queue dan scheduler

| Variabel | Default | Role | Consumer dan efek |
| --- | --- | --- | --- |
| `QUEUE_ENABLED` | `true` | `worker`, `all` | `worker` menolak nilai selain tepat `true`; `all` hanya merender worker bila tepat `true`. Tidak memengaruhi scheduler. |
| `QUEUE_CONNECTION` | `database` | `worker`, `all` | Diteruskan sebagai environment ke Laravel; bukan argumen script wrapper. |
| `QUEUE_NAMES` | `default` | `worker`, `all` | Menjadi `queue:work --queue`. |
| `QUEUE_CONCURRENCY` | `1` | `worker`, `all` | Dirender sebagai Supervisor `numprocs`. |
| `QUEUE_SLEEP` | `3` | `worker`, `all` | Menjadi `queue:work --sleep`. |
| `QUEUE_TRIES` | `3` | `worker`, `all` | Menjadi `queue:work --tries`. |
| `QUEUE_TIMEOUT` | `90` | `worker`, `all` | Menjadi `queue:work --timeout`. |
| `QUEUE_MAX_JOBS` | `0` | `worker`, `all` | Menambah `--max-jobs` hanya bila bukan `0`. |
| `QUEUE_MAX_TIME` | `0` | `worker`, `all` | Menambah `--max-time` hanya bila bukan `0`. |
| `QUEUE_BACKOFF` | `0` | `worker`, `all` | Menambah `--backoff` hanya bila bukan `0`. |

### Boot hook dan timezone

| Variabel | Default | Role | Consumer dan efek |
| --- | --- | --- | --- |
| `RUN_OPTIMIZE_CLEAR_ON_BOOT` | `false` | `web`, `all` | Menjalankan `artisan optimize:clear` bila tepat `true`; kegagalan hanya menghasilkan warning. |
| `RUN_STORAGE_LINK_ON_BOOT` | `false` | `web`, `all` | Menjalankan `artisan storage:link` bila tepat `true`; kegagalan hanya menghasilkan warning. |
| `RUN_MIGRATIONS_ON_BOOT` | `false` | `web`, `all` | Menjalankan `artisan migrate --force` bila tepat `true`; kegagalan hanya menghasilkan warning. |
| `RUN_SEEDERS_ON_BOOT` | `false` | `web`, `all` | Menjalankan `artisan db:seed --force` bila tepat `true`; kegagalan hanya menghasilkan warning. |
| `RUN_QUEUE_RESTART_ON_BOOT` | `false` | `web`, `all` | Menjalankan `artisan queue:restart` bila tepat `true`; kegagalan hanya menghasilkan warning. |
| `TZ` | `Asia/Jakarta` | Build image | Dipakai saat build untuk `/etc/localtime` dan `/etc/timezone`. Tidak dikonsumsi ulang oleh entrypoint; PHP juga menetapkan `date.timezone=Asia/Jakarta` secara statis. |

## Keputusan tinjauan

- Konfigurasi publik akan divalidasi saat startup: role, boolean flag, IANA timezone, absolute app/health path, UID/GID, nilai PHP-FPM, dan opsi queue numerik. Parser PHP, Nginx, dan Laravel tetap menjadi sumber validasi format khusus komponennya.
- `TZ` tetap default `Asia/Jakarta`, menerima IANA timezone valid, dan akan mengatur timezone OS serta PHP pada setiap jalur startup. Konfigurasi Laravel boleh menimpa timezone PHP.
- `APP_HEALTHCHECK_PATH` tetap opsional dengan default `/up`, tetapi probe akan strict terhadap path yang dipilih; tidak ada fallback ke `/`.
- Image akan mendukung tepat satu proses `queue:work` per container `worker` atau `all`. Skalabilitas queue dilakukan dengan replica container `worker`, bukan concurrency internal. Supervisor tetap mengelola lifecycle worker tersebut. `QUEUE_CONCURRENCY` dihapus tanpa compatibility check; konfigurasi lama yang masih mengirimkannya akan diabaikan dan migration notes mengarahkan pengguna ke replica worker.
- Smoke test akan diperluas untuk cabang konfigurasi yang diputuskan, dan README akan menjelaskan lifecycle rilis secara eksplisit, termasuk migrasi health check strict dan worker replica. Dokumentasi juga menyatakan scheduler hanya satu replica kecuali aplikasi memakai distributed lock Laravel seperti `onOneServer`.
- PHP memiliki ceiling upload tetap 500 GB (`upload_max_filesize`) dan 501 GB (`post_max_size`). Nginx tetap menjadi limit yang diatur pengguna; default `NGINX_CLIENT_MAX_BODY_SIZE` berubah dari 64m menjadi 5m. Jadi image default menerima hingga 5 MB, sedangkan pengguna dapat menaikkan limit Nginx hingga ceiling PHP 500 GB.

## Temuan dan rencana tindak lanjut

| Prioritas | Kategori | Temuan | Bukti | Rencana yang dapat dipilih kemudian |
| --- | --- | --- | --- | --- |
| P1 | `defect risk` | Parameter konfigurasi publik selain UID/GID tidak divalidasi sebelum dirender atau diteruskan. Nilai PHP-FPM atau opsi queue numerik yang salah baru gagal saat komponen tujuan memprosesnya. | `docker/bin/entrypoint.sh` hanya memvalidasi `APP_UID`/`APP_GID`; template memakai `envsubst`. | Validasi nilai sederhana di satu titik sebelum render; tambahkan test untuk nilai salah dan batas penting. |
| P2 | `documentation gap` | `TZ` adalah `ENV` image tetapi tidak ada pada README, sementara efeknya praktis build-time dan `date.timezone` PHP tetap hard-coded ke Jakarta. | `Dockerfile`, `docker/php/conf.d/zz-laravel-base.ini`, README tabel environment. | Putuskan apakah timezone adalah konfigurasi runtime publik. Dokumentasikan kontrak tersebut atau pindahkan menjadi build-only/default statis. |
| P2 | `documentation gap` | `APP_HEALTHCHECK_PATH` tidak bersifat strict: jika path gagal, health check mencoba `/`. README hanya menyebut path endpoint, tanpa fallback. | `docker/bin/healthcheck.sh:16-19`, README environment table. | Dokumentasikan fallback sebagai desain kompatibilitas, atau jadikan path yang dikonfigurasi sebagai satu-satunya probe. |
| P3 | `maintenance opportunity` | Smoke test mencakup keempat role dan default utama, tetapi belum mencakup cabang konfigurasi publik: TLS off, queue off pada `all`, boot hook, UID/GID, dan input konfigurasi invalid. | `tests/docker-compose-smoke.yml`, `tests/smoke-test.sh`. | Tambahkan case per cabang yang bernilai kontrak; pertahankan smoke test default tetap kecil. |
| P3 | `resolved by design` | Health check memeriksa satu worker pertama. Desain yang dipilih menetapkan satu `queue:work` per container, sehingga probe tersebut menjadi cukup. | `docker/bin/healthcheck.sh:31-37`, template Supervisor queue worker. | Hapus internal concurrency dan pertahankan satu target health check. |
| P3 | `documentation gap` | Tabel README “Push Otomatis” tidak menerangkan perbedaan antara build pada push `master`, push tag `v*`, jadwal harian, dan dispatch manual. | README bagian Image Tags; `.github/workflows/ci.yml`. | Tambahkan tabel lifecycle rilis seperti bagian jalur CI pada dokumen ini. |

## Hal yang konsisten

- Keempat role pada README, entrypoint, Supervisor, health check, dan smoke Compose memakai nama yang sama.
- `all` benar-benar merupakan role komposit sesuai kontrak.
- Boot hook dibatasi pada `web`/`all` dan kegagalannya tidak menghentikan startup, sesuai README.
- Semua env publik Dockerfile kecuali `TZ` tercantum dalam tabel README.
- CI membangun dan menjalankan smoke test untuk semua versi PHP resmi sebelum jalur rilis melakukan push.
- Jalur bind mount dan immutable image di README sesuai dengan validasi `APP_ROOT` di entrypoint.

## Urutan keputusan bila ingin memperbaiki

1. Putuskan kontrak validasi konfigurasi: nilai/rentang yang harus ditolak saat startup versus nilai yang dibiarkan Laravel/PHP-FPM/Supervisor tangani.
2. Putuskan kontrak `TZ` dan semantik fallback health check.
3. Tambahkan coverage smoke hanya untuk cabang kontrak yang dipilih.
4. Perbarui README dari perilaku final, termasuk lifecycle tag.

Tidak ada perubahan implementasi yang direkomendasikan untuk diterapkan sebelum keputusan tersebut disetujui.
