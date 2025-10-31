#!/usr/bin/env bash
# Package management diagnostics: identifies issues with APT, Snap, and Flatpak ecosystems.

if [[ -n "${LMS_PACKAGE_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_PACKAGE_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_package_checks() {
  print_heading "Package Management Diagnostics"
  check_pkg_apt_cache
  check_pkg_dpkg_lock
  check_pkg_dpkg_audit
  check_pkg_orphaned_packages
  check_pkg_holds
  check_pkg_update_staleness
  check_pkg_lists_presence
  check_pkg_snap_service
  check_pkg_snap_updates
  check_pkg_flatpak_service
  check_pkg_flatpak_updates
  check_pkg_unattended_upgrades
  check_pkg_sources_protocol
  check_pkg_partial_packages
}

check_pkg_apt_cache() {
  increment_total_checks
  local CODE="PKG001"
  local MESSAGE="Broken APT cache detected."
  local REASON="apt-get check returned errors indicating dependency or cache problems."
  local FIX="Repair cache: sudo apt-get clean && sudo apt-get update"

  if ! command_exists apt-get; then
    record_check_skip "$CODE" "${MESSAGE} (apt-get missing)"
    return
  fi

  if ! apt-get check >/dev/null 2>&1; then
    attempt_fix_cmd "Cleaned APT cache" "sudo apt-get clean && sudo apt-get update"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "APT cache is healthy."
  fi
}

check_pkg_dpkg_lock() {
  increment_total_checks
  local CODE="PKG002"
  local MESSAGE="APT/DPKG lock file present."
  local REASON="Lock files prevent package operations when leftover from interrupted runs."
  local FIX="Remove locks: sudo rm /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock"

  local locks=(/var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/apt/lists/lock)
  local found=()
  for lock in "${locks[@]}"; do
    if [[ -f "$lock" ]]; then
      if lsof "$lock" >/dev/null 2>&1; then
        continue
      fi
      found+=("$lock")
    fi
  done

  if (( ${#found[@]} > 0 )); then
    local REASON_DETAIL="${REASON} Found: ${found[*]}"
    set_fix_status "pending" "Remove stale locks with sudo rm"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No stale APT lock files."
  fi
}

check_pkg_dpkg_audit() {
  increment_total_checks
  local CODE="PKG003"
  local MESSAGE="Packages pending configuration."
  local REASON="dpkg --audit reports partially installed packages."
  local FIX="Complete setup: sudo dpkg --configure -a"

  if ! command_exists dpkg; then
    record_check_skip "$CODE" "${MESSAGE} (dpkg missing)"
    return
  fi

  local audit_output
  audit_output=$(dpkg --audit 2>/dev/null)
  if [[ -n "$audit_output" ]]; then
    local REASON_DETAIL="${REASON} Details: ${audit_output}" 
    set_fix_status "pending" "Run sudo dpkg --configure -a"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No packages awaiting configuration."
  fi
}

check_pkg_orphaned_packages() {
  increment_total_checks
  local CODE="PKG004"
  local MESSAGE="Orphaned packages detected."
  local REASON="apt autoremove list is non-empty, leaving unused dependencies."
  local FIX="Clean dependencies: sudo apt autoremove -y"

  if ! command_exists apt-get; then
    record_check_skip "$CODE" "${MESSAGE} (apt-get missing)"
    return
  fi

  local orphans
  orphans=$(apt-get -s autoremove 2>/dev/null | awk '/^Remv/ {packages++} END{print packages+0}')
  if [[ -n "$orphans" ]] && (( orphans > 0 )); then
    attempt_fix_cmd "Removed orphaned packages" "sudo apt autoremove -y"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No orphaned packages detected."
  fi
}

check_pkg_holds() {
  increment_total_checks
  local CODE="PKG005"
  local MESSAGE="Held packages block upgrades."
  local REASON="apt-mark showhold returned held packages."
  local FIX="Release holds: sudo apt-mark unhold <package>"

  if ! command_exists apt-mark; then
    record_check_skip "$CODE" "${MESSAGE} (apt-mark missing)"
    return
  fi

  local held
  held=$(apt-mark showhold 2>/dev/null)
  if [[ -n "$held" ]]; then
    local REASON_DETAIL="${REASON} Held: ${held//$'\n'/, }"
    set_fix_status "pending" "Review holds with apt-mark unhold"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No held packages."
  fi
}

check_pkg_update_staleness() {
  increment_total_checks
  local CODE="PKG006"
  local MESSAGE="APT lists are stale."
  local REASON="update-success-stamp older than 7 days indicates outdated package metadata."
  local FIX="Refresh lists: sudo apt-get update"

  local stamp="/var/lib/apt/periodic/update-success-stamp"
  if [[ ! -f "$stamp" ]]; then
    set_fix_status "pending" "Run sudo apt-get update"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  local now epoch age_days
  now=$(date +%s)
  epoch=$(stat -c %Y "$stamp" 2>/dev/null)
  if [[ -n "$epoch" ]]; then
    age_days=$(( (now - epoch) / 86400 ))
    if (( age_days > 7 )); then
      set_fix_status "pending" "Refresh package lists"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "APT metadata recently updated."
}

check_pkg_lists_presence() {
  increment_total_checks
  local CODE="PKG007"
  local MESSAGE="APT lists directory empty."
  local REASON="/var/lib/apt/lists lacks package metadata files."
  local FIX="Populate lists: sudo apt-get update"

  local list_dir="/var/lib/apt/lists"
  if [[ ! -d "$list_dir" ]]; then
    set_fix_status "pending" "Recreate ${list_dir} and update"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  if ! find "$list_dir" -maxdepth 1 -type f -name '*.lz4' -o -name '*Packages*' | grep -q '.'; then
    set_fix_status "pending" "Run sudo apt-get update"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "APT lists populated."
  fi
}

check_pkg_snap_service() {
  increment_total_checks
  local CODE="PKG008"
  local MESSAGE="Snapd service inactive."
  local REASON="snapd.service not running prevents snap package management."
  local FIX="Restart snapd: sudo systemctl restart snapd"

  if ! command_exists systemctl || ! command_exists snap; then
    record_check_skip "$CODE" "${MESSAGE} (snap/systemctl missing)"
    return
  fi

  if ! systemctl is-active snapd >/dev/null 2>&1; then
    attempt_fix_cmd "Restarted snapd" "sudo systemctl restart snapd"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "snapd service active."
  fi
}

check_pkg_snap_updates() {
  increment_total_checks
  local CODE="PKG009"
  local MESSAGE="Pending snap updates."
  local REASON="snap refresh --list reports outdated snaps."
  local FIX="Apply updates: sudo snap refresh"

  if ! command_exists snap; then
    record_check_skip "$CODE" "${MESSAGE} (snap missing)"
    return
  fi

  if snap refresh --list 2>/dev/null | tail -n +2 | grep -q '.'; then
    set_fix_status "pending" "Run sudo snap refresh"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No pending snap updates."
  fi
}

check_pkg_flatpak_service() {
  increment_total_checks
  local CODE="PKG010"
  local MESSAGE="Flatpak remotes disabled."
  local REASON="flatpak remotes shows disabled or missing default remotes."
  local FIX="Re-enable remotes: flatpak remote-modify --enable <remote>"

  if ! command_exists flatpak; then
    record_check_skip "$CODE" "${MESSAGE} (flatpak missing)"
    return
  fi

  local disabled
  disabled=$(flatpak remotes --columns=name,state 2>/dev/null | awk '/disabled/ {print $1}')
  if [[ -n "$disabled" ]]; then
    local REASON_DETAIL="${REASON} Disabled: ${disabled//$'\n'/, }"
    set_fix_status "pending" "Enable remotes with flatpak remote-modify"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Flatpak remotes enabled."
  fi
}

check_pkg_flatpak_updates() {
  increment_total_checks
  local CODE="PKG011"
  local MESSAGE="Flatpak updates available."
  local REASON="flatpak remote-ls --updates lists outdated runtimes or apps."
  local FIX="Update flatpaks: flatpak update -y"

  if ! command_exists flatpak; then
    record_check_skip "$CODE" "${MESSAGE} (flatpak missing)"
    return
  fi

  if flatpak remote-ls --updates 2>/dev/null | grep -q '.'; then
    set_fix_status "pending" "Run flatpak update"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Flatpaks up-to-date."
  fi
}

check_pkg_unattended_upgrades() {
  increment_total_checks
  local CODE="PKG012"
  local MESSAGE="Unattended upgrades disabled."
  local REASON="unattended-upgrades service is inactive or disabled."
  local FIX="Enable: sudo systemctl enable --now unattended-upgrades"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-unit-files | grep -q '^unattended-upgrades\.service'; then
    if ! systemctl is-enabled unattended-upgrades >/dev/null 2>&1 || ! systemctl is-active unattended-upgrades >/dev/null 2>&1; then
      attempt_fix_cmd "Enabled unattended-upgrades" "sudo systemctl enable --now unattended-upgrades"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    record_check_skip "$CODE" "unattended-upgrades not installed."
    return
  fi

  record_check_ok "$CODE" "Unattended upgrades active."
}

check_pkg_sources_protocol() {
  increment_total_checks
  local CODE="PKG013"
  local MESSAGE="APT sources using insecure HTTP."
  local REASON="Sources list entries rely on http:// instead of https://."
  local FIX="Update sources to HTTPS mirrors"

  if [[ ! -d /etc/apt ]]; then
    record_check_skip "$CODE" "APT configuration directory missing."
    return
  fi

  local insecure
  insecure=$(grep -Rho "^[[:space:]]*deb[[:space:]]\+http://" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null)
  if [[ -n "$insecure" ]]; then
    set_fix_status "pending" "Update sources to HTTPS endpoints"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "APT sources use HTTPS."
  fi
}

check_pkg_partial_packages() {
  increment_total_checks
  local CODE="PKG014"
  local MESSAGE="Partial .deb files in cache."
  local REASON="/var/cache/apt/archives/partial contains leftover downloads."
  local FIX="Clean cache: sudo apt-get clean"

  local partial_dir="/var/cache/apt/archives/partial"
  if [[ ! -d "$partial_dir" ]]; then
    record_check_skip "$CODE" "Partial cache directory absent."
    return
  fi

  if find "$partial_dir" -type f 2>/dev/null | grep -q '.'; then
    attempt_fix_cmd "Cleaned partial APT cache" "sudo apt-get clean"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No partial package downloads."
  fi
}
