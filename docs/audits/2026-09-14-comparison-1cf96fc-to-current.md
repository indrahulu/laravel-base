# Laporan Perubahan Image: `1cf96fc` → current

Laporan ini hanya mencatat perubahan yang memengaruhi kontrak image atau keputusan pengguna. Hal yang tidak berubah—termasuk pola dasar bind mount/immutable build, role yang tersedia, versi PHP, extension, port, dan workflow CI—tidak dibahas sebagai perubahan.

## Ringkasan perubahan yang perlu diperhatikan

| Area | Sebelum (`1cf96fc`) | Sesudah (`ce38d9a`) | Keputusan pengguna |
| --- | --- | --- | --- |
| Validasi konfigurasi | Beberapa nilai malformed diteruskan atau diperlakukan sebagai `false` | Path, boolean, timezone, PHP-FPM, dan queue numeric divalidasi saat startup | Audit nilai nonstandar pada manifest |
| Timezone | `TZ` custom belum diterapkan oleh entrypoint; PHP tetap Jakarta | `TZ` valid diterapkan ke OS dan PHP saat startup | Set `TZ` jika bukan `Asia/Jakarta` |
| Health check | Endpoint gagal dapat fallback ke `/`; `/up` menjadi default | HTTP probe optional; jika diisi, path strict tanpa fallback | Set path jika ingin HTTP probe; kosong berarti process-only |
| Queue | `QUEUE_CONCURRENCY` menentukan jumlah proses | Satu `queue:work` tetap per container | Hapus `QUEUE_CONCURRENCY`, scale replica |
| Upload | PHP/Nginx sekitar 64 MB | PHP ceiling 500G/501G; Nginx default 5 MB | Override Nginx jika upload >5 MB |
| Dokumentasi/test | Kontrak baru belum terdokumentasi dan belum diuji lengkap | README dan smoke test mencakup kontrak baru | Ikuti migration notes |

## 1. Validasi konfigurasi startup

### Perubahan

Entrypoint sekarang memvalidasi beberapa nilai sebelum service dimulai:

- `APP_ROOT` harus absolute path.
- `APP_HEALTHCHECK_PATH`, jika diisi, harus absolute path; nilai kosong berarti HTTP probe dilewati.
- `TZ` harus nama timezone IANA yang tersedia di image.
- Flag boolean harus tepat `true` atau `false`: `SSL_SELF_SIGNED_ENABLE`, `QUEUE_ENABLED`, `PHP_OPCACHE_ENABLE`, dan seluruh flag `RUN_*_ON_BOOT`.
- `PHP_FPM_PM_*` dan opsi queue seperti `QUEUE_SLEEP`, `QUEUE_TRIES`, `QUEUE_TIMEOUT`, `QUEUE_MAX_JOBS`, `QUEUE_MAX_TIME`, serta `QUEUE_BACKOFF` harus numeric.

### Sebelum

- Nilai boolean selain `true` umumnya diperlakukan sebagai kondisi false.
- Nilai numeric yang salah diteruskan ke template atau command dan bisa gagal lebih lambat.
- `APP_ROOT` atau health path relatif tidak ditolak di batas awal.

### Sesudah

Container berhenti lebih awal dengan pesan validasi yang jelas.

### Tindakan pengguna

Periksa manifest deployment yang memakai nilai seperti `1`, `yes`, string kosong, path relatif, atau angka dengan format nonnumeric. Ubah menjadi format yang diterima sebelum menggunakan image baru.

## 2. Timezone runtime

### Perubahan

`TZ` yang sebelumnya hanya menjadi nilai environment/base OS sekarang diterapkan kembali oleh entrypoint:

- `/etc/localtime` dan `/etc/timezone` diubah saat container start.
- PHP runtime menerima `date.timezone=${TZ}`.
- Default tetap `Asia/Jakarta`.

### Sebelum

Mengatur `TZ` ke timezone lain tidak menjamin OS dan PHP ikut berubah karena PHP masih memakai `Asia/Jakarta` secara statis.

### Sesudah

`TZ=Etc/UTC`, `TZ=Asia/Singapore`, dan timezone IANA valid lainnya berlaku tanpa rebuild base image.

### Tindakan pengguna

- Tidak ada perubahan jika memakai `Asia/Jakarta`.
- Jika memakai timezone lain, set `TZ` secara konsisten pada setiap service yang memakai image.
- Jangan memakai format seperti `UTC+7`; gunakan nama timezone IANA.

