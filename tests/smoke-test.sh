#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-tests/docker-compose-smoke.yml}"
PROJECT_NAME="${PROJECT_NAME:-laravel-base-smoke}"

WEB_HTTP_PORT="${WEB_HTTP_PORT:-18080}"
WEB_HTTPS_PORT="${WEB_HTTPS_PORT:-18443}"
ALL_HTTP_PORT="${ALL_HTTP_PORT:-28080}"
ALL_HTTPS_PORT="${ALL_HTTPS_PORT:-28443}"

log() {
  printf '[smoke-test] %s\n' "$*"
}

run_compose() {
  docker compose -p "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

cleanup() {
  log "dumping container logs for diagnostics"
  for service in web worker scheduler all redis; do
    log "--- logs: ${service} ---"
    run_compose logs --tail=50 "${service}" 2>&1 || true
  done

  log "tearing down stack"
  run_compose down -v --remove-orphans >/dev/null 2>&1 || true
}

assert_http() {
  local url="$1"
  curl --fail --silent --show-error --insecure "${url}" >/dev/null
}

assert_running() {
  local service="$1"
  local cid

  cid="$(run_compose ps -q "${service}")"
  if [[ -z "${cid}" ]]; then
    log "service ${service} has no container id"
    return 1
  fi

  local state
  state="$(docker inspect -f '{{.State.Status}}' "${cid}")"
  [[ "${state}" == "running" ]]
}

assert_healthy_or_running() {
  local service="$1"
  local cid

  cid="$(run_compose ps -q "${service}")"
  if [[ -z "${cid}" ]]; then
    log "service ${service} has no container id"
    return 1
  fi

  local health
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}")"
  [[ "${health}" == "healthy" || "${health}" == "none" ]]
}

assert_process_running() {
  local service="$1"
  local process_pattern="$2"
  local cid

  cid="$(run_compose ps -q "${service}")"
  if [[ -z "${cid}" ]]; then
    log "service ${service} has no container id"
    return 1
  fi

  docker exec "${cid}" pgrep -f "${process_pattern}" >/dev/null 2>&1
}

assert_php_version() {
  local service="$1"
  local expected="$2"
  local cid actual

  cid="$(run_compose ps -q "${service}")"
  if [[ -z "${cid}" ]]; then
    log "service ${service} has no container id"
    return 1
  fi

  actual="$(docker exec "${cid}" php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  if [[ "${actual}" != "${expected}" ]]; then
    log "PHP version mismatch in ${service}: expected=${expected} actual=${actual}"
    return 1
  fi
}

wait_for() {
  local description="$1"
  local command="$2"
  local attempts="${3:-30}"
  local sleep_seconds="${4:-2}"

  local i
  for ((i = 1; i <= attempts; i++)); do
    if eval "${command}"; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  log "timed out waiting for ${description}"
  return 1
}

main() {
  trap cleanup EXIT

  log "IMAGE=${IMAGE}"
  log "EXPECTED_PHP_VERSION=${EXPECTED_PHP_VERSION:-<not set>}"
  log "WEB_HTTP_PORT=${WEB_HTTP_PORT} WEB_HTTPS_PORT=${WEB_HTTPS_PORT}"
  log "ALL_HTTP_PORT=${ALL_HTTP_PORT} ALL_HTTPS_PORT=${ALL_HTTPS_PORT}"

  log "starting smoke stack"
  run_compose up -d

  for service in web worker scheduler all; do
    wait_for "${service} running" "assert_running ${service}"
    wait_for "${service} healthy" "assert_healthy_or_running ${service}"
  done

  if [[ -n "${EXPECTED_PHP_VERSION:-}" ]]; then
    log "checking PHP version (expected: ${EXPECTED_PHP_VERSION})"
    wait_for "web PHP version" "assert_php_version web ${EXPECTED_PHP_VERSION}"
    wait_for "all PHP version" "assert_php_version all ${EXPECTED_PHP_VERSION}"
  else
    log "EXPECTED_PHP_VERSION not set, skipping PHP version check"
  fi

  log "checking worker queue process"
  wait_for "worker process" "assert_process_running worker 'queue:work'"

  log "checking scheduler process"
  wait_for "scheduler process" "assert_process_running scheduler 'schedule:work'"

  log "checking HTTP endpoints"
  wait_for "web HTTP endpoint"  "assert_http http://127.0.0.1:${WEB_HTTP_PORT}/up"
  wait_for "all HTTP endpoint"  "assert_http http://127.0.0.1:${ALL_HTTP_PORT}/up"

  log "checking HTTPS endpoints"
  wait_for "web HTTPS endpoint" "assert_http https://127.0.0.1:${WEB_HTTPS_PORT}/up"
  wait_for "all HTTPS endpoint" "assert_http https://127.0.0.1:${ALL_HTTPS_PORT}/up"

  log "smoke test PASSED"
}

main "$@"
