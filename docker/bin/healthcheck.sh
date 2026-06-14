#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROLE="${APP_ROLE:-web}"
APP_HEALTHCHECK_PATH="${APP_HEALTHCHECK_PATH:-/up}"

supervisor_ok() {
  supervisorctl status >/dev/null 2>&1
}

process_running() {
  local name="$1"
  supervisorctl status "$name" 2>/dev/null | grep -q 'RUNNING'
}

http_ok() {
  curl --fail --silent --show-error "http://127.0.0.1:8080${APP_HEALTHCHECK_PATH}" >/dev/null \
    || curl --fail --silent --show-error "http://127.0.0.1:8080/" >/dev/null
}

case "${APP_ROLE}" in
  web)
    supervisor_ok && process_running php-fpm && process_running nginx && http_ok
    ;;
  worker)
    supervisor_ok && process_running queue-worker:queue-worker_00
    ;;
  scheduler)
    supervisor_ok && process_running scheduler
    ;;
  all)
    supervisor_ok \
      && process_running php-fpm \
      && process_running nginx \
      && process_running scheduler \
      && http_ok \
      && { process_running queue-worker:queue-worker_00 || [[ "${QUEUE_ENABLED:-true}" != "true" ]]; }
    ;;
  *)
    exit 1
    ;;
esac
