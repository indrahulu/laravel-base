#!/usr/bin/env bash
set -Eeuo pipefail

# Cleanup old versioned Docker Hub tags, keeping the most recent N per PHP version.
#
# Usage:
#   DOCKERHUB_TOKEN=xxx DOCKERHUB_USERNAME=indrahulu bash scripts/cleanup-old-tags.sh
#
# Environment variables:
#   DOCKERHUB_USERNAME   Docker Hub username (required)
#   DOCKERHUB_TOKEN      Docker Hub access token (required)
#   DOCKERHUB_NAMESPACE  Docker Hub namespace. Default: indrahulu
#   DOCKERHUB_REPOSITORY Repository name. Default: laravel-base
#   KEEP                 Number of versioned tags to keep per PHP version. Default: 5
#   DRY_RUN              Set to "true" to only list tags that would be deleted. Default: false

DOCKERHUB_NAMESPACE="${DOCKERHUB_NAMESPACE:-indrahulu}"
DOCKERHUB_REPOSITORY="${DOCKERHUB_REPOSITORY:-laravel-base}"
KEEP="${KEEP:-5}"
DRY_RUN="${DRY_RUN:-false}"

API_BASE="https://hub.docker.com/v2"
REPO_PATH="namespaces/${DOCKERHUB_NAMESPACE}/repositories/${DOCKERHUB_REPOSITORY}"

log() {
  printf '[cleanup] %s\n' "$*"
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log "ERROR: ${name} is required"
    exit 1
  fi
}

login() {
  local response token

  response="$(curl --fail --silent --show-error \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${DOCKERHUB_USERNAME}\", \"password\": \"${DOCKERHUB_TOKEN}\"}" \
    "${API_BASE}/users/login")"

  token="$(printf '%s' "${response}" | jq -r '.token')"

  if [[ -z "${token}" || "${token}" == "null" ]]; then
    log "ERROR: failed to obtain Docker Hub JWT"
    exit 1
  fi

  printf '%s' "${token}"
}

list_all_tags() {
  local jwt="$1"
  local page=1
  local page_size=100
  local results="[]"
  local response count

  while true; do
    response="$(curl --fail --silent --show-error \
      -H "Authorization: Bearer ${jwt}" \
      "${API_BASE}/${REPO_PATH}/tags?page=${page}&page_size=${page_size}")"

    count="$(printf '%s' "${response}" | jq '.results | length')"

    results="$(printf '%s\n%s' "${results}" "${response}" | jq -s '.[0] + (.[1].results // [])')"

    if (( count < page_size )); then
      break
    fi

    page=$((page + 1))
  done

  printf '%s' "${results}"
}

delete_tag() {
  local jwt="$1"
  local tag_name="$2"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "[DRY RUN] would delete tag: ${tag_name}"
    return 0
  fi

  log "deleting tag: ${tag_name}"
  local http_code
  http_code="$(curl --silent --show-error \
    -o /dev/null -w '%{http_code}' \
    -X DELETE \
    -H "Authorization: Bearer ${jwt}" \
    "${API_BASE}/${REPO_PATH}/tags/${tag_name}")"

  if [[ "${http_code}" == "204" || "${http_code}" == "200" ]]; then
    log "deleted: ${tag_name}"
  else
    log "WARNING: failed to delete ${tag_name} (HTTP ${http_code})"
  fi
}

main() {
  require_var DOCKERHUB_USERNAME
  require_var DOCKERHUB_TOKEN

  log "namespace=${DOCKERHUB_NAMESPACE} repository=${DOCKERHUB_REPOSITORY} keep=${KEEP} dry_run=${DRY_RUN}"

  log "logging in to Docker Hub"
  local jwt
  jwt="$(login)"

  log "listing tags"
  local all_tags
  all_tags="$(list_all_tags "${jwt}")"

  local total
  total="$(printf '%s' "${all_tags}" | jq 'length')"
  log "found ${total} tags total"

  # Filter versioned tags: php*-v*
  local versioned_tags
  versioned_tags="$(printf '%s' "${all_tags}" | jq '[.[] | select(.name | test("^php[0-9]+\\.[0-9]+-v[0-9]+"))]')"

  local versioned_count
  versioned_count="$(printf '%s' "${versioned_tags}" | jq 'length')"
  log "found ${versioned_count} versioned tags"

  if (( versioned_count == 0 )); then
    log "nothing to clean up"
    return 0
  fi

  # Group by PHP version prefix (e.g. php8.2, php8.3, php8.4)
  local php_versions
  php_versions="$(printf '%s' "${versioned_tags}" | jq -r '[.[].name | capture("^(?<prefix>php[0-9]+\\.[0-9]+)-v.*") | .prefix] | unique | .[]')"

  for php_ver in ${php_versions}; do
    log "--- processing ${php_ver} ---"

    # Get tags for this PHP version, sorted by last_updated descending
    local sorted tags_to_keep tags_to_delete keep_count delete_count

    sorted="$(printf '%s' "${versioned_tags}" | jq --arg prefix "${php_ver}-v" \
      '[.[] | select(.name | startswith($prefix))] | sort_by(.last_updated) | reverse')"

    keep_count="$(printf '%s' "${sorted}" | jq --argjson keep "${KEEP}" '.[0:$keep] | length')"
    delete_count="$(printf '%s' "${sorted}" | jq --argjson keep "${KEEP}" '.[$keep:] | length')"

    log "keeping ${keep_count} tags, deleting ${delete_count} tags"

    tags_to_keep="$(printf '%s' "${sorted}" | jq -r --argjson keep "${KEEP}" '.[0:$keep] | .[].name')"
    log "keep: ${tags_to_keep}"

    if (( delete_count == 0 )); then
      log "no tags to delete for ${php_ver}"
      continue
    fi

    tags_to_delete="$(printf '%s' "${sorted}" | jq -r --argjson keep "${KEEP}" '.[$keep:] | .[].name')"

    while IFS= read -r tag_name; do
      [[ -z "${tag_name}" ]] && continue
      delete_tag "${jwt}" "${tag_name}"
    done <<< "${tags_to_delete}"
  done

  log "cleanup complete"
}

main "$@"
