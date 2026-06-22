#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${REPO_ROOT}/.env"
  set +a
fi

LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
LOCK_FILE="${LOCK_FILE:-/tmp/indrahulu-laravel-base-build.lock}"
NO_CACHE="${NO_CACHE:-true}"
RUN_SMOKE_BEFORE_PUSH="${RUN_SMOKE_BEFORE_PUSH:-true}"
NTFY_URL="${NTFY_URL:-}"
NTFY_TITLE="${NTFY_TITLE:-cron-build-and-push}"

JOB_STATUS="success"
JOB_ERROR=""
JOB_ARGS=()

resolve_path() {
  local path="$1"

  case "${path}" in
    /*) printf '%s\n' "${path}" ;;
    *) printf '%s/%s\n' "${REPO_ROOT}" "${path}" ;;
  esac
}

LOG_DIR="$(resolve_path "${LOG_DIR}")"
LOCK_FILE="$(resolve_path "${LOCK_FILE}")"

mkdir -p "${LOG_DIR}"

log() {
  printf '[cron-build-and-push] %s\n' "$*"
}

on_error() {
  local exit_code="$1"
  local line="$2"
  local command="$3"

  JOB_STATUS="failed"
  JOB_ERROR="line ${line}: ${command} (exit ${exit_code})"
}

notify_ntfy() {
  local final_status="$1"
  local exit_code="$2"
  local tags="circle-dot"

  [[ -n "${NTFY_URL}" ]] || return 0

  if ! command -v curl >/dev/null 2>&1; then
    log "ntfy notification skipped: curl not found"
    return 0
  fi

  case "${final_status}" in
    success) tags="white_check_mark" ;;
    failed) tags="x" ;;
    skipped) tags="fast_forward" ;;
  esac

  if ! {
    printf 'job: cron-build-and-push\n'
    printf 'status: %s\n' "${final_status}"
    printf 'exit_code: %s\n' "${exit_code}"
    printf 'repo_root: %s\n' "${REPO_ROOT}"
    printf 'log_file: %s\n' "${LOG_DIR}/cron-build-and-push.log"
    printf 'args: %s\n' "${JOB_ARGS[*]:-<none>}"

    if [[ -n "${JOB_ERROR}" ]]; then
      printf 'error: %s\n' "${JOB_ERROR}"
    fi
  } | curl --fail --silent --show-error \
    -H "Title: ${NTFY_TITLE}" \
    -H "Tags: ${tags}" \
    --data-binary @- \
    "${NTFY_URL}" >/dev/null; then
    log "ntfy notification failed"
  fi
}

finish() {
  local exit_code="$1"
  local final_status="${JOB_STATUS}"

  if (( exit_code != 0 )); then
    final_status="failed"
  fi

  notify_ntfy "${final_status}" "${exit_code}"
}

trap 'on_error "$?" "${BASH_LINENO[0]:-${LINENO}}" "$BASH_COMMAND"' ERR
trap 'finish "$?"' EXIT

main() {
  JOB_ARGS=("$@")

  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    JOB_STATUS="skipped"
    JOB_ERROR="another build/push job is still running"
    log "another build/push job is still running; exiting"
    exit 0
  fi

  cd "${REPO_ROOT}"
  log "starting scheduled build and push"
  NO_CACHE="${NO_CACHE}" RUN_SMOKE_BEFORE_PUSH="${RUN_SMOKE_BEFORE_PUSH}" "${REPO_ROOT}/scripts/push-image.sh" "$@"
  log "scheduled build and push finished"
}

main "$@" >> "${LOG_DIR}/cron-build-and-push.log" 2>&1
