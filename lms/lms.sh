#!/usr/bin/env bash
# Linux Maintenance Script (LMS): orchestrates diagnostics across modular check suites.

set -o pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${BASE_DIR}/utils"
MODULE_DIR="${BASE_DIR}/modules"
REPORT_DIR="${BASE_DIR}/reports"

# shellcheck source=./utils/logger.sh
source "${UTIL_DIR}/logger.sh"

usage() {
  cat <<'USAGE'
Linux Maintenance Script (LMS)
Usage: lms.sh [--fix] [--explain] [--report <path>]

  --fix       Apply safe automatic fixes where available
  --explain   Provide verbose explanations for detected issues
  --report    Custom report output path
  --help      Show this help message
USAGE
}

REPORT_PATH=""
LMS_AUTO_FIX_MODE=0
LMS_EXPLAIN_MODE=${LMS_EXPLAIN_MODE:-0}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix)
        LMS_AUTO_FIX_MODE=1
        shift
        ;;
      --explain)
        LMS_EXPLAIN_MODE=1
        shift
        ;;
      --report)
        REPORT_PATH="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

prepare_environment() {
  mkdir -p "$REPORT_DIR"
  if [[ -z "$REPORT_PATH" ]]; then
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    REPORT_PATH="${REPORT_DIR}/report_${timestamp}.txt"
  fi
  set_report_file "$REPORT_PATH"
}

load_modules() {
  # shellcheck source=./modules/network.sh
  source "${MODULE_DIR}/network.sh"
  # shellcheck source=./modules/disk.sh
  source "${MODULE_DIR}/disk.sh"
  # shellcheck source=./modules/package.sh
  source "${MODULE_DIR}/package.sh"
  # shellcheck source=./modules/performance.sh
  source "${MODULE_DIR}/performance.sh"
  # shellcheck source=./modules/security.sh
  source "${MODULE_DIR}/security.sh"
  # shellcheck source=./modules/system.sh
  source "${MODULE_DIR}/system.sh"
  # shellcheck source=./modules/log.sh
  source "${MODULE_DIR}/log.sh"
}

run_checks() {
  print_heading "Linux Maintenance Script"
  print_info "Auto-fix mode: $([[ $LMS_AUTO_FIX_MODE -eq 1 ]] && echo Enabled || echo Disabled)"
  print_info "Explain mode: $([[ $LMS_EXPLAIN_MODE -eq 1 ]] && echo Enabled || echo Disabled)"
  print_info "Report path: ${REPORT_PATH}"
  echo

  run_network_checks
  echo
  run_disk_checks
  echo
  run_package_checks
  echo
  run_performance_checks
  echo
  run_security_checks
  echo
  run_system_checks
  echo
  run_log_checks
}

summarize() {
  finalize_report
  echo
  print_heading "Summary"
  print_info "Total checks executed: ${LMS_TOTAL_CHECKS}"
  if (( LMS_DETECTED_COUNT > 0 )); then
    print_warning "Detected issues: ${LMS_DETECTED_COUNT}"
  else
    print_success "Detected issues: 0"
  fi
  print_info "Auto-fixed issues: ${LMS_AUTO_FIXED_COUNT}"
  print_info "Report saved to: ${REPORT_PATH}"
}

main() {
  parse_args "$@"
  prepare_environment
  load_modules
  run_checks
  summarize
}

main "$@"
