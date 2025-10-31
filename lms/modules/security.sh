#!/usr/bin/env bash
# Security diagnostics: highlights weak configurations and disabled protections.

if [[ -n "${LMS_SECURITY_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_SECURITY_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_security_checks() {
  print_heading "Security Diagnostics"
  check_sec_ssh_root_login
  check_sec_ssh_password_auth
  check_sec_ufw_status
  check_sec_fail2ban
  check_sec_apparmor
  check_sec_uid0_users
  check_sec_empty_passwords
  check_sec_sticky_bit_dirs
  check_sec_userns_clone
  check_sec_dmesg_restrict
  check_sec_aslr
  check_sec_reboot_required
  check_sec_passwordless_sudo
  check_sec_pending_security_updates
}

check_sec_ssh_root_login() {
  increment_total_checks
  local CODE="SEC001"
  local MESSAGE="SSH allows direct root login."
  local REASON="PermitRootLogin is set to yes in sshd_config."
  local FIX="Harden SSH: set PermitRootLogin prohibit-password"

  local config="/etc/ssh/sshd_config"
  if [[ ! -f "$config" ]]; then
    record_check_skip "$CODE" "sshd_config missing."
    return
  fi

  if grep -Ei '^[[:space:]]*PermitRootLogin[[:space:]]+yes' "$config" >/dev/null 2>&1; then
    set_fix_status "pending" "Edit sshd_config to disable root login"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Root login disabled."
  fi
}

check_sec_ssh_password_auth() {
  increment_total_checks
  local CODE="SEC002"
  local MESSAGE="SSH password authentication enabled."
  local REASON="PasswordAuthentication yes allows credential brute force."
  local FIX="Set PasswordAuthentication no and use keys"

  local config="/etc/ssh/sshd_config"
  if [[ ! -f "$config" ]]; then
    record_check_skip "$CODE" "sshd_config missing."
    return
  fi

  if ! grep -Eiq '^[[:space:]]*PasswordAuthentication[[:space:]]+no' "$config"; then
    set_fix_status "pending" "Disable password auth in sshd_config"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "SSH password auth disabled."
  fi
}

check_sec_ufw_status() {
  increment_total_checks
  local CODE="SEC003"
  local MESSAGE="Firewall (UFW) disabled."
  local REASON="ufw status reports inactive firewall."
  local FIX="Enable firewall: sudo ufw enable"

  if ! command_exists ufw; then
    record_check_skip "$CODE" "UFW not installed."
    return
  fi

  if ufw status 2>/dev/null | grep -qi 'inactive'; then
    set_fix_status "pending" "Review rules then enable ufw"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "UFW firewall active."
  fi
}

check_sec_fail2ban() {
  increment_total_checks
  local CODE="SEC004"
  local MESSAGE="Fail2ban service inactive."
  local REASON="fail2ban.service is disabled or not running."
  local FIX="Restart service: sudo systemctl restart fail2ban"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if systemctl list-unit-files | grep -q '^fail2ban\.service'; then
    if ! systemctl is-active fail2ban >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted fail2ban" "sudo systemctl restart fail2ban"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "Fail2ban not installed."
    return
  fi

  record_check_ok "$CODE" "Fail2ban active."
}

check_sec_apparmor() {
  increment_total_checks
  local CODE="SEC005"
  local MESSAGE="AppArmor protection disabled."
  local REASON="AppArmor framework not enforcing security profiles."
  local FIX="Enable AppArmor: sudo systemctl enable --now apparmor"

  if command_exists aa-status; then
    if ! aa-status --enabled >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled AppArmor" "sudo systemctl restart apparmor"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  elif command_exists systemctl && systemctl list-unit-files | grep -q '^apparmor\.service'; then
    if ! systemctl is-active apparmor >/dev/null 2>&1; then
      attempt_fix_cmd "Started AppArmor" "sudo systemctl restart apparmor"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "AppArmor utilities missing."
    return
  fi

  record_check_ok "$CODE" "AppArmor enforcing."
}

check_sec_uid0_users() {
  increment_total_checks
  local CODE="SEC006"
  local MESSAGE="Additional UID 0 accounts detected."
  local REASON="/etc/passwd contains accounts other than root with UID 0."
  local FIX="Review privileged accounts and adjust IDs"

  if [[ ! -r /etc/passwd ]]; then
    record_check_skip "$CODE" "/etc/passwd not readable."
    return
  fi

  local privileged
  privileged=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
  if [[ -n "$privileged" ]]; then
    local REASON_DETAIL="${REASON} Accounts: ${privileged//$'\n'/, }"
    set_fix_status "pending" "Investigate UID 0 users"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No extra UID 0 users."
  fi
}

check_sec_empty_passwords() {
  increment_total_checks
  local CODE="SEC007"
  local MESSAGE="Accounts with empty passwords."
  local REASON="/etc/shadow entries contain blank password fields."
  local FIX="Lock the account: sudo passwd -l <user>"

  if [[ ! -r /etc/shadow ]]; then
    record_check_skip "$CODE" "/etc/shadow not readable."
    return
  fi

  local empty
  empty=$(awk -F: '$2 == "" {print $1}' /etc/shadow)
  if [[ -n "$empty" ]]; then
    local REASON_DETAIL="${REASON} Users: ${empty//$'\n'/, }"
    set_fix_status "pending" "Lock accounts with sudo passwd -l"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No empty password accounts."
  fi
}

check_sec_sticky_bit_dirs() {
  increment_total_checks
  local CODE="SEC008"
  local MESSAGE="World-writable directory missing sticky bit."
  local REASON="Shared directories like /tmp require sticky bit to prevent file hijack."
  local FIX="Apply sticky bit: sudo chmod 1777 <dir>"

  local dirs=(/tmp /var/tmp /dev/shm)
  local offenders=()
  local dir
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    local perms
    perms=$(stat -c '%A' "$dir" 2>/dev/null)
    if [[ -n "$perms" && "$perms" != *t ]]; then
      offenders+=("$dir")
    fi
  done

  if (( ${#offenders[@]} > 0 )); then
    local REASON_DETAIL="${REASON} Affected: ${offenders[*]}"
    set_fix_status "pending" "Set chmod 1777 on shared temp directories"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Sticky bit set on temp directories."
  fi
}

check_sec_userns_clone() {
  increment_total_checks
  local CODE="SEC009"
  local MESSAGE="Unprivileged user namespaces enabled."
  local REASON="kernel.unprivileged_userns_clone=1 allows privilege-escalation vectors."
  local FIX="Disable feature: sudo sysctl kernel.unprivileged_userns_clone=0"

  local file="/proc/sys/kernel/unprivileged_userns_clone"
  if [[ ! -r "$file" ]]; then
    record_check_skip "$CODE" "userns sysctl missing."
    return
  fi

  local value
  value=$(cat "$file")
  if [[ "$value" == "1" ]]; then
    attempt_fix_cmd "Disabled unprivileged user namespaces" "sudo sysctl kernel.unprivileged_userns_clone=0"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Unprivileged user namespaces disabled."
  fi
}

check_sec_dmesg_restrict() {
  increment_total_checks
  local CODE="SEC010"
  local MESSAGE="Kernel dmesg accessible to users."
  local REASON="kernel.dmesg_restrict is 0 allowing info disclosure."
  local FIX="Restrict dmesg: sudo sysctl kernel.dmesg_restrict=1"

  local file="/proc/sys/kernel/dmesg_restrict"
  if [[ ! -r "$file" ]]; then
    record_check_skip "$CODE" "dmesg_restrict sysctl missing."
    return
  fi

  local value
  value=$(cat "$file")
  if [[ "$value" == "0" ]]; then
    attempt_fix_cmd "Enabled dmesg restrictions" "sudo sysctl kernel.dmesg_restrict=1"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "dmesg restricted (value=${value})."
  fi
}

check_sec_aslr() {
  increment_total_checks
  local CODE="SEC011"
  local MESSAGE="ASLR disabled."
  local REASON="/proc/sys/kernel/randomize_va_space is set to 0."
  local FIX="Enable ASLR: sudo sysctl kernel.randomize_va_space=2"

  local file="/proc/sys/kernel/randomize_va_space"
  if [[ ! -r "$file" ]]; then
    record_check_skip "$CODE" "ASLR sysctl missing."
    return
  fi

  local value
  value=$(cat "$file")
  if [[ "$value" == "0" ]]; then
    attempt_fix_cmd "Enabled ASLR" "sudo sysctl kernel.randomize_va_space=2"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "ASLR enabled (value=${value})."
  fi
}

check_sec_reboot_required() {
  increment_total_checks
  local CODE="SEC012"
  local MESSAGE="Pending security reboot required."
  local REASON="/var/run/reboot-required present after kernel or libc updates."
  local FIX="Schedule reboot: sudo reboot"

  if [[ -f /var/run/reboot-required ]]; then
    set_fix_status "pending" "Plan a reboot to apply security patches"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No forced reboot required."
  fi
}

check_sec_passwordless_sudo() {
  increment_total_checks
  local CODE="SEC013"
  local MESSAGE="Passwordless sudo entries found."
  local REASON="Sudoers configuration grants NOPASSWD to groups or users."
  local FIX="Review sudoers and remove NOPASSWD entries"

  local sudo_files=(/etc/sudoers /etc/sudoers.d/*)
  local matches=()
  local file
  for file in "${sudo_files[@]}"; do
    [[ -f "$file" ]] || continue
    if grep -E 'NOPASSWD' "$file" >/dev/null 2>&1; then
      matches+=("$file")
    fi
  done

  if (( ${#matches[@]} > 0 )); then
    local REASON_DETAIL="${REASON} Files: ${matches[*]}"
    set_fix_status "pending" "Harden sudoers by removing NOPASSWD"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No passwordless sudo rules."
  fi
}

check_sec_pending_security_updates() {
  increment_total_checks
  local CODE="SEC014"
  local MESSAGE="Unapplied security updates available."
  local REASON="apt list --upgradable reports packages from security repositories."
  local FIX="Install updates: sudo apt-get upgrade --with-new-pkgs"

  if ! command_exists apt-get; then
    record_check_skip "$CODE" "APT tools missing."
    return
  fi

  local updates
  updates=$(apt list --upgradable 2>/dev/null | grep -E 'security' || true)
  if [[ -n "$updates" ]]; then
    set_fix_status "pending" "Apply security updates via sudo apt-get upgrade"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No pending security updates."
  fi
}