```yaml
environment:
  TZ: Asia/Singapore
```

## 3. Health check optional dan strict

### Perubahan

- `APP_HEALTHCHECK_PATH` tidak lagi memiliki default `/up`.
- Jika variable tidak diset atau kosong, `web` dan `all` hanya memeriksa proses internal: Supervisor, PHP-FPM, dan Nginx; HTTP application probe dilewati.
- Jika variable diisi, hanya endpoint tersebut yang diperiksa; fallback ke `/` tidak ada.
- Docker `HEALTHCHECK` tetap aktif secara default. Pengguna yang ingin menonaktifkan seluruh container healthcheck dapat memakai `healthcheck: disable: true` pada deployment.

### Sebelum

`APP_HEALTHCHECK_PATH` otomatis bernilai `/up`. Jika endpoint tersebut gagal, health check mencoba `/`, sehingga aplikasi lama dapat dilaporkan `healthy` berdasarkan endpoint yang tidak dipilih secara eksplisit.

### Sesudah

Deployment lama yang tidak menetapkan variable berubah menjadi process-only healthcheck. Deployment yang ingin mempertahankan HTTP probe `/up` harus menetapkannya secara eksplisit:

```yaml
environment:
  APP_HEALTHCHECK_PATH: /up
```

Untuk aplikasi yang memakai endpoint lain:

```yaml
environment:
  APP_HEALTHCHECK_PATH: /health
```

Path yang diisi harus absolute dan mengembalikan HTTP 2xx. Perubahan ini berlaku terutama pada role `web` dan `all`; `worker` dan `scheduler` tetap hanya memeriksa proses internal.

## 4. Queue worker dan scheduler

### Queue worker

#### Perubahan

- `QUEUE_CONCURRENCY` dihapus dari default image dan tidak lagi digunakan oleh Supervisor.
- Template Supervisor tidak lagi memakai `numprocs`.
- Setiap container `worker` atau `all` dengan queue aktif menjalankan tepat satu `queue:work`.
- Nama program Supervisor berubah dari pola `queue-worker_00` menjadi `queue-worker`.
- `all` dengan `QUEUE_ENABLED=false` tidak menjalankan queue worker.

#### Sebelum

`QUEUE_CONCURRENCY=3`, misalnya, membuat satu container menjalankan tiga proses queue worker.

#### Sesudah

`QUEUE_CONCURRENCY` yang masih dikirim deployment lama tidak berpengaruh. Throughput ditambah dengan replica container.

```bash
docker compose up -d --scale worker=3 worker
```

#### Tindakan pengguna

- Hapus `QUEUE_CONCURRENCY` dari Compose, Helm values, ConfigMap, Secret, dan dokumentasi internal.
- Ubah monitoring yang mencari nama `queue-worker_00` menjadi `queue-worker` atau `php artisan queue:work`.
- Untuk production, scale role `worker` terpisah agar tidak menggandakan web dan scheduler seperti pada role `all`.

### Scheduler

Tidak ada perubahan pada command scheduler. Perubahan dalam rentang ini adalah dokumentasi operasional: scheduler dianjurkan satu replica, atau memakai distributed lock Laravel seperti `onOneServer` jika lebih dari satu replica diperlukan.

## 5. Batas upload

### PHP

| Setting | Sebelum | Sesudah |
| --- | --- | --- |
| `upload_max_filesize` | `64M` | `500G` |
| `post_max_size` | `64M` | `501G` |

### Nginx

| Setting | Sebelum | Sesudah |
| --- | --- | --- |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `64m` | `5m` |
| `client_max_body_size` | `64m` | `5m` |

### Tindakan pengguna

- Upload tanpa konfigurasi tambahan sekarang efektif dibatasi sekitar 5 MB oleh Nginx.
- Jika membutuhkan upload lebih besar, override Nginx pada service `web` atau `all`:

```yaml
environment:
  NGINX_CLIENT_MAX_BODY_SIZE: 100m
```

- Sesuaikan juga reverse proxy, timeout, temporary disk, dan storage aplikasi.
- Ceiling PHP adalah 500G/501G; nilai Nginx di atas ceiling tersebut tidak membuat PHP menerima file lebih besar.

## 6. Tindakan berdasarkan packaging aplikasi

