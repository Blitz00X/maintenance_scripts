#!/usr/bin/env bash
# Logging helpers for the Linux Maintenance Script.

if [[ -n "${LMS_LOGGER_LOADED:-}" ]]; then
  return
fi
export LMS_LOGGER_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helper.sh
source "${SCRIPT_DIR}/helper.sh"

declare -gA LMS_MESSAGES
declare -gA LMS_REASONS
declare -gA LMS_FIXES
declare -gA LMS_RESULTS
declare -gA LMS_ACTIONS

declare -g LMS_CODES

declare -g LMS_TOTAL_CHECKS=0
declare -g LMS_DETECTED_COUNT=0
declare -g LMS_AUTO_FIXED_COUNT=0

declare -g LMS_REPORT_FILE=""
: "${LMS_EXPLAIN_MODE:=0}"
: "${LMS_AUTO_FIX_MODE:=0}"

set_report_file() {
  LMS_REPORT_FILE="$1"
  mkdir -p "$(dirname "$LMS_REPORT_FILE")"
  : >"$LMS_REPORT_FILE"
}

increment_total_checks() {
  (( LMS_TOTAL_CHECKS++ ))
}

log_issue() {
  local code="$1"
  local message="$2"
  local reason="$3"
  local fix="$4"

  local status="${__lms_fix_status:-pending}"
  local note="${__lms_fix_note:-}"

  LMS_CODES+=("$code")
  LMS_MESSAGES["$code"]="$message"
  LMS_REASONS["$code"]="$reason"
  LMS_FIXES["$code"]="$fix"
  LMS_RESULTS["$code"]="$status"
  LMS_ACTIONS["$code"]="$note"

  (( LMS_DETECTED_COUNT++ ))

  case "$status" in
    fixed)
      (( LMS_AUTO_FIXED_COUNT++ ))
      print_success "[${code}] ${message} (auto-fixed)"
      ;;
    failed)
      print_error "[${code}] ${message} (auto-fix failed)"
      ;;
    attempted)
      print_warning "[${code}] ${message} (fix attempted)"
      ;;
    *)
      print_warning "[${code}] ${message}"
      ;;
  esac

  if (( LMS_EXPLAIN_MODE )); then
    print_muted "LMS detected problem ${code}: ${message} Reason: ${reason} Suggested fix: ${fix}."
  fi

  clear_fix_status
}

finalize_report() {
  if [[ -z "$LMS_REPORT_FILE" ]]; then
    return
  fi

  {
    echo "=== Linux Maintenance Script Report ==="
    echo "Date: $(date '+%Y-%m-%d %H:%M')"
    echo "Total Checks: ${LMS_TOTAL_CHECKS}"
    echo "Detected Issues: ${LMS_DETECTED_COUNT}"
    echo "Auto-fixed: ${LMS_AUTO_FIXED_COUNT}"
    echo
    for code in "${LMS_CODES[@]}"; do
      local message="${LMS_MESSAGES[$code]}"
      local reason="${LMS_REASONS[$code]}"
      local fix="${LMS_FIXES[$code]}"
      local status="${LMS_RESULTS[$code]}"
      local note="${LMS_ACTIONS[$code]}"
      local status_label
      case "$status" in
        fixed) status_label="Status: fixed" ;;
        failed) status_label="Status: fix failed" ;;
        attempted) status_label="Status: fix attempted" ;;
        *) status_label="Status: pending" ;;
      esac
      echo "[${code}] ${message}"
      echo "Cause: ${reason}"
      echo "Fix: ${fix}"
      if [[ -n "$note" ]]; then
        echo "Action: ${note}"
      fi
      echo "${status_label}"
      echo
    done
  } >>"$LMS_REPORT_FILE"
}
