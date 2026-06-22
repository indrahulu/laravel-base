#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="${IMAGE_NAME:-indrahulu/laravel-base}"
PRIMARY_TAG="${PRIMARY_TAG:-php8.3}"
BUILD_BEFORE_PUSH="${BUILD_BEFORE_PUSH:-true}"
NO_CACHE="${NO_CACHE:-false}"
RUN_SMOKE_BEFORE_PUSH="${RUN_SMOKE_BEFORE_PUSH:-false}"

log() {
  printf '[push-image] %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/push-image.sh [extra-tag ...]

Environment variables:
  IMAGE_NAME          Docker image name. Default: indrahulu/laravel-base
  PRIMARY_TAG         Primary tag to build and push. Default: php8.3
  BUILD_BEFORE_PUSH   Build image before push. true|false. Default: true
  NO_CACHE            Build with --no-cache. true|false. Default: false
  RUN_SMOKE_BEFORE_PUSH
                      Run tests/smoke-test.sh before push. true|false. Default: false

Examples:
  ./scripts/push-image.sh
  ./scripts/push-image.sh php8.3-20260615
  IMAGE_NAME=indrahulu/laravel-base PRIMARY_TAG=php8.3 ./scripts/push-image.sh latest php8.3-20260615
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "required command not found: ${command_name}"
    exit 1
  fi
}

assert_docker_login() {
  if ! docker info >/dev/null 2>&1; then
    log "docker daemon is not reachable"
    exit 1
  fi

  if ! docker system info --format '{{json .RegistryConfig.IndexConfigs}}' 2>/dev/null | grep -q 'docker.io'; then
    log "unable to confirm Docker Hub registry configuration"
  fi
}

is_release_tag() {
  [[ "${PRIMARY_TAG}" =~ ^release ]]
}

run_smoke_if_required() {
  local should_run="${RUN_SMOKE_BEFORE_PUSH}"

  if [[ "${should_run}" != "true" ]] && is_release_tag; then
    should_run="true"
    log "release tag detected; forcing smoke test before push"
  fi

  if [[ "${should_run}" != "true" ]]; then
    log "smoke test skipped"
    return
  fi

  if [[ ! -f "tests/smoke-test.sh" ]]; then
    log "smoke test script not found at tests/smoke-test.sh"
    exit 1
  fi

  log "running smoke test before push"
  bash ./tests/smoke-test.sh
  log "smoke test passed"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_command docker
  assert_docker_login

  local primary_ref="${IMAGE_NAME}:${PRIMARY_TAG}"
  local extra_tags=("$@")

  if [[ "${BUILD_BEFORE_PUSH}" == "true" ]]; then
    log "building ${primary_ref}"
    if [[ "${NO_CACHE}" == "true" ]]; then
      docker build --no-cache -t "${primary_ref}" .
    else
      docker build -t "${primary_ref}" .
    fi
  else
    log "skipping build for ${primary_ref}"
  fi

  run_smoke_if_required

  local tag
  for tag in "${extra_tags[@]}"; do
    log "tagging ${primary_ref} as ${IMAGE_NAME}:${tag}"
    docker tag "${primary_ref}" "${IMAGE_NAME}:${tag}"
  done

  log "pushing ${primary_ref}"
  docker push "${primary_ref}"

  for tag in "${extra_tags[@]}"; do
    log "pushing ${IMAGE_NAME}:${tag}"
    docker push "${IMAGE_NAME}:${tag}"
  done

  log "push complete"
}

main "$@"