Perubahan kontrak yang sama berlaku untuk bind mount dan immutable build. Yang berbeda hanya tempat pengguna menerapkan perubahan tersebut.

| Perubahan | Bind mount | Immutable build |
| --- | --- | --- |
| `APP_HEALTHCHECK_PATH` | Set di Compose/manifest jika ingin HTTP probe; route berada pada source yang di-mount | Set di manifest jika ingin HTTP probe; jika menambah route, ubah source lalu rebuild image aplikasi |
| `TZ` | Set pada Compose/manifest tiap service | Set pada manifest, atau bake sebagai `ENV` lalu rebuild jika memang ingin menjadi default image |
| Hapus `QUEUE_CONCURRENCY` | Hapus dari Compose/manifest dan scale service `worker` | Hapus dari manifest/image config dan scale service `worker` |
| Upload >5 MB | Set `NGINX_CLIENT_MAX_BODY_SIZE` di Compose/manifest | Set di manifest; jika ditulis sebagai `ENV` di Dockerfile aplikasi, rebuild image aplikasi |
| Boolean/numeric baru | Perbaiki environment di Compose/manifest | Perbaiki environment di manifest atau Dockerfile aplikasi |

### Contoh bind mount sesudah migrasi

```yaml
services:
  web:
    image: indrahulu/laravel-base:php8.5
    environment:
      APP_ROLE: web
      # Opsional: tambahkan jika ingin HTTP application probe.
      APP_HEALTHCHECK_PATH: /up
      TZ: Asia/Jakarta
      NGINX_CLIENT_MAX_BODY_SIZE: 100m
    volumes:
      - ./app:/var/www/html

  worker:
    image: indrahulu/laravel-base:php8.5
    environment:
      APP_ROLE: worker
      TZ: Asia/Jakarta
    volumes:
      - ./app:/var/www/html
```

### Contoh immutable build sesudah migrasi

```dockerfile
FROM indrahulu/laravel-base:php8.5

COPY --chown=www-data:www-data . /var/www/html

# Opsional, hanya bila default aplikasi memang >5 MB.
ENV NGINX_CLIENT_MAX_BODY_SIZE=100m
```

Environment yang dapat berubah antar deployment sebaiknya tetap dikelola oleh manifest, bukan dibakar ke image.

## 7. Dokumentasi dan test yang berubah

- README menambahkan lifecycle release/push image, termasuk branch, manual dispatch, nightly, dan release tag.
- README menambahkan migration notes untuk health strict, queue replica, scheduler, dan upload default 5 MB.
- Smoke test sekarang memverifikasi validasi invalid config, timezone override, health strict, jumlah queue worker, queue nonaktif pada `all`, serta limit PHP/Nginx.

Perubahan `.agents/`, `AGENTS.md`, dan berkas audit adalah tooling/dokumentasi repository dan tidak mengubah image yang dijalankan pengguna.

## Checklist migrasi

- [ ] Jika ingin HTTP application probe, pastikan endpoint yang dipilih mengembalikan HTTP 2xx.
- [ ] Set `APP_HEALTHCHECK_PATH` eksplisit jika ingin mempertahankan probe `/up` atau memakai path lain.
- [ ] Hapus `QUEUE_CONCURRENCY`.
- [ ] Scale `worker` dengan replica container.
- [ ] Audit monitoring dari `queue-worker_00` ke `queue-worker`.
- [ ] Set `TZ` jika bukan `Asia/Jakarta`.
- [ ] Audit boolean dan numeric environment agar formatnya valid.
- [ ] Set `NGINX_CLIENT_MAX_BODY_SIZE` jika upload melebihi 5 MB.
- [ ] Sesuaikan proxy, timeout, disk, dan storage untuk upload besar.
- [ ] Jalankan smoke test atau deployment staging sebelum mengganti image production.

## Sumber perubahan

- Baseline: `git show 1cf96fcdefc5026af9a8073d9721972df1013c00:<path>`
- Current: `HEAD` (the commit containing this report)
- `Dockerfile`
- `docker/bin/entrypoint.sh`
- `docker/bin/healthcheck.sh`
- `docker/nginx/nginx.conf`
- `docker/php/conf.d/zz-laravel-base.ini`
- `docker/supervisor/templates/queue-worker.conf.template`
- `tests/docker-compose-smoke.yml`
- `tests/smoke-test.sh`
- `tests/fixture-app-no-health/`
- `README.md`
