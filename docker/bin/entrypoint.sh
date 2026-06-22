#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/var/www/html}"
APP_ROLE="${APP_ROLE:-web}"
APP_UID="${APP_UID:-}"
APP_GID="${APP_GID:-}"
SSL_SELF_SIGNED_ENABLE="${SSL_SELF_SIGNED_ENABLE:-true}"
QUEUE_ENABLED="${QUEUE_ENABLED:-true}"
RUN_OPTIMIZE_CLEAR_ON_BOOT="${RUN_OPTIMIZE_CLEAR_ON_BOOT:-false}"
RUN_STORAGE_LINK_ON_BOOT="${RUN_STORAGE_LINK_ON_BOOT:-false}"
RUN_MIGRATIONS_ON_BOOT="${RUN_MIGRATIONS_ON_BOOT:-false}"
RUN_SEEDERS_ON_BOOT="${RUN_SEEDERS_ON_BOOT:-false}"
RUN_QUEUE_RESTART_ON_BOOT="${RUN_QUEUE_RESTART_ON_BOOT:-false}"

log() {
  printf '[entrypoint] %s\n' "$*"
}

# Re-exec as root if not already root (needed for usermod, chown, etc.)
if [[ "$(id -u)" -ne 0 ]]; then
  log "Running as UID $(id -u), re-execing as root for setup"
  exec gosu root "$0" "$@"
fi

is_numeric() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_file() {
  local path="$1"
  local message="$2"
  if [[ ! -e "$path" ]]; then
    log "$message"
    exit 1
  fi
}

configure_runtime_user() {
  local current_uid current_gid target_uid target_gid existing_user existing_group

  target_uid="${APP_UID}"
  target_gid="${APP_GID}"

  if [[ -z "${target_uid}" && -z "${target_gid}" ]]; then
    return
  fi

  current_uid="$(id -u www-data)"
  current_gid="$(id -g www-data)"

  if [[ -n "${target_gid}" ]]; then
    if ! is_numeric "${target_gid}"; then
      log "APP_GID must be numeric; got '${target_gid}'"
      exit 1
    fi

    existing_group="$(getent group "${target_gid}" | cut -d: -f1 || true)"
    if [[ -n "${existing_group}" && "${existing_group}" != "www-data" ]]; then
      log "APP_GID ${target_gid} is already used by group ${existing_group}"
      exit 1
    fi

    if [[ "${target_gid}" != "${current_gid}" ]]; then
      log "Updating www-data GID from ${current_gid} to ${target_gid}"
      groupmod -g "${target_gid}" www-data
      current_gid="${target_gid}"
    fi
  fi

  if [[ -n "${target_uid}" ]]; then
    if ! is_numeric "${target_uid}"; then
      log "APP_UID must be numeric; got '${target_uid}'"
      exit 1
    fi

    existing_user="$(getent passwd "${target_uid}" | cut -d: -f1 || true)"
    if [[ -n "${existing_user}" && "${existing_user}" != "www-data" ]]; then
      log "APP_UID ${target_uid} is already used by user ${existing_user}"
      exit 1
    fi

    if [[ "${target_uid}" != "${current_uid}" ]]; then
      log "Updating www-data UID from ${current_uid} to ${target_uid}"
      usermod -u "${target_uid}" www-data
    fi
  fi
}

prepare_permissions() {
  mkdir -p "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
  chown www-data:www-data "${APP_ROOT}" || true
  chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache" || true
  chmod -R ug+rwX "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache" || true
}

boot_hooks_requested() {
  [[ "${RUN_OPTIMIZE_CLEAR_ON_BOOT}" == "true" ]] \
    || [[ "${RUN_STORAGE_LINK_ON_BOOT}" == "true" ]] \
    || [[ "${RUN_MIGRATIONS_ON_BOOT}" == "true" ]] \
    || [[ "${RUN_SEEDERS_ON_BOOT}" == "true" ]] \
    || [[ "${RUN_QUEUE_RESTART_ON_BOOT}" == "true" ]]
}

boot_hooks_allowed_for_role() {
  [[ "${APP_ROLE}" == "web" || "${APP_ROLE}" == "all" ]]
}

run_artisan_command() {
  local command="$1"

  log "Running artisan ${command}"
  if (cd "${APP_ROOT}" && php artisan ${command}); then
    log "artisan ${command} completed"
  else
    log "WARNING: artisan ${command} failed"
  fi
}

run_boot_hooks() {
  if ! boot_hooks_requested; then
    return
  fi

  if ! boot_hooks_allowed_for_role; then
    log "Boot hooks requested but skipped for APP_ROLE=${APP_ROLE}"
    return
  fi

  if [[ ! -f "${APP_ROOT}/artisan" ]]; then
    log "WARNING: boot hooks requested but ${APP_ROOT}/artisan is missing; skipping artisan boot hooks"
    return
  fi

  if [[ "${RUN_OPTIMIZE_CLEAR_ON_BOOT}" == "true" ]]; then
    run_artisan_command "optimize:clear"
  fi

  if [[ "${RUN_STORAGE_LINK_ON_BOOT}" == "true" ]]; then
    run_artisan_command "storage:link"
  fi

  if [[ "${RUN_MIGRATIONS_ON_BOOT}" == "true" ]]; then
    run_artisan_command "migrate --force"
  fi

  if [[ "${RUN_SEEDERS_ON_BOOT}" == "true" ]]; then
    run_artisan_command "db:seed --force"
  fi

  if [[ "${RUN_QUEUE_RESTART_ON_BOOT}" == "true" ]]; then
    run_artisan_command "queue:restart"
  fi
}

