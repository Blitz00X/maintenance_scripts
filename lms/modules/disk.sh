#!/usr/bin/env bash
# Disk diagnostics module: monitors filesystem capacity, health, and storage services.

if [[ -n "${LMS_DISK_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_DISK_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_disk_checks() {
  print_heading "Disk & Filesystem Diagnostics"
  check_disk_root_usage
  check_disk_boot_usage
  check_disk_var_usage
  check_disk_home_usage
  check_disk_tmp_size
  check_disk_root_inodes
  check_disk_var_inodes
  check_disk_read_only_mount
  check_disk_dmesg_errors
  check_disk_smart_health
  check_disk_smart_temperature
  check_disk_trim_timer
  check_disk_fstab_mounts
  check_disk_raid_state
  check_disk_swap_presence
}

check_disk_root_usage() {
  increment_total_checks
  local CODE="DISK001"
  local MESSAGE="Root partition 90% full."
  local REASON="The root filesystem usage exceeds 90%, risking write failures."
  local FIX="Free space or trim logs: sudo journalctl --vacuum-size=100M"

  if ! command_exists df; then
    record_check_skip "$CODE" "${MESSAGE} (df command missing)"
    return
  fi

  local usage
  usage=$(df -P / | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 90 )); then
    attempt_fix_cmd "Reduced journal size" "sudo journalctl --vacuum-size=100M"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Root filesystem usage under control."
  fi
}

check_disk_boot_usage() {
  increment_total_checks
  local CODE="DISK002"
  local MESSAGE="Boot partition usage critical."
  local REASON="/boot directory is above 80% which can block kernel updates."
  local FIX="Remove stale kernels: sudo apt autoremove --purge"

  if ! mountpoint -q /boot; then
    record_check_skip "$CODE" "/boot not a separate partition."
    return
  fi

  local usage
  usage=$(df -P /boot | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 80 )); then
    set_fix_status "pending" "Remove old kernels with sudo apt autoremove"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/boot usage acceptable."
  fi
}

check_disk_var_usage() {
  increment_total_checks
  local CODE="DISK003"
  local MESSAGE="/var partition nearly full."
  local REASON="/var usage exceeds 90%, impacting package and log operations."
  local FIX="Vacuum logs: sudo journalctl --vacuum-size=100M"

  if ! command_exists df; then
    record_check_skip "$CODE" "${MESSAGE} (df command missing)"
    return
  fi

  if ! mountpoint -q /var; then
    record_check_skip "$CODE" "/var not a separate partition."
    return
  fi

  local usage
  usage=$(df -P /var | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 90 )); then
    attempt_fix_cmd "Reduced journal size" "sudo journalctl --vacuum-size=100M"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/var usage acceptable."
  fi
}

check_disk_home_usage() {
  increment_total_checks
  local CODE="DISK004"
  local MESSAGE="Home partition nearly full."
  local REASON="/home usage surpasses 90%, preventing user data from being written."
  local FIX="Clean large files or archive data to external storage"

  if ! command_exists df; then
    record_check_skip "$CODE" "${MESSAGE} (df command missing)"
    return
  fi

  if ! mountpoint -q /home; then
    record_check_skip "$CODE" "/home not a separate partition."
    return
  fi

  local usage
  usage=$(df -P /home | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 90 )); then
    set_fix_status "pending" "Archive or remove large user files"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/home usage acceptable."
  fi
}

check_disk_tmp_size() {
  increment_total_checks
  local CODE="DISK005"
  local MESSAGE="Temporary directory too large."
  local REASON="/tmp exceeds 5G indicating stale temporary files."
  local FIX="Purge temporary files: sudo rm -rf /tmp/*"

  if ! command_exists du; then
    record_check_skip "$CODE" "${MESSAGE} (du command missing)"
    return
  fi

  local size
  size=$(du -sb /tmp 2>/dev/null | awk '{print $1}')
  if [[ -n "$size" ]] && (( size > 5368709120 )); then
    set_fix_status "pending" "Clear stale files in /tmp"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/tmp within expected size."
  fi
}

check_disk_root_inodes() {
  increment_total_checks
  local CODE="DISK006"
  local MESSAGE="Root partition inode exhaustion."
  local REASON="Root filesystem has over 90% inode utilization."
  local FIX="Remove excessive small files under /var and /tmp"

  if ! command_exists df; then
    record_check_skip "$CODE" "${MESSAGE} (df command missing)"
    return
  fi

  local usage
  usage=$(df -Pi / | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 90 )); then
    set_fix_status "pending" "Remove unused cache and spool files"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Root inode usage normal."
  fi
}

check_disk_var_inodes() {
  increment_total_checks
  local CODE="DISK007"
  local MESSAGE="/var inode exhaustion."
  local REASON="/var partition exceeds 90% inode capacity, causing write failures."
  local FIX="Purge old logs or spool files under /var"

  if ! command_exists df; then
    record_check_skip "$CODE" "${MESSAGE} (df command missing)"
    return
  fi

  if ! mountpoint -q /var; then
    record_check_skip "$CODE" "/var not a separate partition."
    return
  fi

  local usage
  usage=$(df -Pi /var | awk 'NR==2 {gsub(/%/, ""); print $5}')
  if [[ -n "$usage" ]] && (( usage > 90 )); then
    set_fix_status "pending" "Remove small files and caches under /var"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/var inode usage normal."
  fi
}

