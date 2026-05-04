#!/usr/bin/env bash
# Container runtime diagnostics (Docker, Podman, containerd).

if [[ -n "${LMS_CONTAINER_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_CONTAINER_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

LMS_DOCKER_ROOT_PCT_WARN=${LMS_DOCKER_ROOT_PCT_WARN:-90}

run_container_checks() {
  print_heading "Container Runtimes"
  check_ctr_docker_daemon
  check_ctr_docker_root_disk
  check_ctr_podman_health
  check_ctr_containerd_service
  check_ctr_docker_rootless
}

check_ctr_docker_daemon() {
  increment_total_checks
  local CODE="CTR001"
  local MESSAGE="Docker daemon unreachable."
  local REASON="Docker CLI is installed but cannot talk to the daemon (socket or service)."
  local FIX="Start Docker: sudo systemctl enable --now docker.socket docker"

  if ! command_exists docker; then
    record_check_skip "$CODE" "Docker not installed."
    return
  fi

  if command_exists systemctl; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^docker\.socket'; then
      if ! systemctl is-active docker.socket >/dev/null 2>&1; then
        attempt_fix_cmd "Started docker.socket" "sudo systemctl enable --now docker.socket"
      fi
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^docker\.service'; then
      if ! systemctl is-active docker >/dev/null 2>&1; then
        attempt_fix_cmd "Started docker" "sudo systemctl enable --now docker"
      fi
    fi
  fi

  if docker info >/dev/null 2>&1; then
    record_check_ok "$CODE" "Docker daemon reachable."
    return
  fi

  local err
  err=$(docker info 2>&1 | tail -n 3)
  local REASON_DETAIL="${REASON} Detail: ${err//$'\n'/; }"
  set_fix_status "pending" "Start docker.service or check group membership (docker)"
  log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
}

check_ctr_docker_root_disk() {
  increment_total_checks
  local CODE="CTR002"
  local MESSAGE="Docker storage root nearly full."
  local REASON="Filesystem backing Docker Root Dir exceeds warning threshold."
  local FIX="Prune images: docker system prune -a, or expand disk"

  if ! command_exists docker; then
    record_check_skip "$CODE" "Docker not installed."
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    record_check_skip "$CODE" "Docker daemon not reachable."
    return
  fi

  if ! command_exists df; then
    record_check_skip "$CODE" "df missing."
    return
  fi

  local root_dir
  root_dir=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null)
  if [[ -z "$root_dir" || ! -e "$root_dir" ]]; then
    record_check_skip "$CODE" "Docker Root Dir unknown."
    return
  fi

  local usage
  usage=$(df -P "$root_dir" 2>/dev/null | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > LMS_DOCKER_ROOT_PCT_WARN )); then
    local REASON_DETAIL="${REASON} Path ${root_dir} at ${usage}%."
    set_fix_status "pending" "Run docker system df and prune unused data"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Docker root disk usage acceptable (${usage}%)."
  fi
}

check_ctr_podman_health() {
  increment_total_checks
  local CODE="CTR003"
  local MESSAGE="Podman engine unhealthy."
  local REASON="podman info failed, indicating a broken rootless/rootful setup or missing dependencies."
  local FIX="Inspect: podman system info && journalctl --user -u podman"

  if ! command_exists podman; then
    record_check_skip "$CODE" "Podman not installed."
    return
  fi

  if podman info >/dev/null 2>&1; then
    record_check_ok "$CODE" "Podman engine healthy."
    return
  fi

  local err
  err=$(podman info 2>&1 | tail -n 3)
  local REASON_DETAIL="${REASON} Detail: ${err//$'\n'/; }"
  set_fix_status "pending" "Review podman configuration"
  log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
}

check_ctr_containerd_service() {
  increment_total_checks
  local CODE="CTR004"
  local MESSAGE="Containerd service inactive while Docker stack expected."
  local REASON="containerd is the runtime for many Docker installs; if installed but stopped, pulls and runs fail."
  local FIX="Start containerd: sudo systemctl enable --now containerd"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if ! systemctl list-unit-files 2>/dev/null | grep -q '^containerd\.service'; then
    record_check_skip "$CODE" "containerd not installed."
    return
  fi

  if ! command_exists docker; then
    record_check_skip "$CODE" "Docker not installed (containerd check skipped)."
    return
  fi

  if systemctl is-active containerd >/dev/null 2>&1; then
    record_check_ok "$CODE" "Containerd service active."
    return
  fi

  if docker info >/dev/null 2>&1; then
    record_check_ok "$CODE" "Docker works without active containerd unit (alternate runtime)."
    return
  fi

  attempt_fix_cmd "Started containerd" "sudo systemctl enable --now containerd"
  log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
}

check_ctr_docker_rootless() {
  increment_total_checks
  local CODE="CTR005"
  local MESSAGE="Docker rootless mode in use."
  local REASON="docker info reports Rootless: true; confirm this matches host policy and socket permissions."
  local FIX="Review: docker info && docker context ls"

  if ! command_exists docker; then
    record_check_skip "$CODE" "Docker not installed."
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    record_check_skip "$CODE" "Docker daemon not reachable."
    return
  fi

  if docker info 2>/dev/null | grep -qiE '^[[:space:]]*rootless:[[:space:]]+true'; then
    set_fix_status "pending" "Rootless Docker active"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  record_check_ok "$CODE" "Docker not running in rootless mode (or rootless field absent)."
}
