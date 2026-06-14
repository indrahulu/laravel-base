#!/usr/bin/env bash
set -Eeuo pipefail

cd "${APP_ROOT:-/var/www/html}"
exec php artisan schedule:work
