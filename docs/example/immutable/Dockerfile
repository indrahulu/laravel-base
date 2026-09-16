FROM node:22-alpine AS frontend

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM indrahulu/laravel-base:php8.5

COPY --chown=www-data:www-data . /var/www/html
COPY --from=frontend --chown=www-data:www-data /app/public/build /var/www/html/public/build

RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader
