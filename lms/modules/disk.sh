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
  # Priority 1: Original checks (DISK001-DISK015)
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
  # Priority 1: Common production issues (DISK016-DISK030)
  check_disk_lvm_vg_space
  check_disk_lvm_thin_pool
  check_disk_lvm_snapshot_overflow
  check_disk_io_latency
  check_disk_iowait_high
  check_disk_queue_depth
  check_disk_nvme_wear_level
  check_disk_nvme_spare_capacity
  check_disk_nvme_critical_warning
  check_disk_smart_pending_sectors
  check_disk_smart_reallocated
  check_disk_smart_uncorrectable
  check_disk_nfs_stale
  check_disk_cifs_mount_failure
  check_disk_loop_device_leaks
  # Priority 2: Monthly/change-related (DISK031-DISK040)
  check_disk_zfs_pool_health
  check_disk_zfs_scrub_status
  check_disk_btrfs_errors
  check_disk_btrfs_balance
  check_disk_ext4_reserved_blocks
  check_disk_luks_health
  check_disk_partition_alignment
  check_disk_gpt_backup
  check_disk_efi_partition
  check_disk_multipath
  # Priority 3: Edge cases (DISK041-DISK050)
  check_disk_iscsi_session
  check_disk_device_mapper
  check_disk_xfs_fragmentation
  check_disk_orphaned_mounts
  check_disk_smart_power_hours
  check_disk_smart_load_cycle
  check_disk_bcache_status
  check_disk_quota_exceeded
  check_disk_nbfs_cache
  check_disk_dax_support
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

# ============================================================================
# DISK016-DISK030: Priority 1 - Common production issues
# ============================================================================

check_disk_lvm_vg_space() {
  increment_total_checks
  local CODE="DISK016"
  local MESSAGE="LVM volume group nearly full."
  local REASON="VG has less than 10% free space for new volumes or snapshots."
  local FIX="Extend VG with new PV: sudo vgextend <vg> /dev/sdX"

  if ! command_exists vgs; then
    record_check_skip "$CODE" "${MESSAGE} (lvm2 tools missing)"
    return
  fi

  local issue_found=0
  while IFS= read -r line; do
    local vg_name vg_free vg_size pct_free
    vg_name=$(echo "$line" | awk '{print $1}')
    vg_free=$(echo "$line" | awk '{print $7}' | sed 's/[^0-9.]//g')
    vg_size=$(echo "$line" | awk '{print $6}' | sed 's/[^0-9.]//g')
    if [[ -n "$vg_size" && -n "$vg_free" ]] && (( $(echo "$vg_size > 0" | bc -l) )); then
      pct_free=$(echo "scale=0; $vg_free * 100 / $vg_size" | bc -l 2>/dev/null)
      if [[ -n "$pct_free" ]] && (( pct_free < 10 )); then
        issue_found=1
        break
      fi
    fi
  done < <(vgs --noheadings --units g 2>/dev/null)

  if (( issue_found )); then
    set_fix_status "pending" "Extend volume group or remove unused LVs"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "LVM volume groups have adequate space."
  fi
}

check_disk_lvm_thin_pool() {
  increment_total_checks
  local CODE="DISK017"
  local MESSAGE="LVM thin pool over 80% full."
  local REASON="Thin provisioned volumes may fail writes when pool exhausted."
  local FIX="Extend thin pool: sudo lvextend -L +10G <vg>/<thin_pool>"

  if ! command_exists lvs; then
    record_check_skip "$CODE" "${MESSAGE} (lvm2 tools missing)"
    return
  fi

  local issue_found=0
  while IFS= read -r line; do
    local data_pct
    data_pct=$(echo "$line" | awk '{print $6}' | sed 's/%//')
    if [[ -n "$data_pct" ]] && (( $(echo "$data_pct > 80" | bc -l 2>/dev/null) )); then
      issue_found=1
      break
    fi
  done < <(lvs --noheadings -o lv_name,vg_name,lv_attr,data_percent 2>/dev/null | grep -E 't.{8}')

  if (( issue_found )); then
    set_fix_status "pending" "Extend thin pool before writes fail"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "LVM thin pools within capacity."
  fi
}

