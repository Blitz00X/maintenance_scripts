#!/usr/bin/env bash
# Boot loader and UEFI diagnostics (systemd-boot, Secure Boot, ESP).

if [[ -n "${LMS_BOOT_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_BOOT_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_boot_checks() {
  print_heading "Boot & UEFI"
  check_boot_bootctl
  check_boot_secure_boot
  check_boot_esp_mount
}

check_boot_bootctl() {
  increment_total_checks
  local CODE="BOOT001"
  local MESSAGE="systemd-boot reports problems."
  local REASON="bootctl status indicates missing ESP, mismatched loader, or failed installation."
  local FIX="Review: bootctl status && bootctl list"

  if ! command_exists bootctl; then
    record_check_skip "$CODE" "bootctl not installed (no systemd-boot?)."
    return
  fi

  local st ec=0
  st=$(bootctl status 2>&1) || ec=$?
  if [[ $ec -ne 0 ]]; then
    if echo "$st" | grep -qiE 'permission|access denied|must be root|operation not permitted'; then
      record_check_skip "$CODE" "bootctl status requires elevated privileges."
      return
    fi
    local REASON_DETAIL="${REASON} Output: ${st//$'\n'/; }"
    set_fix_status "pending" "Run bootctl status as root for details"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
    return
  fi

  if echo "$st" | grep -qiE 'not installed|could not be detected|FAIL|error'; then
    local REASON_DETAIL="${REASON} Snippet: ${st//$'\n'/; }"
    set_fix_status "pending" "Inspect ESP and boot loader entries"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "bootctl status clean."
  fi
}

check_boot_secure_boot() {
  increment_total_checks
  local CODE="BOOT002"
  local MESSAGE="Secure Boot is not enabled."
  local REASON="Firmware reports SecureBoot disabled; required on some compliance baselines."
  local FIX="Enable Secure Boot in firmware setup or enroll MOK keys as needed"

  if ! command_exists mokutil; then
    record_check_skip "$CODE" "mokutil missing."
    return
  fi

  local sb
  if ! sb=$(mokutil --sb-state 2>/dev/null); then
    record_check_skip "$CODE" "mokutil --sb-state failed."
    return
  fi

  if echo "$sb" | grep -qi 'enabled'; then
    record_check_ok "$CODE" "Secure Boot enabled."
  else
    local REASON_DETAIL="${REASON} State: ${sb//$'\n'/; }"
    set_fix_status "pending" "Enable Secure Boot in UEFI firmware if appropriate"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  fi
}

check_boot_esp_mount() {
  increment_total_checks
  local CODE="BOOT003"
  local MESSAGE="EFI system partition mount looks wrong."
  local REASON="/boot/efi should exist on UEFI systems and be mounted as vfat for kernel/shim updates."
  local FIX="Ensure ESP is mounted: sudo mount ... and verify /etc/fstab"

  if [[ ! -d /sys/firmware/efi ]]; then
    record_check_skip "$CODE" "Classic BIOS boot (no /sys/firmware/efi)."
    return
  fi

  if [[ ! -d /boot/efi ]]; then
    record_check_skip "$CODE" "/boot/efi path missing."
    return
  fi

  if ! command_exists findmnt; then
    record_check_skip "$CODE" "findmnt missing."
    return
  fi

  if ! findmnt /boot/efi >/dev/null 2>&1; then
    set_fix_status "pending" "Mount EFI system partition on /boot/efi"
    log_issue "$CODE" "$MESSAGE" "${REASON} /boot/efi is not mounted." "$FIX"
    return
  fi

  local fstype
  fstype=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null)
  if [[ "$fstype" != "vfat" && "$fstype" != "fat32" && "$fstype" != "msdos" ]]; then
    local REASON_DETAIL="${REASON} Found fstype: ${fstype}."
    set_fix_status "pending" "ESP should typically be vfat"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "/boot/efi mounted (${fstype})."
  fi
}
