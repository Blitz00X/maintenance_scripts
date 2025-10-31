#!/usr/bin/env bash
# Log diagnostics: monitors journal health, log file growth, and authentication anomalies.

if [[ -n "${LMS_LOG_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_LOG_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_log_checks() {
  print_heading "Log Health Diagnostics"
  check_log_journal_size
  check_log_syslog_size
  check_log_authlog_size
  check_log_auth_failures
  check_log_journal_integrity
  check_log_stale_rotations
  check_log_logrotate_timestamp
  check_log_journal_storage_mode
  check_log_persistent_directory
  check_log_kernel_traces
  check_log_coredumps
  check_log_journal_rate_limit
  check_log_wtmp_size
  check_log_btmp_size
}

check_log_journal_size() {
  increment_total_checks
  local CODE="LOG001"
  local MESSAGE="Journal consumes excessive disk space."
  local REASON="journalctl --disk-usage exceeds 1GB."
  local FIX="Vacuum logs: sudo journalctl --vacuum-size=100M"

  if ! command_exists journalctl; then
    record_check_skip "$CODE" "journalctl missing."
    return
  fi

  local usage
  usage=$(journalctl --disk-usage 2>/dev/null | awk '{print $(NF-1)}')
  local unit
  unit=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}')
  if [[ -n "$usage" && -n "$unit" ]]; then
    local bytes
    case "$unit" in
      B) bytes=$usage ;;
      KB) bytes=$(( usage * 1024 )) ;;
      MB) bytes=$(( usage * 1024 * 1024 )) ;;
      GB) bytes=$(( usage * 1024 * 1024 * 1024 )) ;;
      *) bytes=0 ;;
    esac
    if (( bytes > 1073741824 )); then
      attempt_fix_cmd "Vacuumed journal to 100M" "sudo journalctl --vacuum-size=100M"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "Journal size under 1GB."
}

check_log_syslog_size() {
  increment_total_checks
  local CODE="LOG002"
  local MESSAGE="/var/log/syslog larger than 200MB."
  local REASON="Large syslog indicates rotation or logging issues."
  local FIX="Force rotation: sudo logrotate -f /etc/logrotate.d/rsyslog"

  local file="/var/log/syslog"
  if [[ ! -f "$file" ]]; then
    record_check_skip "$CODE" "syslog missing."
    return
  fi

  local size
  size=$(stat -c %s "$file" 2>/dev/null)
  if [[ -n "$size" ]] && (( size > 209715200 )); then
    set_fix_status "pending" "Run logrotate for syslog"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "syslog size within limits."
  fi
}

check_log_authlog_size() {
  increment_total_checks
  local CODE="LOG003"
  local MESSAGE="/var/log/auth.log larger than 50MB."
  local REASON="Excessive authentication logs impact disk space."
  local FIX="Rotate auth logs: sudo logrotate -f /etc/logrotate.d/rsyslog"

  local file="/var/log/auth.log"
  if [[ ! -f "$file" ]]; then
    record_check_skip "$CODE" "auth.log missing."
    return
  fi

  local size
  size=$(stat -c %s "$file" 2>/dev/null)
  if [[ -n "$size" ]] && (( size > 52428800 )); then
    set_fix_status "pending" "Trigger logrotate for auth.log"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "auth.log size within limits."
  fi
}

check_log_auth_failures() {
  increment_total_checks
  local CODE="LOG004"
  local MESSAGE="Repeated authentication failures detected."
  local REASON="Last 200 auth.log lines show more than 10 failed logins."
  local FIX="Investigate source IPs and adjust fail2ban policies"

  local file="/var/log/auth.log"
  if [[ ! -f "$file" ]]; then
    record_check_skip "$CODE" "auth.log missing."
    return
  fi

  local failures
  failures=$(tail -n 200 "$file" 2>/dev/null | grep -c "Failed password")
  if [[ -n "$failures" ]] && (( failures > 10 )); then
    local REASON_DETAIL="${REASON} Count: ${failures}"
    set_fix_status "pending" "Strengthen SSH protections"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Authentication failure rate normal."
  fi
}

check_log_journal_integrity() {
  increment_total_checks
  local CODE="LOG005"
  local MESSAGE="Journal integrity errors detected."
  local REASON="journalctl --verify reported corrupted entries."
  local FIX="Flush corrupt segments: sudo journalctl --verify --disk-usage"

  if ! command_exists journalctl; then
    record_check_skip "$CODE" "journalctl missing."
    return
  fi

  if ! journalctl --verify >/tmp/lms_journal_verify 2>&1; then
    local output
    output=$(head -n 5 /tmp/lms_journal_verify)
    rm -f /tmp/lms_journal_verify
    local REASON_DETAIL="${REASON} Sample: ${output//$'\n'/; }"
    set_fix_status "pending" "Rotate journal to remove corruption"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    rm -f /tmp/lms_journal_verify
    record_check_ok "$CODE" "Journal verifies clean."
  fi
}

check_log_stale_rotations() {
  increment_total_checks
  local CODE="LOG006"
  local MESSAGE="Stale rotated logs older than 180 days."
  local REASON="find detected archived logs not purged for 6 months."
  local FIX="Purge stale logs: sudo find /var/log -name '*.gz' -mtime +180 -delete"

  if ! command_exists find; then
    record_check_skip "$CODE" "find missing."
    return
  fi

  local stale
  stale=$(find /var/log -type f -name '*.gz' -mtime +180 2>/dev/null | head -n 5)
  if [[ -n "$stale" ]]; then
    local REASON_DETAIL="${REASON} Examples: ${stale//$'\n'/; }"
    set_fix_status "pending" "Purge stale log archives"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No stale rotated logs."
  fi
}