write_nginx_config() {
  envsubst '${APP_ROOT} ${NGINX_CLIENT_MAX_BODY_SIZE}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/conf.d/default.conf

  if [[ "${SSL_SELF_SIGNED_ENABLE}" == "true" ]]; then
    printf '\n' >> /etc/nginx/conf.d/default.conf
    envsubst '${APP_ROOT} ${NGINX_CLIENT_MAX_BODY_SIZE}' \
      < /etc/nginx/templates/default-ssl.conf.template \
      >> /etc/nginx/conf.d/default.conf
  fi
}

write_php_fpm_config() {
  envsubst '${PHP_FPM_PM_MAX_CHILDREN} ${PHP_FPM_PM_START_SERVERS} ${PHP_FPM_PM_MIN_SPARE_SERVERS} ${PHP_FPM_PM_MAX_SPARE_SERVERS} ${PHP_FPM_PM_MAX_REQUESTS}' \
    < /usr/local/etc/php-fpm.d/zz-www.conf.template \
    > /usr/local/etc/php-fpm.d/zz-www.conf
}

write_supervisor_programs() {
  local runtime_conf=/etc/supervisor/conf.d/runtime.conf
  : > "${runtime_conf}"

  case "${APP_ROLE}" in
    web)
      cat /etc/supervisor/templates/php-fpm.conf >> "${runtime_conf}"
      printf '\n' >> "${runtime_conf}"
      cat /etc/supervisor/templates/nginx.conf >> "${runtime_conf}"
      ;;
    worker)
      if [[ "${QUEUE_ENABLED}" != "true" ]]; then
        log "QUEUE_ENABLED=false is incompatible with APP_ROLE=worker"
        exit 1
      fi
      envsubst '${QUEUE_CONCURRENCY}' \
        < /etc/supervisor/templates/queue-worker.conf.template \
        >> "${runtime_conf}"
      ;;
    scheduler)
      cat /etc/supervisor/templates/scheduler.conf.template >> "${runtime_conf}"
      ;;
    all)
      cat /etc/supervisor/templates/php-fpm.conf >> "${runtime_conf}"
      printf '\n' >> "${runtime_conf}"
      cat /etc/supervisor/templates/nginx.conf >> "${runtime_conf}"
      if [[ "${QUEUE_ENABLED}" == "true" ]]; then
        printf '\n' >> "${runtime_conf}"
        envsubst '${QUEUE_CONCURRENCY}' \
          < /etc/supervisor/templates/queue-worker.conf.template \
          >> "${runtime_conf}"
      fi
      printf '\n' >> "${runtime_conf}"
      cat /etc/supervisor/templates/scheduler.conf.template >> "${runtime_conf}"
      ;;
    *)
      log "Unsupported APP_ROLE=${APP_ROLE}"
      exit 1
      ;;
  esac
}

validate_app() {
  case "${APP_ROLE}" in
    web)
      require_file "${APP_ROOT}/public/index.php" "Laravel app not found: expected ${APP_ROOT}/public/index.php"
      ;;
    worker|scheduler|all)
      require_file "${APP_ROOT}/artisan" "Laravel app not found: expected ${APP_ROOT}/artisan"
      if [[ "${APP_ROLE}" == "all" ]]; then
        require_file "${APP_ROOT}/public/index.php" "Laravel app not found: expected ${APP_ROOT}/public/index.php"
      fi
      ;;
  esac
}

configure_php() {
  cat > /usr/local/etc/php/conf.d/zz-runtime.ini <<EOF
memory_limit=${PHP_MEMORY_LIMIT:-512M}
opcache.enable=$([[ "${PHP_OPCACHE_ENABLE:-true}" == "true" ]] && echo 1 || echo 0)
opcache.enable_cli=$([[ "${PHP_OPCACHE_ENABLE:-true}" == "true" ]] && echo 1 || echo 0)
opcache.validate_timestamps=$([[ "${PHP_OPCACHE_ENABLE:-true}" == "true" ]] && echo 0 || echo 1)
opcache.revalidate_freq=$([[ "${PHP_OPCACHE_ENABLE:-true}" == "true" ]] && echo 0 || echo 1)
EOF
}

prepare_runtime_directories() {
  chmod 1777 /run
  mkdir -p /run/php
  chown -R www-data:www-data /run/php
  chown -R www-data:www-data /var/lib/nginx 2>/dev/null || true
  chown -R www-data:www-data /var/log/supervisor 2>/dev/null || true
  chown -R www-data:www-data /etc/nginx/ssl 2>/dev/null || true
}

main() {
  configure_runtime_user
  validate_app
  prepare_permissions
  run_boot_hooks
  write_nginx_config
  write_php_fpm_config
  configure_php
  write_supervisor_programs
  prepare_runtime_directories

  log "Starting role ${APP_ROLE} as www-data"
  exec gosu www-data "$@"
}

main "$@"
