#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-tests/docker-compose-smoke.yml}"
PROJECT_NAME="${PROJECT_NAME:-laravel-base-smoke}"

log() {
  printf '[smoke-test] %s\n' "$*"
}

run_compose() {
  docker compose -p "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

cleanup() {
  run_compose down -v --remove-orphans >/dev/null 2>&1 || true
}

assert_http() {
  local url="$1"
  curl --fail --silent --show-error "${url}" >/dev/null
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

  log "starting smoke stack"
  run_compose up -d

  for service in web worker scheduler all; do
    wait_for "${service} running" "assert_running ${service}"
    wait_for "${service} healthy" "assert_healthy_or_running ${service}"
  done

  log "checking HTTP endpoints"
  wait_for "web HTTP endpoint" "assert_http http://127.0.0.1:18080/up"
  wait_for "all HTTP endpoint" "assert_http http://127.0.0.1:28080/up"

  log "smoke test passed"
}

main "$@"
