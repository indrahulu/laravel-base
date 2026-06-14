#!/usr/bin/env bash
set -Eeuo pipefail

cd "${APP_ROOT:-/var/www/html}"

args=(
  artisan
  queue:work
  "${QUEUE_CONNECTION:-redis}"
  "--queue=${QUEUE_NAMES:-default}"
  "--sleep=${QUEUE_SLEEP:-3}"
  "--tries=${QUEUE_TRIES:-3}"
  "--timeout=${QUEUE_TIMEOUT:-90}"
)

if [[ "${QUEUE_MAX_JOBS:-0}" != "0" ]]; then
  args+=("--max-jobs=${QUEUE_MAX_JOBS}")
fi

if [[ "${QUEUE_MAX_TIME:-0}" != "0" ]]; then
  args+=("--max-time=${QUEUE_MAX_TIME}")
fi

if [[ "${QUEUE_BACKOFF:-0}" != "0" ]]; then
  args+=("--backoff=${QUEUE_BACKOFF}")
fi

exec php "${args[@]}"
