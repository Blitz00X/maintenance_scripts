#!/usr/bin/env bash
# Network diagnostics module: identifies common connectivity and configuration problems.

if [[ -n "${LMS_NETWORK_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_NETWORK_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_network_checks() {
  print_heading "Network Diagnostics"
  check_net_internet_connectivity
  check_net_dns_resolution
  check_net_default_gateway
  check_net_default_interface_state
  check_net_packet_loss
  check_net_latency
  check_net_networkmanager_service
  check_net_resolved_service
  check_net_interface_addressing
  check_net_resolv_conf_nameserver
  check_net_sshd_listening
  check_net_time_sync_service
  check_net_hosts_loopback
  check_net_apipa_address
  check_net_resolv_conf_symlink
}

check_net_internet_connectivity() {
  increment_total_checks
  local CODE="NET001"
  local MESSAGE="Internet connectivity failed."
  local REASON="The system could not reach a public resolver (8.8.8.8)."
  local FIX="Check your connection or run: sudo systemctl restart NetworkManager"

  if ! command_exists ping; then
    record_check_skip "$CODE" "${MESSAGE} (ping command missing)"
    return
  fi

  if ! timeout 5 ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then
    if command_exists systemctl; then
      if (( LMS_AUTO_FIX_MODE )); then
        if systemctl restart NetworkManager >/dev/null 2>&1; then
          set_fix_status "fixed" "Restarted NetworkManager"
        else
          set_fix_status "failed" "systemctl restart NetworkManager failed"
        fi
      else
        set_fix_status "pending" "Run: sudo systemctl restart NetworkManager"
      fi
    else
      set_fix_status "failed" "systemctl utility unavailable"
    fi
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Internet connectivity is healthy."
  fi
}

check_net_dns_resolution() {
  increment_total_checks
  local CODE="NET002"
  local MESSAGE="DNS resolution failed."
  local REASON="The resolver could not translate common hostnames to IP addresses."
  local FIX="Restart DNS services: sudo systemctl restart systemd-resolved"

  if ! command_exists getent; then
    record_check_skip "$CODE" "${MESSAGE} (getent command missing)"
    return
  fi

  if ! getent ahosts archlinux.org >/dev/null 2>&1; then
    if command_exists systemctl; then
      attempt_fix_cmd "Restarted systemd-resolved" "sudo systemctl restart systemd-resolved"
    else
      set_fix_status "pending" "Run: sudo systemctl restart systemd-resolved"
    fi
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "DNS resolution responds correctly."
  fi
}

check_net_default_gateway() {
  increment_total_checks
  local CODE="NET003"
  local MESSAGE="No default gateway detected."
  local REASON="Routing table does not contain a default route for outbound traffic."
  local FIX="Restore routing: nmcli networking on && nmcli connection up <profile>"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  if ! ip route show default >/dev/null 2>&1; then
    set_fix_status "pending" "Configure a default gateway with nmcli or ip route"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Default gateway is present."
  fi
}

check_net_default_interface_state() {
  increment_total_checks
  local CODE="NET004"
  local MESSAGE="Default network interface is down."
  local REASON="The interface responsible for the default route reports DOWN state."
  local FIX="Bring link up: sudo ip link set <iface> up"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local iface
  iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
  if [[ -z "$iface" ]]; then
    record_check_skip "$CODE" "Default route absent; skipping interface state check."
    return
  fi

  if ip link show "$iface" | grep -q "state DOWN"; then
    set_fix_status "pending" "Run: sudo ip link set ${iface} up"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Interface ${iface} is up."
  fi
}

check_net_packet_loss() {
  increment_total_checks
  local CODE="NET005"
  local MESSAGE="High packet loss detected."
  local REASON="Ping statistics show more than 25% packet loss to 8.8.8.8."
  local FIX="Investigate network congestion or cabling; restart networking services"

  if ! command_exists ping; then
    record_check_skip "$CODE" "${MESSAGE} (ping command missing)"
    return
  fi

  local loss
  loss=$(timeout 10 ping -c4 -q 8.8.8.8 2>/dev/null | awk -F',' '/packet loss/ {gsub(/[^0-9.]/, "", $3); print $3}')
  if [[ -n "$loss" ]] && (( ${loss%%.*} > 25 )); then
    set_fix_status "pending" "Run diagnostics to reduce packet loss"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Packet loss within acceptable range."
  fi
}

check_net_latency() {
  increment_total_checks
  local CODE="NET006"
  local MESSAGE="Network latency is high."
  local REASON="Average round-trip time to 1.1.1.1 exceeds 200ms."
  local FIX="Check routing paths or ISP connectivity; consider restarting gateway"

  if ! command_exists ping; then
    record_check_skip "$CODE" "${MESSAGE} (ping command missing)"
    return
  fi

  local avg
  avg=$(timeout 10 ping -c4 -q 1.1.1.1 2>/dev/null | awk -F'/' 'END{print $5}')
  if [[ -n "$avg" ]]; then
    local avg_int=${avg%%.*}
    if (( avg_int > 200 )); then
      set_fix_status "pending" "Check uplink latency sources"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "Latency levels normal."
}

check_net_networkmanager_service() {
  increment_total_checks
  local CODE="NET007"
  local MESSAGE="NetworkManager service is inactive."
  local REASON="NetworkManager is required to manage network interfaces on many distributions."
  local FIX="Restore service: sudo systemctl restart NetworkManager"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl is-enabled NetworkManager >/dev/null 2>&1 && ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    attempt_fix_cmd "Restarted NetworkManager" "sudo systemctl restart NetworkManager"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "NetworkManager service active."
  fi
}

check_net_resolved_service() {
  increment_total_checks
  local CODE="NET008"
  local MESSAGE="systemd-resolved service is inactive."
  local REASON="The DNS stub resolver service is stopped, which breaks name resolution."
  local FIX="Restart service: sudo systemctl restart systemd-resolved"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-unit-files | grep -q '^systemd-resolved\.service' && ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
    attempt_fix_cmd "Restarted systemd-resolved" "sudo systemctl restart systemd-resolved"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "systemd-resolved running."
  fi
}

check_net_interface_addressing() {
  increment_total_checks
  local CODE="NET009"
  local MESSAGE="Default interface lacks an IPv4 address."
  local REASON="The interface handling default route does not have a valid IPv4 address assigned."
  local FIX="Request DHCP lease: sudo dhclient <iface>"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local iface
  iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
  if [[ -z "$iface" ]]; then
    record_check_skip "$CODE" "Default route absent; skipping address check."
    return
  fi

  if ! ip -4 addr show "$iface" | grep -q 'inet '; then
    set_fix_status "pending" "Request new DHCP lease with: sudo dhclient ${iface}"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "${iface} has an IPv4 address."
  fi
}

check_net_resolv_conf_nameserver() {
  increment_total_checks
  local CODE="NET010"
  local MESSAGE="/etc/resolv.conf lacks nameserver entries."
  local REASON="Without nameserver entries DNS lookups cannot be performed."
  local FIX="Update resolv.conf or restart systemd-resolved"

  if [[ ! -f /etc/resolv.conf ]]; then
    set_fix_status "pending" "Recreate /etc/resolv.conf with valid nameservers"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  if ! grep -E '^nameserver' /etc/resolv.conf >/dev/null 2>&1; then
    set_fix_status "pending" "Add nameserver entries such as 'nameserver 1.1.1.1'"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "resolv.conf contains nameservers."
  fi
}

check_net_sshd_listening() {
  increment_total_checks
  local CODE="NET011"
  local MESSAGE="SSH daemon is not listening on port 22."
  local REASON="The sshd service is down or restricted to other interfaces."
  local FIX="Start SSH daemon: sudo systemctl restart ssh"

  if ! command_exists ss; then
    record_check_skip "$CODE" "${MESSAGE} (ss command missing)"
    return
  fi

  if ! ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE '(:|\])22$'; then
    if command_exists systemctl; then
      attempt_fix_cmd "Restarted ssh service" "sudo systemctl restart ssh"
    else
      set_fix_status "pending" "Run: sudo systemctl restart ssh"
    fi
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "sshd is listening on port 22."
  fi
}

check_net_time_sync_service() {
  increment_total_checks
  local CODE="NET012"
  local MESSAGE="Time synchronization service inactive."
  local REASON="NTP client (systemd-timesyncd or chronyd) is stopped causing clock drift."
  local FIX="Restore time sync: sudo systemctl restart systemd-timesyncd"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-units --type=service | grep -q 'systemd-timesyncd'; then
    if ! systemctl is-active systemd-timesyncd >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted systemd-timesyncd" "sudo systemctl restart systemd-timesyncd"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  elif systemctl list-units --type=service | grep -q 'chronyd'; then
    if ! systemctl is-active chronyd >/dev/null 2>&1; then
      attempt_fix_cmd "Restarted chronyd" "sudo systemctl restart chronyd"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  else
    set_fix_status "pending" "Install and enable an NTP client"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  record_check_ok "$CODE" "Time synchronization service active."
}

check_net_hosts_loopback() {
  increment_total_checks
  local CODE="NET013"
  local MESSAGE="/etc/hosts missing loopback hostname entry."
  local REASON="Hostname not mapped to 127.0.1.1 causing local resolution failures."
  local FIX="Add '127.0.1.1 $(hostname)' to /etc/hosts"

  if [[ ! -f /etc/hosts ]]; then
    set_fix_status "pending" "Recreate /etc/hosts with loopback entries"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
    return
  fi

  local host
  host=$(hostname 2>/dev/null)
  if [[ -z "$host" ]]; then
    record_check_skip "$CODE" "Hostname unavailable."
    return
  fi

  if ! grep -E "127\.0\.1\.1\s+${host}(\s|$)" /etc/hosts >/dev/null 2>&1; then
    set_fix_status "pending" "Add loopback hostname mapping"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Loopback hostname mapping present."
  fi
}

check_net_apipa_address() {
  increment_total_checks
  local CODE="NET014"
  local MESSAGE="Interface using APIPA address."
  local REASON="DHCP failed and interface self-assigned an address in 169.254.0.0/16."
  local FIX="Renew DHCP lease: sudo dhclient <iface>"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local offenders
  offenders=$(ip -4 addr show scope global 2>/dev/null | awk '/inet 169\.254/{print $2" on "$7}')
  if [[ -n "$offenders" ]]; then
    local REASON_DETAIL="${REASON} Offending: ${offenders}"
    set_fix_status "pending" "Renew DHCP leases on affected interfaces"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No interfaces with APIPA addresses."
  fi
}

check_net_resolv_conf_symlink() {
  increment_total_checks
  local CODE="NET015"
  local MESSAGE="/etc/resolv.conf symlink is broken."
  local REASON="The resolv.conf symlink points to a missing file, breaking DNS lookups."
  local FIX="Recreate symlink: sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf"

  if [[ -L /etc/resolv.conf ]]; then
    local target
    target=$(readlink -f /etc/resolv.conf 2>/dev/null)
    if [[ -z "$target" || ! -f "$target" ]]; then
      set_fix_status "pending" "Recreate resolv.conf symlink"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "resolv.conf symlink valid."
}