check_log_logrotate_timestamp() {
  increment_total_checks
  local CODE="LOG007"
  local MESSAGE="logrotate hasn't run in 14 days."
  local REASON="/var/lib/logrotate/status timestamp older than two weeks."
  local FIX="Trigger rotation: sudo logrotate -f /etc/logrotate.conf"

  local status_file="/var/lib/logrotate/status"
  if [[ ! -f "$status_file" ]]; then
    set_fix_status "pending" "Run sudo logrotate -f /etc/logrotate.conf"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  local now epoch age
  now=$(date +%s)
  epoch=$(stat -c %Y "$status_file" 2>/dev/null)
  if [[ -n "$epoch" ]]; then
    age=$(( (now - epoch) / 86400 ))
    if (( age > 14 )); then
      set_fix_status "pending" "Run logrotate manually"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "logrotate ran ${age:-0} days ago."
}

check_log_journal_storage_mode() {
  increment_total_checks
  local CODE="LOG008"
  local MESSAGE="Journal configured for volatile storage."
  local REASON="/etc/systemd/journald.conf sets Storage=volatile, preventing persistence."
  local FIX="Set Storage=persistent and restart systemd-journald"

  local config="/etc/systemd/journald.conf"
  if [[ ! -f "$config" ]]; then
    record_check_skip "$CODE" "journald.conf missing."
    return
  fi

  if grep -Eiq '^Storage=volatile' "$config"; then
    set_fix_status "pending" "Adjust Storage=persistent and restart journald"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Journal storage persistent."
  fi
}

check_log_persistent_directory() {
  increment_total_checks
  local CODE="LOG009"
  local MESSAGE="Persistent journal directory missing."
  local REASON="/var/log/journal absent causing logs to be lost on reboot."
  local FIX="Create directory: sudo mkdir -p /var/log/journal"

  if [[ ! -d /var/log/journal ]]; then
    set_fix_status "pending" "Create /var/log/journal and restart systemd-journald"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "/var/log/journal present."
  fi
}

check_log_kernel_traces() {
  increment_total_checks
  local CODE="LOG010"
  local MESSAGE="Kernel stack traces detected."
  local REASON="dmesg contains 'Call Trace', suggesting kernel issues."
  local FIX="Inspect kernel logs and update drivers"

  if ! command_exists dmesg; then
    record_check_skip "$CODE" "dmesg missing."
    return
  fi

  if dmesg 2>/dev/null | tail -n 500 | grep -q "Call Trace"; then
    set_fix_status "pending" "Investigate kernel crash or hardware faults"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No kernel call traces."
  fi
}

check_log_coredumps() {
  increment_total_checks
  local CODE="LOG011"
  local MESSAGE="Application core dumps present."
  local REASON="coredumpctl list reports stored crashes."
  local FIX="Analyze crashes: coredumpctl info <PID>"

  if ! command_exists coredumpctl; then
    record_check_skip "$CODE" "coredumpctl missing."
    return
  fi

  if coredumpctl list 2>/dev/null | grep -q '[0-9]'; then
    set_fix_status "pending" "Review and prune core dumps"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No core dumps recorded."
  fi
}

check_log_journal_rate_limit() {
  increment_total_checks
  local CODE="LOG012"
  local MESSAGE="Journal rate limiting disabled."
  local REASON="RateLimitBurst=0 or RateLimitInterval=0 within journald.conf."
  local FIX="Restore defaults: sudo sed -i 's/RateLimitBurst=0/RateLimitBurst=2000/' /etc/systemd/journald.conf"

  local config="/etc/systemd/journald.conf"
  if [[ ! -f "$config" ]]; then
    record_check_skip "$CODE" "journald.conf missing."
    return
  fi

  if grep -Eq '^RateLimit(Burst|Interval)=0' "$config"; then
    set_fix_status "pending" "Reset RateLimitBurst/Interval to safe defaults"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Journal rate limiting enabled."
  fi
}

check_log_wtmp_size() {
  increment_total_checks
  local CODE="LOG013"
  local MESSAGE="/var/log/wtmp larger than 100MB."
  local REASON="Large login history slows utilities like last."
  local FIX="Truncate: sudo truncate -s 0 /var/log/wtmp"

  local file="/var/log/wtmp"
  if [[ ! -f "$file" ]]; then
    record_check_skip "$CODE" "wtmp missing."
    return
  fi

  local size
  size=$(stat -c %s "$file" 2>/dev/null)
  if [[ -n "$size" ]] && (( size > 104857600 )); then
    set_fix_status "pending" "Archive and truncate wtmp"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "wtmp size acceptable."
  fi
}

check_log_btmp_size() {
  increment_total_checks
  local CODE="LOG014"
  local MESSAGE="/var/log/btmp larger than 5MB."
  local REASON="Failed login history unusually large signaling brute-force attempts."
  local FIX="Archive: sudo truncate -s 0 /var/log/btmp"

  local file="/var/log/btmp"
  if [[ ! -f "$file" ]]; then
    record_check_skip "$CODE" "btmp missing."
    return
  fi

  local size
  size=$(stat -c %s "$file" 2>/dev/null)
  if [[ -n "$size" ]] && (( size > 5242880 )); then
    set_fix_status "pending" "Archive and truncate btmp"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "btmp size acceptable."
  fi
}