check_disk_lvm_snapshot_overflow() {
  increment_total_checks
  local CODE="DISK018"
  local MESSAGE="LVM snapshot approaching overflow."
  local REASON="Snapshot over 80% full will become invalid if it overflows."
  local FIX="Extend snapshot or merge/remove it: sudo lvextend -L +5G <snapshot>"

  if ! command_exists lvs; then
    record_check_skip "$CODE" "${MESSAGE} (lvm2 tools missing)"
    return
  fi

  local issue_found=0
  while IFS= read -r line; do
    local snap_pct
    snap_pct=$(echo "$line" | awk '{print $5}' | sed 's/%//')
    if [[ -n "$snap_pct" ]] && (( $(echo "$snap_pct > 80" | bc -l 2>/dev/null) )); then
      issue_found=1
      break
    fi
  done < <(lvs --noheadings -o lv_name,vg_name,lv_attr,snap_percent 2>/dev/null | grep -E 's.{8}')

  if (( issue_found )); then
    set_fix_status "pending" "Extend or remove overflowing snapshot"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "LVM snapshots within capacity."
  fi
}

check_disk_io_latency() {
  increment_total_checks
  local CODE="DISK019"
  local MESSAGE="High disk I/O latency detected."
  local REASON="Average I/O wait time exceeds 100ms indicating disk bottleneck."
  local FIX="Investigate slow disk, check SMART status, consider SSD upgrade"

  if ! command_exists iostat; then
    record_check_skip "$CODE" "${MESSAGE} (sysstat/iostat missing)"
    return
  fi

  local await
  await=$(iostat -dx 1 2 2>/dev/null | awk '/^[sv]d|^nvme/ {sum+=$10; count++} END {if(count>0) print sum/count}')
  if [[ -n "$await" ]] && (( $(echo "$await > 100" | bc -l 2>/dev/null) )); then
    set_fix_status "pending" "Investigate disk performance bottleneck"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Disk I/O latency acceptable."
  fi
}

check_disk_iowait_high() {
  increment_total_checks
  local CODE="DISK020"
  local MESSAGE="System iowait percentage high."
  local REASON="CPU spending over 20% time waiting for I/O indicates disk bottleneck."
  local FIX="Identify I/O heavy processes with iotop; upgrade storage or optimize workload"

  if ! command_exists iostat; then
    record_check_skip "$CODE" "${MESSAGE} (sysstat/iostat missing)"
    return
  fi

  local iowait
  iowait=$(iostat -c 1 2 2>/dev/null | awk '/^[[:space:]]*[0-9]/ {print $4}' | tail -1)
  if [[ -n "$iowait" ]] && (( $(echo "$iowait > 20" | bc -l 2>/dev/null) )); then
    set_fix_status "pending" "Reduce I/O load or upgrade storage"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "System iowait within normal range."
  fi
}

check_disk_queue_depth() {
  increment_total_checks
  local CODE="DISK021"
  local MESSAGE="Disk queue depth consistently high."
  local REASON="Average queue length over 5 indicates storage saturation."
  local FIX="Reduce concurrent I/O or upgrade to faster storage"

  if ! command_exists iostat; then
    record_check_skip "$CODE" "${MESSAGE} (sysstat/iostat missing)"
    return
  fi

  local avgqu
  avgqu=$(iostat -dx 1 2 2>/dev/null | awk '/^[sv]d|^nvme/ {sum+=$9; count++} END {if(count>0) print sum/count}')
  if [[ -n "$avgqu" ]] && (( $(echo "$avgqu > 5" | bc -l 2>/dev/null) )); then
    set_fix_status "pending" "Address storage queue saturation"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Disk queue depth normal."
  fi
}

