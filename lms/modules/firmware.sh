#!/usr/bin/env bash
# Firmware & microcode diagnostics (fwupd, LVFS metadata freshness, CPU microcode packages).

if [[ -n "${LMS_FIRMWARE_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_FIRMWARE_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

LMS_FWU_METADATA_STALE_DAYS=${LMS_FWU_METADATA_STALE_DAYS:-180}

run_firmware_checks() {
  print_heading "Firmware & Microcode"
  check_fwu_fwupd_service
  check_fwu_pending_updates
  check_fwu_metadata_stale
  check_fwu_cpu_microcode_package
  check_fwu_device_errors
}

check_fwu_fwupd_service() {
  increment_total_checks
  local CODE="FWU001"
  local MESSAGE="Fwupd service inactive."
  local REASON="Firmware updates require an active fwupd daemon."
  local FIX="Start fwupd: sudo systemctl enable --now fwupd"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if ! systemctl list-unit-files 2>/dev/null | grep -qE '^fwupd\.service'; then
    record_check_skip "$CODE" "fwupd not installed."
    return
  fi

  if ! systemctl is-active fwupd >/dev/null 2>&1; then
    attempt_fix_cmd "Started fwupd" "sudo systemctl enable --now fwupd"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Fwupd service active."
  fi
}

check_fwu_pending_updates() {
  increment_total_checks
  local CODE="FWU002"
  local MESSAGE="Firmware upgrades available via fwupd."
  local REASON="fwupdmgr reports devices with newer LVFS/capsule firmware."
  local FIX="Review and apply: fwupdmgr get-updates && fwupdmgr update"

  if ! command_exists fwupdmgr; then
    record_check_skip "$CODE" "fwupdmgr missing."
    return
  fi

  local updates
  if ! updates=$(timeout 45 fwupdmgr --no-history get-updates 2>/dev/null); then
    record_check_skip "$CODE" "fwupdmgr get-updates unavailable or timed out (offline?)."
    return
  fi

  if echo "$updates" | grep -qiF 'No updatable devices' || echo "$updates" | grep -qiF 'No updates detected'; then
    record_check_ok "$CODE" "No pending fwupd upgrades reported."
    return
  fi
  if echo "$updates" | grep -qiE 'upgrade|newer|is upgradable|can be upgraded|release newer'; then
    set_fix_status "pending" "Review fwupdmgr get-updates output"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi
  if [[ -n "$(echo "$updates" | tr -d '[:space:]')" ]]; then
    set_fix_status "pending" "Review fwupdmgr output"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No fwupd upgrade listing (empty)."
  fi
}

check_fwu_metadata_stale() {
  increment_total_checks
  local CODE="FWU003"
  local MESSAGE="Fwupd local metadata may be stale."
  local REASON="Cached firmware metadata under /var/lib/fwupd is older than expected."
  local FIX="Refresh metadata: sudo fwupdmgr refresh --force"

  if [[ ! -d /var/lib/fwupd ]]; then
    record_check_skip "$CODE" "/var/lib/fwupd absent."
    return
  fi

  if ! command_exists find; then
    record_check_skip "$CODE" "find missing."
    return
  fi

  if find /var/lib/fwupd -type f -mtime "+${LMS_FWU_METADATA_STALE_DAYS}" 2>/dev/null | grep -q .; then
    set_fix_status "pending" "Run sudo fwupdmgr refresh"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Fwupd metadata cache recently updated."
  fi
}

check_fwu_cpu_microcode_package() {
  increment_total_checks
  local CODE="FWU004"
  local MESSAGE="CPU microcode package not installed."
  local REASON="AMD/Intel systems should install vendor microcode packages for security fixes."
  local FIX="Install: sudo apt install amd64-microcode  (or intel-microcode)"

  local vendor
  vendor=$(awk -F: '/vendor_id|CPU implementer/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | tr -d '[:space:]')
  if [[ -z "$vendor" ]]; then
    record_check_skip "$CODE" "CPU vendor unknown."
    return
  fi

  if [[ "$vendor" != "AuthenticAMD" && "$vendor" != "GenuineIntel" ]]; then
    record_check_skip "$CODE" "Not an AMD/Intel CPU (${vendor})."
    return
  fi

  if ! command_exists dpkg; then
    record_check_skip "$CODE" "dpkg missing."
    return
  fi

  if [[ "$vendor" == "AuthenticAMD" ]]; then
    if dpkg -l 2>/dev/null | grep -q '^ii[[:space:]]\+amd64-microcode'; then
      record_check_ok "$CODE" "amd64-microcode installed."
    else
      set_fix_status "pending" "Install amd64-microcode"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    fi
  else
    if dpkg -l 2>/dev/null | grep -q '^ii[[:space:]]\+intel-microcode'; then
      record_check_ok "$CODE" "intel-microcode installed."
    else
      set_fix_status "pending" "Install intel-microcode"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    fi
  fi
}

check_fwu_device_errors() {
  increment_total_checks
  local CODE="FWU005"
  local MESSAGE="Fwupd reports device or firmware errors."
  local REASON="fwupdmgr device listing includes failure or error states."
  local FIX="Inspect: fwupdmgr get-devices && journalctl -u fwupd"

  if ! command_exists fwupdmgr; then
    record_check_skip "$CODE" "fwupdmgr missing."
    return
  fi

  local devices
  if ! devices=$(timeout 20 fwupdmgr get-devices 2>/dev/null); then
    record_check_skip "$CODE" "fwupdmgr get-devices failed or timed out."
    return
  fi

  if echo "$devices" | grep -qiE '\[failed\]|\[error\]|Device has failed|unreachable|not supported'; then
    local detail
    detail=$(echo "$devices" | grep -iE '\[failed\]|\[error\]|Device has failed|unreachable|not supported' | head -n 3)
    local REASON_DETAIL="${REASON} Snippet: ${detail//$'\n'/; }"
    set_fix_status "pending" "Review fwupdmgr get-devices and fwupd journal"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No obvious fwupd device errors."
  fi
}
