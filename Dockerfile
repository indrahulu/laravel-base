FROM php:8.3-fpm-bookworm

ARG DEBIAN_FRONTEND=noninteractive

ENV APP_ROOT=/var/www/html \
    APP_ROLE=web \
    APP_UID= \
    APP_GID= \
    SSL_SELF_SIGNED_ENABLE=true \
    PHP_MEMORY_LIMIT=512M \
    PHP_OPCACHE_ENABLE=true \
    NGINX_CLIENT_MAX_BODY_SIZE=64m \
    PHP_FPM_PM_MAX_CHILDREN=20 \
    PHP_FPM_PM_START_SERVERS=4 \
    PHP_FPM_PM_MIN_SPARE_SERVERS=2 \
    PHP_FPM_PM_MAX_SPARE_SERVERS=6 \
    PHP_FPM_PM_MAX_REQUESTS=500 \
    RUN_OPTIMIZE_CLEAR_ON_BOOT=false \
    RUN_STORAGE_LINK_ON_BOOT=false \
    RUN_MIGRATIONS_ON_BOOT=false \
    RUN_SEEDERS_ON_BOOT=false \
    RUN_QUEUE_RESTART_ON_BOOT=false \
    QUEUE_ENABLED=true \
    QUEUE_CONNECTION=redis \
    QUEUE_NAMES=default \
    QUEUE_SLEEP=3 \
    QUEUE_TRIES=3 \
    QUEUE_TIMEOUT=90 \
    QUEUE_MAX_JOBS=0 \
    QUEUE_MAX_TIME=0 \
    QUEUE_BACKOFF=0 \
    QUEUE_CONCURRENCY=1 \
    APP_HEALTHCHECK_PATH=/up \
    SSL_COUNTRY=ID \
    SSL_STATE=Jakarta \
    SSL_LOCALITY=Jakarta \
    SSL_ORGANIZATION=indrahulu \
    SSL_ORGANIZATIONAL_UNIT="Laravel Base" \
    SSL_COMMON_NAME=localhost \
    SSL_DAYS=3650

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gettext-base \
        git \
        imagemagick \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libmagickwand-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
        nginx \
        openssl \
        procps \
        supervisor \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        curl \
        exif \
        gd \
        intl \
        mysqli \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        sockets \
        zip \
    && pecl install imagick redis \
    && docker-php-ext-enable imagick redis \
    && apt-mark manual libpq5 libzip4 \
    && apt-get purge -y --auto-remove \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libmagickwand-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN mkdir -p \
        /etc/nginx/templates \
        /etc/nginx/ssl \
        /etc/supervisor/conf.d \
        /etc/supervisor/templates \
        /run/php \
        /var/log/supervisor \
        /var/log/laravel-base \
        /var/www/html \
    && chown -R www-data:www-data /var/www/html

COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY docker/nginx/default-ssl.conf.template /etc/nginx/templates/default-ssl.conf.template
COPY docker/php/conf.d/zz-laravel-base.ini /usr/local/etc/php/conf.d/zz-laravel-base.ini
COPY docker/php-fpm/zz-www.conf.template /usr/local/etc/php-fpm.d/zz-www.conf.template
COPY docker/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/supervisor/templates/ /etc/supervisor/templates/
COPY docker/bin/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/bin/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY docker/bin/run-queue.sh /usr/local/bin/run-queue.sh
COPY docker/bin/run-scheduler.sh /usr/local/bin/run-scheduler.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/run-queue.sh /usr/local/bin/run-scheduler.sh \
    && php -m | grep -qi '^imagick$' \
    && php -m | grep -qi '^redis$' \
    && php -m | grep -qi '^gd$' \
    && php -m | grep -qi '^sockets$'

WORKDIR /var/www/html

EXPOSE 8080 8443

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