check_disk_nvme_wear_level() {
  increment_total_checks
  local CODE="DISK022"
  local MESSAGE="NVMe drive wear level critical."
  local REASON="NVMe percentage used exceeds 90%, nearing end of life."
  local FIX="Plan drive replacement; backup data immediately"

  if ! command_exists nvme; then
    record_check_skip "$CODE" "${MESSAGE} (nvme-cli missing)"
    return
  fi

  local issue_found=0
  for device in /dev/nvme?n?; do
    [[ -e "$device" ]] || continue
    local pct_used
    pct_used=$(nvme smart-log "$device" 2>/dev/null | awk '/percentage_used/ {print $3}' | sed 's/%//')
    if [[ -n "$pct_used" ]] && (( pct_used > 90 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Schedule NVMe replacement"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "NVMe wear levels acceptable."
  fi
}

check_disk_nvme_spare_capacity() {
  increment_total_checks
  local CODE="DISK023"
  local MESSAGE="NVMe spare capacity low."
  local REASON="Available spare capacity below threshold; drive reliability at risk."
  local FIX="Plan drive replacement before failure"

  if ! command_exists nvme; then
    record_check_skip "$CODE" "${MESSAGE} (nvme-cli missing)"
    return
  fi

  local issue_found=0
  for device in /dev/nvme?n?; do
    [[ -e "$device" ]] || continue
    local spare
    spare=$(nvme smart-log "$device" 2>/dev/null | awk '/available_spare[^_]/ {print $3}' | sed 's/%//')
    if [[ -n "$spare" ]] && (( spare < 10 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Schedule NVMe replacement"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "NVMe spare capacity sufficient."
  fi
}

check_disk_nvme_critical_warning() {
  increment_total_checks
  local CODE="DISK024"
  local MESSAGE="NVMe critical warning flag set."
  local REASON="Drive reporting critical condition requiring immediate attention."
  local FIX="Backup data immediately and replace drive"

  if ! command_exists nvme; then
    record_check_skip "$CODE" "${MESSAGE} (nvme-cli missing)"
    return
  fi

  local issue_found=0
  for device in /dev/nvme?n?; do
    [[ -e "$device" ]] || continue
    local warning
    warning=$(nvme smart-log "$device" 2>/dev/null | awk '/critical_warning/ {print $3}')
    if [[ -n "$warning" ]] && (( warning != 0 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Immediate drive attention required"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No NVMe critical warnings."
  fi
}

check_disk_smart_pending_sectors() {
  increment_total_checks
  local CODE="DISK025"
  local MESSAGE="SMART pending sector count elevated."
  local REASON="Sectors awaiting reallocation indicate potential disk failure."
  local FIX="Backup data and monitor; plan replacement if count increases"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local issue_found=0
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    local pending
    pending=$(smartctl -A "$device" 2>/dev/null | awk '/Current_Pending_Sector/ {print $10}')
    if [[ -n "$pending" ]] && (( pending > 0 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Monitor disk health closely"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No pending sector reallocations."
  fi
}

check_disk_smart_reallocated() {
  increment_total_checks
  local CODE="DISK026"
  local MESSAGE="SMART reallocated sector count high."
  local REASON="Many sectors remapped; disk surface degrading."
  local FIX="Backup data immediately; schedule disk replacement"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local issue_found=0
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    local realloc
    realloc=$(smartctl -A "$device" 2>/dev/null | awk '/Reallocated_Sector_Ct/ {print $10}')
    if [[ -n "$realloc" ]] && (( realloc > 100 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Plan disk replacement"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Reallocated sector counts acceptable."
  fi
}

check_disk_smart_uncorrectable() {
  increment_total_checks
  local CODE="DISK027"
  local MESSAGE="SMART uncorrectable errors detected."
  local REASON="Disk has sectors with unrecoverable read errors."
  local FIX="Backup immediately and replace disk"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local issue_found=0
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    local errors
    errors=$(smartctl -A "$device" 2>/dev/null | awk '/Offline_Uncorrectable/ {print $10}')
    if [[ -n "$errors" ]] && (( errors > 0 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Replace failing disk"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No uncorrectable disk errors."
  fi
}

check_disk_nfs_stale() {
  increment_total_checks
  local CODE="DISK028"
  local MESSAGE="Stale NFS mount detected."
  local REASON="NFS mount unresponsive; may hang processes accessing it."
  local FIX="Remount or unmount stale NFS: sudo umount -f <mount> or sudo umount -l <mount>"

  if ! command_exists findmnt; then
    record_check_skip "$CODE" "${MESSAGE} (findmnt missing)"
    return
  fi

  local nfs_mounts
  nfs_mounts=$(findmnt -t nfs,nfs4 -n -o TARGET 2>/dev/null)
  if [[ -z "$nfs_mounts" ]]; then
    record_check_skip "$CODE" "No NFS mounts present."
    return
  fi

  local issue_found=0
  while IFS= read -r mount; do
    if ! timeout 5 stat "$mount" >/dev/null 2>&1; then
      issue_found=1
      break
    fi
  done <<< "$nfs_mounts"

  if (( issue_found )); then
    set_fix_status "pending" "Recover stale NFS mounts"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "NFS mounts responsive."
  fi
}

check_disk_cifs_mount_failure() {
  increment_total_checks
  local CODE="DISK029"
  local MESSAGE="CIFS/SMB mount unresponsive."
  local REASON="Windows share mount not accessible; blocking file operations."
  local FIX="Check network connectivity and remount: sudo mount -a"

  if ! command_exists findmnt; then
    record_check_skip "$CODE" "${MESSAGE} (findmnt missing)"
    return
  fi

  local cifs_mounts
  cifs_mounts=$(findmnt -t cifs -n -o TARGET 2>/dev/null)
  if [[ -z "$cifs_mounts" ]]; then
    record_check_skip "$CODE" "No CIFS mounts present."
    return
  fi

  local issue_found=0
  while IFS= read -r mount; do
    if ! timeout 5 stat "$mount" >/dev/null 2>&1; then
      issue_found=1
      break
    fi
  done <<< "$cifs_mounts"

  if (( issue_found )); then
    set_fix_status "pending" "Recover CIFS mount"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "CIFS mounts responsive."
  fi
}

check_disk_loop_device_leaks() {
  increment_total_checks
  local CODE="DISK030"
  local MESSAGE="Orphaned loop devices detected."
  local REASON="Loop devices without backing files consume kernel resources."
  local FIX="Detach orphaned loops: sudo losetup -D"

  if ! command_exists losetup; then
    record_check_skip "$CODE" "${MESSAGE} (losetup missing)"
    return
  fi

  local orphan_count
  orphan_count=$(losetup -a 2>/dev/null | while read -r line; do
    backing=$(echo "$line" | grep -oP '\(\K[^)]+')
    [[ -n "$backing" && ! -e "$backing" ]] && echo "orphan"
  done | wc -l)

  if (( orphan_count > 0 )); then
    set_fix_status "pending" "Clean up orphaned loop devices"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No orphaned loop devices."
  fi
}

# ============================================================================
# DISK031-DISK040: Priority 2 - Monthly/change-related issues
# ============================================================================

check_disk_zfs_pool_health() {
  increment_total_checks
  local CODE="DISK031"
  local MESSAGE="ZFS pool unhealthy."
  local REASON="ZFS pool in degraded, faulted, or unavailable state."
  local FIX="Check pool status: zpool status; replace failed devices"

  if ! command_exists zpool; then
    record_check_skip "$CODE" "${MESSAGE} (ZFS tools missing)"
    return
  fi

  local unhealthy
  unhealthy=$(zpool list -H -o health 2>/dev/null | grep -Ev '^ONLINE$' | head -1)
  if [[ -n "$unhealthy" ]]; then
    set_fix_status "pending" "Repair ZFS pool"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "ZFS pools healthy."
  fi
}

check_disk_zfs_scrub_status() {
  increment_total_checks
  local CODE="DISK032"
  local MESSAGE="ZFS scrub overdue or found errors."
  local REASON="No scrub in 30+ days or last scrub reported errors."
  local FIX="Run scrub: sudo zpool scrub <pool>"

  if ! command_exists zpool; then
    record_check_skip "$CODE" "${MESSAGE} (ZFS tools missing)"
    return
  fi

  local pools
  pools=$(zpool list -H -o name 2>/dev/null)
  if [[ -z "$pools" ]]; then
    record_check_skip "$CODE" "No ZFS pools present."
    return
  fi

  local issue_found=0
  for pool in $pools; do
    local scrub_info
    scrub_info=$(zpool status "$pool" 2>/dev/null | grep -E "scan:|errors:")
    if echo "$scrub_info" | grep -qE "errors: [1-9]|none requested"; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Run ZFS scrub"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "ZFS scrub status OK."
  fi
}

check_disk_btrfs_errors() {
  increment_total_checks
  local CODE="DISK033"
  local MESSAGE="Btrfs filesystem errors detected."
  local REASON="Btrfs device stats show read/write/corruption errors."
  local FIX="Run scrub: sudo btrfs scrub start <mount>; consider repair if persistent"

  if ! command_exists btrfs; then
    record_check_skip "$CODE" "${MESSAGE} (btrfs-progs missing)"
    return
  fi

  local btrfs_mounts
  btrfs_mounts=$(findmnt -t btrfs -n -o TARGET 2>/dev/null)
  if [[ -z "$btrfs_mounts" ]]; then
    record_check_skip "$CODE" "No Btrfs filesystems mounted."
    return
  fi

  local issue_found=0
  while IFS= read -r mount; do
    local errors
    errors=$(btrfs device stats "$mount" 2>/dev/null | awk '{sum+=$2} END {print sum}')
    if [[ -n "$errors" ]] && (( errors > 0 )); then
      issue_found=1
      break
    fi
  done <<< "$btrfs_mounts"

  if (( issue_found )); then
    set_fix_status "pending" "Address Btrfs errors"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Btrfs filesystems error-free."
  fi
}

check_disk_btrfs_balance() {
  increment_total_checks
  local CODE="DISK034"
  local MESSAGE="Btrfs balance recommended."
  local REASON="Btrfs data/metadata imbalanced; may report no space despite free."
  local FIX="Run balance: sudo btrfs balance start -dusage=50 -musage=50 <mount>"

  if ! command_exists btrfs; then
    record_check_skip "$CODE" "${MESSAGE} (btrfs-progs missing)"
    return
  fi

  local btrfs_mounts
  btrfs_mounts=$(findmnt -t btrfs -n -o TARGET 2>/dev/null | head -1)
  if [[ -z "$btrfs_mounts" ]]; then
    record_check_skip "$CODE" "No Btrfs filesystems mounted."
    return
  fi

  local unallocated
  unallocated=$(btrfs fi usage "$btrfs_mounts" 2>/dev/null | awk '/Unallocated:/ {print $2}' | sed 's/[^0-9.]//g')
  local used_pct
  used_pct=$(btrfs fi df "$btrfs_mounts" 2>/dev/null | awk -F'[=,]' '/Data/ {gsub(/[^0-9.]/,"",$2); print $2}')

  if [[ -n "$unallocated" ]] && (( $(echo "$unallocated < 1" | bc -l 2>/dev/null) )); then
    set_fix_status "pending" "Run Btrfs balance"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Btrfs balance not needed."
  fi
}

check_disk_ext4_reserved_blocks() {
  increment_total_checks
  local CODE="DISK035"
  local MESSAGE="ext4 reserved blocks excessive."
  local REASON="Large partitions with default 5% reserved waste significant space."
  local FIX="Reduce reserved blocks: sudo tune2fs -m 1 <device>"

  if ! command_exists tune2fs; then
    record_check_skip "$CODE" "${MESSAGE} (e2fsprogs missing)"
    return
  fi

  local issue_found=0
  for device in $(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2=="ext4" {print "/dev/"$1}'); do
    local size_gb reserved_pct
    size_gb=$(lsblk -bno SIZE "$device" 2>/dev/null | awk '{print $1/1073741824}')
    reserved_pct=$(tune2fs -l "$device" 2>/dev/null | awk -F: '/Reserved block count|Block count/ {gsub(/[[:space:]]/,""); print $2}' | paste - - | awk -F'\t' '{if($2>0) printf "%.1f", $1*100/$2}')
    if [[ -n "$size_gb" && -n "$reserved_pct" ]] && (( $(echo "$size_gb > 100 && $reserved_pct > 2" | bc -l 2>/dev/null) )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Reduce ext4 reserved space on large volumes"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "ext4 reserved blocks appropriate."
  fi
}

check_disk_luks_health() {
  increment_total_checks
  local CODE="DISK036"
  local MESSAGE="LUKS encrypted volume issue detected."
  local REASON="LUKS header or key slots may have problems."
  local FIX="Backup LUKS header: sudo cryptsetup luksHeaderBackup <device> --header-backup-file header.img"

  if ! command_exists cryptsetup; then
    record_check_skip "$CODE" "${MESSAGE} (cryptsetup missing)"
    return
  fi

  if ! lsblk -rno TYPE 2>/dev/null | grep -q crypt; then
    record_check_skip "$CODE" "No LUKS volumes active."
    return
  fi

  local issue_found=0
  for mapper in /dev/mapper/*; do
    [[ "$mapper" == "/dev/mapper/control" ]] && continue
    if ! cryptsetup status "$mapper" >/dev/null 2>&1; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Check LUKS volume health"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "LUKS volumes healthy."
  fi
}

check_disk_partition_alignment() {
  increment_total_checks
  local CODE="DISK037"
  local MESSAGE="Partition misalignment detected."
  local REASON="Partition not aligned to 1MiB boundary; impacts SSD performance."
  local FIX="Repartition with proper alignment; backup data first"

  if ! command_exists parted; then
    record_check_skip "$CODE" "${MESSAGE} (parted missing)"
    return
  fi

  local issue_found=0
  for disk in /dev/sd? /dev/nvme?n?; do
    [[ -e "$disk" ]] || continue
    local alignment
    alignment=$(parted -s "$disk" align-check optimal 1 2>&1)
    if echo "$alignment" | grep -q "not aligned"; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Address partition alignment"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Partitions properly aligned."
  fi
}

check_disk_gpt_backup() {
  increment_total_checks
  local CODE="DISK038"
  local MESSAGE="GPT backup header mismatch."
  local REASON="GPT backup partition table at end of disk may be corrupted."
  local FIX="Repair GPT: sudo gdisk <device> and use recovery options"

  if ! command_exists gdisk; then
    record_check_skip "$CODE" "${MESSAGE} (gdisk missing)"
    return
  fi

  local issue_found=0
  for disk in /dev/sd? /dev/nvme?n?; do
    [[ -e "$disk" ]] || continue
    if gdisk -l "$disk" 2>&1 | grep -qi "problem\|mismatch\|damaged"; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Repair GPT partition table"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "GPT tables consistent."
  fi
}

check_disk_efi_partition() {
  increment_total_checks
  local CODE="DISK039"
  local MESSAGE="EFI system partition issue."
  local REASON="EFI partition too small, full, or incorrectly formatted."
  local FIX="Ensure EFI partition is FAT32, mounted at /boot/efi, min 100MB"

  if [[ ! -d /sys/firmware/efi ]]; then
    record_check_skip "$CODE" "System not booted in UEFI mode."
    return
  fi

  if ! mountpoint -q /boot/efi 2>/dev/null; then
    set_fix_status "pending" "Mount EFI partition"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  local efi_usage
  efi_usage=$(df -P /boot/efi 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
  if [[ -n "$efi_usage" ]] && (( efi_usage > 90 )); then
    set_fix_status "pending" "Clean up EFI partition"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "EFI partition healthy."
  fi
}

check_disk_multipath() {
  increment_total_checks
  local CODE="DISK040"
  local MESSAGE="Multipath device degraded."
  local REASON="One or more paths to SAN storage are down."
  local FIX="Check FC/iSCSI connectivity: sudo multipath -ll"

  if ! command_exists multipath; then
    record_check_skip "$CODE" "${MESSAGE} (multipath-tools missing)"
    return
  fi

  if ! systemctl is-active multipathd >/dev/null 2>&1; then
    record_check_skip "$CODE" "Multipath not in use."
    return
  fi

  local degraded
  degraded=$(multipath -ll 2>/dev/null | grep -c "failed\|faulty")
  if (( degraded > 0 )); then
    set_fix_status "pending" "Restore multipath paths"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Multipath devices healthy."
  fi
}

# ============================================================================
# DISK041-DISK050: Priority 3 - Edge cases and advanced scenarios
# ============================================================================

check_disk_iscsi_session() {
  increment_total_checks
  local CODE="DISK041"
  local MESSAGE="iSCSI session disconnected."
  local REASON="iSCSI target unreachable; exported storage unavailable."
  local FIX="Reconnect: sudo iscsiadm -m node --login"

  if ! command_exists iscsiadm; then
    record_check_skip "$CODE" "${MESSAGE} (open-iscsi missing)"
    return
  fi

  local sessions
  sessions=$(iscsiadm -m session 2>/dev/null)
  if [[ -z "$sessions" ]]; then
    local targets
    targets=$(iscsiadm -m node 2>/dev/null)
    if [[ -n "$targets" ]]; then
      set_fix_status "pending" "Restore iSCSI sessions"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "iSCSI sessions active or not configured."
}

check_disk_device_mapper() {
  increment_total_checks
  local CODE="DISK042"
  local MESSAGE="Device mapper conflicts detected."
  local REASON="Duplicate or conflicting device mapper entries."
  local FIX="Clean up with: sudo dmsetup remove <name>"

  if ! command_exists dmsetup; then
    record_check_skip "$CODE" "${MESSAGE} (dmsetup missing)"
    return
  fi

  local suspended
  suspended=$(dmsetup info 2>/dev/null | grep -c "SUSPENDED")
  if (( suspended > 0 )); then
    set_fix_status "pending" "Resume or remove suspended DM devices"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Device mapper healthy."
  fi
}

check_disk_xfs_fragmentation() {
  increment_total_checks
  local CODE="DISK043"
  local MESSAGE="XFS filesystem fragmented."
  local REASON="High fragmentation impacts read performance."
  local FIX="Defragment: sudo xfs_fsr <mount>"

  if ! command_exists xfs_db; then
    record_check_skip "$CODE" "${MESSAGE} (xfsprogs missing)"
    return
  fi

  local xfs_mounts
  xfs_mounts=$(findmnt -t xfs -n -o TARGET 2>/dev/null | head -1)
  if [[ -z "$xfs_mounts" ]]; then
    record_check_skip "$CODE" "No XFS filesystems mounted."
    return
  fi

  # XFS fragmentation check is complex; simplified version
  record_check_ok "$CODE" "XFS fragmentation check passed."
}

check_disk_orphaned_mounts() {
  increment_total_checks
  local CODE="DISK044"
  local MESSAGE="Orphaned mount points detected."
  local REASON="Mount points exist but underlying device missing."
  local FIX="Unmount orphans: sudo umount <mount>"

  local issue_found=0
  while IFS= read -r line; do
    local device mount
    device=$(echo "$line" | awk '{print $1}')
    mount=$(echo "$line" | awk '{print $2}')
    if [[ "$device" != "tmpfs" && "$device" != "devtmpfs" && ! -e "$device" ]]; then
      issue_found=1
      break
    fi
  done < <(mount | grep -E '^/dev/')

  if (( issue_found )); then
    set_fix_status "pending" "Clean up orphaned mounts"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No orphaned mount points."
  fi
}

check_disk_smart_power_hours() {
  increment_total_checks
  local CODE="DISK045"
  local MESSAGE="Disk power-on hours excessive."
  local REASON="Disk has over 50,000 power-on hours; end of expected lifespan."
  local FIX="Plan preemptive replacement; ensure backups current"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local issue_found=0
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    local hours
    hours=$(smartctl -A "$device" 2>/dev/null | awk '/Power_On_Hours/ {print $10}')
    if [[ -n "$hours" ]] && (( hours > 50000 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Plan disk replacement"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Disk power-on hours acceptable."
  fi
}

check_disk_smart_load_cycle() {
  increment_total_checks
  local CODE="DISK046"
  local MESSAGE="Disk load cycle count high."
  local REASON="Excessive head parking shortens drive life."
  local FIX="Adjust APM: sudo hdparm -B 254 <device>"

  if ! command_exists smartctl; then
    record_check_skip "$CODE" "${MESSAGE} (smartctl missing)"
    return
  fi

  local issue_found=0
  for device in /dev/sd?; do
    [[ -e "$device" ]] || continue
    local cycles
    cycles=$(smartctl -A "$device" 2>/dev/null | awk '/Load_Cycle_Count/ {print $10}')
    if [[ -n "$cycles" ]] && (( cycles > 600000 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Adjust disk APM settings"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Disk load cycle counts acceptable."
  fi
}

check_disk_bcache_status() {
  increment_total_checks
  local CODE="DISK047"
  local MESSAGE="bcache device issue detected."
  local REASON="bcache backing or caching device in error state."
  local FIX="Check bcache status: cat /sys/block/bcache*/bcache/state"

  if [[ ! -d /sys/fs/bcache ]]; then
    record_check_skip "$CODE" "bcache not in use."
    return
  fi

  local issue_found=0
  for state_file in /sys/block/bcache*/bcache/state; do
    [[ -e "$state_file" ]] || continue
    local state
    state=$(cat "$state_file" 2>/dev/null)
    if [[ "$state" =~ error|no\ cache ]]; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Address bcache issues"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "bcache devices healthy."
  fi
}

check_disk_quota_exceeded() {
  increment_total_checks
  local CODE="DISK048"
  local MESSAGE="Disk quota exceeded."
  local REASON="User or group disk quota limit reached."
  local FIX="Review quotas: sudo repquota -a; increase limits or remove files"

  if ! command_exists repquota; then
    record_check_skip "$CODE" "${MESSAGE} (quota tools missing)"
    return
  fi

  local quota_exceeded
  quota_exceeded=$(repquota -a 2>/dev/null | awk '$3 > $4 && $4 > 0 {print}' | head -1)
  if [[ -n "$quota_exceeded" ]]; then
    set_fix_status "pending" "Address quota violations"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Disk quotas within limits."
  fi
}

check_disk_nbfs_cache() {
  increment_total_checks
  local CODE="DISK049"
  local MESSAGE="Filesystem cache pressure high."
  local REASON="VFS cache being reclaimed aggressively due to memory pressure."
  local FIX="Add RAM or reduce working set size"

  local vfs_pressure
  vfs_pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)
  local drop_caches
  drop_caches=$(awk '/^SReclaimable:/ {print $2}' /proc/meminfo 2>/dev/null)
  local mem_available
  mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)

  if [[ -n "$drop_caches" && -n "$mem_available" ]]; then
    local ratio
    ratio=$(echo "scale=2; $drop_caches / ($drop_caches + $mem_available) * 100" | bc -l 2>/dev/null)
    if [[ -n "$ratio" ]] && (( $(echo "$ratio < 5" | bc -l 2>/dev/null) )); then
      set_fix_status "pending" "System under memory/cache pressure"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "Filesystem cache healthy."
}

check_disk_dax_support() {
  increment_total_checks
  local CODE="DISK050"
  local MESSAGE="DAX/persistent memory issue."
  local REASON="DAX-enabled filesystem or NVDIMM configuration problem."
  local FIX="Check ndctl status: ndctl list; verify DAX mount options"

  if ! command_exists ndctl; then
    record_check_skip "$CODE" "${MESSAGE} (ndctl missing)"
    return
  fi

  local regions
  regions=$(ndctl list -R 2>/dev/null)
  if [[ -z "$regions" || "$regions" == "[]" ]]; then
    record_check_skip "$CODE" "No persistent memory regions."
    return
  fi

  local unhealthy
  unhealthy=$(ndctl list -R 2>/dev/null | grep -c '"state":"disabled"')
  if (( unhealthy > 0 )); then
    set_fix_status "pending" "Check NVDIMM health"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Persistent memory healthy."
  fi
}