check_disk_read_only_mount() {
  increment_total_checks
  local CODE="DISK008"
  local MESSAGE="Filesystem remounted read-only."
  local REASON="Mount table contains volumes with read-only flag (ro)."
  local FIX="Remount read-write after fsck: sudo mount -o remount,rw <mountpoint>"

  if ! command_exists findmnt; then
    record_check_skip "$CODE" "${MESSAGE} (findmnt command missing)"
    return
  fi

  local ro_mounts
  ro_mounts=$(findmnt -rn -o TARGET,OPTIONS | awk -F' ' '$2 ~ /(^|,)ro($|,)/ {print $1}')
  if [[ -n "$ro_mounts" ]]; then
    local REASON_DETAIL="${REASON} Affected: ${ro_mounts}"
    set_fix_status "pending" "Run fsck and remount affected filesystem"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "All filesystems mounted read-write."
  fi
}

check_disk_dmesg_errors() {
  increment_total_checks
  local CODE="DISK009"
  local MESSAGE="Kernel reported disk I/O errors."
  local REASON="dmesg output includes recent I/O error or sense key warnings."
  local FIX="Inspect hardware cables and run smartctl long test"

  if ! command_exists dmesg; then
    record_check_skip "$CODE" "${MESSAGE} (dmesg command missing)"
    return
  fi

  if dmesg --time-format=iso 2>/dev/null | tail -n 200 | grep -E "I/O error|Buffer I/O error|end_request" >/dev/null 2>&1; then
    set_fix_status "pending" "Check kernel logs and plan disk replacement"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No recent disk I/O errors in kernel log."
  fi
}

check_disk_smart_health() {
  increment_total_checks
  local CODE="DISK010"
  local MESSAGE="SMART overall-health failed."
  local REASON="smartctl reports device failing or unable to run self-test."
  local FIX="Backup data and replace the failing drive"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local device
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    if smartctl -H "$device" 2>/dev/null | grep -qi 'FAILED'; then
      local REASON_DETAIL="${REASON} Device: ${device}"
      set_fix_status "pending" "Schedule drive replacement for ${device}"
      log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
      return
    fi
  done
  record_check_ok "$CODE" "SMART health checks pass."
}

check_disk_smart_temperature() {
  increment_total_checks
  local CODE="DISK011"
  local MESSAGE="Drive temperature critical."
  local REASON="smartctl reports temperature above 60°C."
  local FIX="Improve cooling or relocate the drive"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local device temp
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    temp=$(smartctl -A "$device" 2>/dev/null | awk '/Temperature_Celsius|Temp/ {print $10; exit}')
    if [[ -n "$temp" ]] && (( temp > 60 )); then
      local REASON_DETAIL="${REASON} Device ${device} at ${temp}°C"
      set_fix_status "pending" "Improve airflow for ${device}"
      log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
      return
    fi
  done
  record_check_ok "$CODE" "Drive temperatures normal."
}

check_disk_trim_timer() {
  increment_total_checks
  local CODE="DISK012"
  local MESSAGE="TRIM timer disabled."
  local REASON="fstrim.timer is inactive, preventing SSD discard operations."
  local FIX="Enable TRIM: sudo systemctl enable --now fstrim.timer"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-unit-files | grep -q '^fstrim\.timer'; then
    if ! systemctl is-enabled fstrim.timer >/dev/null 2>&1 || ! systemctl is-active fstrim.timer >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled fstrim.timer" "sudo systemctl enable --now fstrim.timer"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "fstrim.timer not available."
    return
  fi

  record_check_ok "$CODE" "TRIM timer active."
}

check_disk_fstab_mounts() {
  increment_total_checks
  local CODE="DISK013"
  local MESSAGE="fstab entries not mounted."
  local REASON="Entries in /etc/fstab are missing from current mount table."
  local FIX="Mount missing entries: sudo mount -a"

  if [[ ! -f /etc/fstab ]]; then
    record_check_skip "$CODE" "/etc/fstab missing."
    return
  fi

  if ! command_exists awk || ! command_exists findmnt; then
    record_check_skip "$CODE" "Necessary commands unavailable."
    return
  fi

  local missing
  missing=$(awk '/^[^#]/ {print $2}' /etc/fstab | while read -r mountpoint; do
    [[ -z "$mountpoint" ]] && continue
    if [[ "$mountpoint" == "swap" ]]; then
      continue
    fi
    if ! findmnt -rn "$mountpoint" >/dev/null 2>&1; then
      printf '%s ' "$mountpoint"
    fi
  done)

  if [[ -n "$missing" ]]; then
    local REASON_DETAIL="${REASON} Missing: ${missing}"
    set_fix_status "pending" "Run sudo mount -a to restore mounts"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "All fstab entries mounted."
  fi
}

check_disk_raid_state() {
  increment_total_checks
  local CODE="DISK014"
  local MESSAGE="RAID array degraded."
  local REASON="/proc/mdstat indicates a degraded md array."
  local FIX="Rebuild array: sudo mdadm --manage /dev/mdX --add /dev/sdY"

  if [[ ! -f /proc/mdstat ]]; then
    record_check_skip "$CODE" "Software RAID not in use."
    return
  fi

  if grep -E '\[(U_+|_+U)\]' /proc/mdstat >/dev/null 2>&1; then
    set_fix_status "pending" "Replace failed disks and rebuild array"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "RAID arrays healthy."
  fi
}

check_disk_swap_presence() {
  increment_total_checks
  local CODE="DISK015"
  local MESSAGE="No active swap detected."
  local REASON="/proc/swaps reports no swap space; swapping protects against OOM."
  local FIX="Create swap: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"

  if ! command_exists swapon; then
    record_check_skip "$CODE" "${MESSAGE} (swapon missing)"
    return
  fi

  if ! swapon --show 2>/dev/null | tail -n +2 | grep -q '.'; then
    set_fix_status "pending" "Provision swap space"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Swap space detected."
  fi
}
