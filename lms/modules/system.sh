#!/usr/bin/env bash
# Core system diagnostics: monitors essential services, timers, and identity configuration.

if [[ -n "${LMS_SYSTEM_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_SYSTEM_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_system_checks() {
  print_heading "System Services & Configuration"
  check_sys_system_state
  check_sys_failed_units
  check_sys_cron_service
  check_sys_anacron_service
  check_sys_atd_service
  check_sys_rsyslog_service
  check_sys_dbus_service
  check_sys_polkit_service
  check_sys_apt_daily_timer
  check_sys_logrotate_timer
  check_sys_hostname_consistency
  check_sys_machine_id
  check_sys_masked_units
  check_sys_broken_symlinks
}

check_sys_system_state() {
  increment_total_checks
  local CODE="SYS001"
  local MESSAGE="Systemd reports degraded state."
  local REASON="systemctl is-system-running returned degraded or maintenance."
  local FIX="Inspect failing units: systemctl --failed"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  local state
  state=$(systemctl is-system-running 2>/dev/null)
  if [[ "$state" =~ (degraded|maintenance|emergency) ]]; then
    local REASON_DETAIL="${REASON} Current state: ${state}"
    set_fix_status "pending" "Review failing units"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "System state: ${state}."
  fi
}

check_sys_failed_units() {
  increment_total_checks
  local CODE="SYS002"
  local MESSAGE="Failed systemd units detected."
  local REASON="systemctl --failed listed services or timers in failed state."
  local FIX="Restart units: sudo systemctl restart <unit>"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  local failed
  failed=$(systemctl --failed --no-legend 2>/dev/null)
  if [[ -n "$failed" ]]; then
    local REASON_DETAIL="${REASON} Units: ${failed//$'\n'/; }"
    set_fix_status "pending" "Investigate failed units"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No failed units."
  fi
}

check_sys_cron_service() {
  increment_total_checks
  local CODE="SYS003"
  local MESSAGE="Cron service inactive."
  local REASON="cron.service not running prevents scheduled tasks."
  local FIX="Restart cron: sudo systemctl restart cron"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^cron\.service'; then
    if ! systemctl is-active cron >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted cron" "sudo systemctl restart cron"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "cron service not installed."
    return
  fi

  record_check_ok "$CODE" "Cron service active."
}

check_sys_anacron_service() {
  increment_total_checks
  local CODE="SYS004"
  local MESSAGE="Anacron service inactive."
  local REASON="anacron.timer or service disabled leaving laptops without periodic jobs."
  local FIX="Enable anacron: sudo systemctl enable --now anacron.timer"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^anacron\.service'; then
    if ! systemctl is-active anacron >/dev/null 2>&1; then
      attempt_fix_cmd "Started anacron" "sudo systemctl restart anacron"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  elif systemctl list-unit-files | grep -q '^anacron\.timer'; then
    if ! systemctl is-active anacron.timer >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled anacron.timer" "sudo systemctl enable --now anacron.timer"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "Anacron not installed."
    return
  fi

  record_check_ok "$CODE" "Anacron scheduling active."
}

check_sys_atd_service() {
  increment_total_checks
  local CODE="SYS005"
  local MESSAGE="atd service inactive."
  local REASON="atd systemd unit not running disables 'at' jobs."
  local FIX="Restart atd: sudo systemctl restart atd"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^atd\.service'; then
    if ! systemctl is-active atd >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted atd" "sudo systemctl restart atd"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "atd service not installed."
    return
  fi

  record_check_ok "$CODE" "atd service active."
}

check_sys_rsyslog_service() {
  increment_total_checks
  local CODE="SYS006"
  local MESSAGE="Rsyslog service inactive."
  local REASON="rsyslog.service stopped, risking loss of system logs."
  local FIX="Restart rsyslog: sudo systemctl restart rsyslog"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^rsyslog\.service'; then
    if ! systemctl is-active rsyslog >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted rsyslog" "sudo systemctl restart rsyslog"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "rsyslog service not installed."
    return
  fi

  record_check_ok "$CODE" "Rsyslog service active."
}

check_sys_dbus_service() {
  increment_total_checks
  local CODE="SYS007"
  local MESSAGE="DBus service inactive."
  local REASON="dbus-daemon not running disrupts desktop and system messaging."
  local FIX="Restart DBus: sudo systemctl restart dbus"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^dbus\.service'; then
    if ! systemctl is-active dbus >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted dbus" "sudo systemctl restart dbus"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "dbus service not installed."
    return
  fi

  record_check_ok "$CODE" "DBus service active."
}

check_sys_polkit_service() {
  increment_total_checks
  local CODE="SYS008"
  local MESSAGE="PolicyKit service inactive."
  local REASON="polkit service is required for desktop privilege escalation prompts."
  local FIX="Restart polkit: sudo systemctl restart polkit"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^polkit\.service'; then
    if ! systemctl is-active polkit >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted polkit" "sudo systemctl restart polkit"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "polkit service not installed."
    return
  fi

  record_check_ok "$CODE" "PolicyKit service active."
}

check_sys_apt_daily_timer() {
  increment_total_checks
  local CODE="SYS009"
  local MESSAGE="apt-daily.timer disabled."
  local REASON="System will miss automatic package list refreshes."
  local FIX="Enable timer: sudo systemctl enable --now apt-daily.timer"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^apt-daily\.timer'; then
    if ! systemctl is-enabled apt-daily.timer >/dev/null 2>&1 || ! systemctl is-active apt-daily.timer >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled apt-daily.timer" "sudo systemctl enable --now apt-daily.timer"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "apt-daily timer not present."
    return
  fi

  record_check_ok "$CODE" "apt-daily timer active."
}

check_sys_logrotate_timer() {
  increment_total_checks
  local CODE="SYS010"
  local MESSAGE="logrotate.timer disabled."
  local REASON="Without log rotation, log files grow without bound."
  local FIX="Enable timer: sudo systemctl enable --now logrotate.timer"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^logrotate\.timer'; then
    if ! systemctl is-enabled logrotate.timer >/dev/null 2>&1 || ! systemctl is-active logrotate.timer >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled logrotate.timer" "sudo systemctl enable --now logrotate.timer"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "logrotate timer not installed."
    return
  fi

  record_check_ok "$CODE" "logrotate timer active."
}

check_sys_hostname_consistency() {
  increment_total_checks
  local CODE="SYS011"
  local MESSAGE="Hostname mismatch detected."
  local REASON="/etc/hostname differs from runtime hostname causing service confusion."
  local FIX="Align hostnames: sudo hostnamectl set-hostname <name>"

  if [[ ! -f /etc/hostname ]]; then
    record_check_skip "$CODE" "/etc/hostname missing."
    return
  fi

  local file_host runtime_host
  file_host=$(tr -d '\n' </etc/hostname)
  runtime_host=$(hostname 2>/dev/null)
  if [[ -z "$file_host" || -z "$runtime_host" ]]; then
    record_check_skip "$CODE" "Unable to determine hostnames."
    return
  fi

  if [[ "$file_host" != "$runtime_host" ]]; then
    local REASON_DETAIL="${REASON} File: ${file_host}, Runtime: ${runtime_host}"
    set_fix_status "pending" "Run sudo hostnamectl set-hostname ${file_host}"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Hostnames consistent (${runtime_host})."
  fi
}

check_sys_machine_id() {
  increment_total_checks
  local CODE="SYS012"
  local MESSAGE="Machine ID missing or default."
  local REASON="/etc/machine-id empty leading to duplicated IDs."
  local FIX="Regenerate: sudo systemd-machine-id-setup"

  if [[ ! -f /etc/machine-id ]]; then
    set_fix_status "pending" "Run sudo systemd-machine-id-setup"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  local id
  id=$(tr -d '\n' </etc/machine-id)
  if [[ -z "$id" || "$id" == "00000000000000000000000000000000" ]]; then
    set_fix_status "pending" "Regenerate machine-id"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Machine ID present."
  fi
}

check_sys_masked_units() {
  increment_total_checks
  local CODE="SYS013"
  local MESSAGE="Essential units masked."
  local REASON="systemctl list-unit-files reports masked targets or services."
  local FIX="Unmask units: sudo systemctl unmask <unit>"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  local masked
  masked=$(systemctl list-unit-files --state=masked --no-legend 2>/dev/null | head -n 5)
  if [[ -n "$masked" ]]; then
    local REASON_DETAIL="${REASON} Examples: ${masked//$'\n'/; }"
    set_fix_status "pending" "Unmask required units"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No masked units."
  fi
}

check_sys_broken_symlinks() {
  increment_total_checks
  local CODE="SYS014"
  local MESSAGE="Broken system symlinks detected."
  local REASON="find reports symbolic links in /etc pointing to missing targets."
  local FIX="Review link targets and recreate missing files"

  if ! command_exists find; then
    record_check_skip "$CODE" "find utility missing."
    return
  fi

  local broken
  broken=$(find /etc -xtype l 2>/dev/null | head -n 10)
  if [[ -n "$broken" ]]; then
    local REASON_DETAIL="${REASON} Examples: ${broken//$'\n'/; }"
    set_fix_status "pending" "Repair or remove broken symlinks"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No broken symlinks under /etc."
  fi
}
