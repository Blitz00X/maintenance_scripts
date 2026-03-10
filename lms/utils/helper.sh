#!/usr/bin/env bash
# Helper utilities for terminal formatting, command execution, and fix handling.

if [[ -n "${LMS_HELPER_LOADED:-}" ]]; then
  return
fi
export LMS_HELPER_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./colors.sh
source "${SCRIPT_DIR}/colors.sh"

print_heading() {
  printf '%b%s%b\n' "${LMS_COLOR_HEADING}" "$1" "${LMS_COLOR_RESET}"
}

print_info() {
  printf '%b%s%b\n' "${LMS_COLOR_INFO}" "$1" "${LMS_COLOR_RESET}"
}

print_success() {
  printf '%b%s%b\n' "${LMS_COLOR_SUCCESS}" "$1" "${LMS_COLOR_RESET}"
}

print_warning() {
  printf '%b%s%b\n' "${LMS_COLOR_WARN}" "$1" "${LMS_COLOR_RESET}"
}

print_error() {
  printf '%b%s%b\n' "${LMS_COLOR_ERROR}" "$1" "${LMS_COLOR_RESET}"
}

print_muted() {
  printf '%b%s%b\n' "${LMS_COLOR_MUTED}" "$1" "${LMS_COLOR_RESET}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

set_fix_status() {
  # Records the outcome of an attempted fix for consumption by the logger.
  __lms_fix_status="$1"
  __lms_fix_note="$2"
}

clear_fix_status() {
  unset __lms_fix_status
  unset __lms_fix_note
}

attempt_fix_cmd() {
  # attempt_fix_cmd "description" "command"
  local description="$1"
  local command="$2"
  if (( LMS_AUTO_FIX_MODE )); then
    if eval "$command" >/dev/null 2>&1; then
      set_fix_status "fixed" "${description}"; return 0
    else
      set_fix_status "failed" "${description} (command failed)"; return 1
    fi
  else
    set_fix_status "pending" "${description}"; return 1
  fi
}

record_check_ok() {
  local code="$1"; local message="$2"
  print_success "[${code}] ${message}"
}

record_check_skip() {
  local code="$1"; local message="$2"
  print_warning "[${code}] ${message}"
}

check_dependency() {
  local tool="$1"
  local code="$2"
  if ! command_exists "$tool"; then
    record_check_skip "$code" "Missing dependency: ${tool}"
    return 1
  fi
  return 0
}
