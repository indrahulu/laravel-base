#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
LOCK_FILE="${LOCK_FILE:-/tmp/indrahulu-laravel-base-build.lock}"
NO_CACHE="${NO_CACHE:-true}"

mkdir -p "${LOG_DIR}"

log() {
  printf '[cron-build-and-push] %s\n' "$*"
}

main() {
  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    log "another build/push job is still running; exiting"
    exit 0
  fi

  cd "${REPO_ROOT}"
  log "starting scheduled build and push"
  NO_CACHE="${NO_CACHE}" "${REPO_ROOT}/scripts/push-image.sh" "$@"
  log "scheduled build and push finished"
}

main "$@" >> "${LOG_DIR}/cron-build-and-push.log" 2>&1
