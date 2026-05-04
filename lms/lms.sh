#!/usr/bin/env bash
# Linux Maintenance Script (LMS): orchestrates diagnostics across modular check suites.

set -o pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${BASE_DIR}/utils"
MODULE_DIR="${BASE_DIR}/modules"
CONFIG_FILE="${BASE_DIR}/config.sh"
REPORT_DIR="${BASE_DIR}/reports"

if [[ -f "${BASE_DIR}/config.example.sh" ]]; then
  # shellcheck source=./config.example.sh
  source "${BASE_DIR}/config.example.sh"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=./config.sh
  source "${CONFIG_FILE}"
fi

DEFAULT_MODULES=(network disk package container performance security system firmware boot log)
if [[ -z ${LMS_ENABLED_MODULES+x} || ${#LMS_ENABLED_MODULES[@]} -eq 0 ]]; then
  LMS_ENABLED_MODULES=("${DEFAULT_MODULES[@]}")
fi

LMS_DEFAULT_AUTO_FIX=${LMS_DEFAULT_AUTO_FIX:-0}
LMS_DEFAULT_EXPLAIN=${LMS_DEFAULT_EXPLAIN:-0}
if [[ -z ${LMS_DEFAULT_ARGS+x} ]]; then
  LMS_DEFAULT_ARGS=()
fi

# shellcheck source=./utils/logger.sh
source "${UTIL_DIR}/logger.sh"

usage() {
  cat <<'USAGE'
Linux Maintenance Script (LMS)
Usage: lms.sh [--fix] [--explain] [--report <path>]

  --fix       Apply safe automatic fixes where available
  --explain   Provide verbose explanations for detected issues
  --json      Generate a structured JSON report
  --report    Custom report output path
  --help      Show this help message
USAGE
}

REPORT_PATH=""
LMS_AUTO_FIX_MODE=${LMS_DEFAULT_AUTO_FIX}
LMS_EXPLAIN_MODE=${LMS_DEFAULT_EXPLAIN}

if (( ${#LMS_DEFAULT_ARGS[@]} )); then
  set -- "${LMS_DEFAULT_ARGS[@]}" "$@"
fi

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
      --json)
        LMS_JSON_MODE=1
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
  if [[ -n "${LMS_REPORT_DIR:-}" ]]; then
    REPORT_DIR="${LMS_REPORT_DIR}"
  fi
  mkdir -p "$REPORT_DIR"
  if [[ -z "$REPORT_PATH" ]]; then
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    REPORT_PATH="${REPORT_DIR}/report_${timestamp}.txt"
  fi
  set_report_file "$REPORT_PATH"
}

load_modules() {
  local module_file
  for module_file in "${MODULE_DIR}"/*.sh; do
    if [[ -f "$module_file" ]]; then
      # shellcheck disable=SC1090
      source "$module_file"
    fi
  done
}

check_privileges() {
  if (( LMS_AUTO_FIX_MODE )) && [[ $EUID -ne 0 ]]; then
    print_warning "Running with --fix but without root privileges. Some remediations may fail."
    echo
  fi
}

run_checks() {
  print_heading "Linux Maintenance Script"
  print_info "Auto-fix mode: $([[ $LMS_AUTO_FIX_MODE -eq 1 ]] && echo Enabled || echo Disabled)"
  print_info "Explain mode: $([[ $LMS_EXPLAIN_MODE -eq 1 ]] && echo Enabled || echo Disabled)"
  print_info "Report path: ${REPORT_PATH}"
  echo

  local module
  for module in "${LMS_ENABLED_MODULES[@]}"; do
    run_module "${module}"
    echo
  done
}

run_module() {
  local module_name="$1"
  local func="run_${module_name}_checks"
  if declare -F "$func" >/dev/null; then
    "$func"
  else
    print_warning "Unknown module '${module_name}' or check function '${func}' missing."
  fi
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
  check_privileges
  load_modules
  run_checks
  summarize
}

main "$@"
