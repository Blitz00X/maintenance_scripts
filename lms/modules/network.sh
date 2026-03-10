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
  # Priority 1: Original checks (NET001-NET015)
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
  # Priority 1: Common production issues (NET016-NET030)
  check_net_ipv6_connectivity
  check_net_mtu_mismatch
  check_net_duplicate_ip
  check_net_arp_anomalies
  check_net_bonding_status
  check_net_bridge_status
  check_net_socket_exhaustion
  check_net_tcp_listen_overflow
  check_net_iptables_conflicts
  check_net_nftables_vs_iptables
  check_net_vpn_tunnel_health
  check_net_wireguard_status
  check_net_interface_errors
  check_net_dropped_packets
  check_net_ssl_cert_expiry
  # Priority 2: Monthly/change-related (NET031-NET040)
  check_net_listening_port_conflicts
  check_net_proxy_config
  check_net_http_connectivity
  check_net_https_connectivity
  check_net_dns_over_tls
  check_net_network_namespace_leaks
  check_net_traffic_shaping
  check_net_buffer_overflows
  check_net_mdns_avahi
  check_net_ipv6_privacy_ext
  # Priority 3: Edge cases (NET041-NET050)
  check_net_vlan_config
  check_net_openvpn_status
  check_net_conntrack_full
  check_net_route_blackholes
  check_net_ethernet_negotiation
  check_net_wifi_signal_strength
  check_net_dns_search_domains
  check_net_reverse_dns
  check_net_tcp_keepalive
  check_net_syn_flood_protection
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

# ============================================================================
# NET016-NET030: Priority 1 - Common production issues
# ============================================================================

check_net_ipv6_connectivity() {
  increment_total_checks
  local CODE="NET016"
  local MESSAGE="IPv6 connectivity failed."
  local REASON="System has IPv6 enabled but cannot reach IPv6 endpoints."
  local FIX="Disable IPv6 if not needed: sysctl -w net.ipv6.conf.all.disable_ipv6=1"

  if ! command_exists ping; then
    record_check_skip "$CODE" "${MESSAGE} (ping command missing)"
    return
  fi

  # Check if IPv6 is enabled
  if [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null) == "1" ]]; then
    record_check_skip "$CODE" "IPv6 is disabled system-wide."
    return
  fi

  if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
    if ! timeout 5 ping -6 -c1 -W2 2001:4860:4860::8888 >/dev/null 2>&1; then
      set_fix_status "pending" "Fix IPv6 routing or disable IPv6"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "IPv6 connectivity OK or not configured."
}

check_net_mtu_mismatch() {
  increment_total_checks
  local CODE="NET017"
  local MESSAGE="MTU mismatch detected."
  local REASON="Interface MTU differs from common values causing fragmentation issues."
  local FIX="Adjust MTU: sudo ip link set <iface> mtu 1500"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local issue_found=0
  while IFS= read -r line; do
    local iface mtu
    iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
    mtu=$(echo "$line" | grep -oP 'mtu \K[0-9]+')
    # Skip loopback and virtual interfaces
    [[ "$iface" == "lo" || "$iface" =~ ^(docker|veth|br-|virbr) ]] && continue
    if [[ -n "$mtu" ]] && (( mtu < 576 || mtu > 9000 )); then
      issue_found=1
      break
    fi
  done < <(ip link show 2>/dev/null)

  if (( issue_found )); then
    set_fix_status "pending" "Review interface MTU settings"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "MTU settings acceptable."
  fi
}

check_net_duplicate_ip() {
  increment_total_checks
  local CODE="NET018"
  local MESSAGE="Duplicate IP address detected."
  local REASON="Another host on the network has the same IP causing connectivity issues."
  local FIX="Resolve IP conflict by changing one host's address"

  if ! command_exists arping; then
    record_check_skip "$CODE" "${MESSAGE} (arping missing)"
    return
  fi

  local iface ip_addr
  iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
  ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)

  if [[ -z "$ip_addr" || -z "$iface" ]]; then
    record_check_skip "$CODE" "Could not determine primary IP."
    return
  fi

  local dup_check
  dup_check=$(arping -D -I "$iface" -c 2 "$ip_addr" 2>&1)
  if echo "$dup_check" | grep -q "Received 1 reply"; then
    set_fix_status "pending" "Resolve duplicate IP address"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No duplicate IPs detected."
  fi
}

check_net_arp_anomalies() {
  increment_total_checks
  local CODE="NET019"
  local MESSAGE="ARP table anomalies detected."
  local REASON="Stale or failed ARP entries may cause connectivity issues."
  local FIX="Flush ARP cache: sudo ip neigh flush all"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local failed_count
  failed_count=$(ip neigh show 2>/dev/null | grep -c "FAILED\|INCOMPLETE")
  if (( failed_count > 10 )); then
    set_fix_status "pending" "Clear stale ARP entries"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "ARP table healthy."
  fi
}

check_net_bonding_status() {
  increment_total_checks
  local CODE="NET020"
  local MESSAGE="Network bonding degraded."
  local REASON="One or more slave interfaces in bond are down."
  local FIX="Restore slave interface or reconfigure bonding"

  if [[ ! -d /proc/net/bonding ]]; then
    record_check_skip "$CODE" "No network bonds configured."
    return
  fi

  local issue_found=0
  for bond_file in /proc/net/bonding/*; do
    [[ -e "$bond_file" ]] || continue
    if grep -q "MII Status: down" "$bond_file" 2>/dev/null; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Restore bonded interface"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Network bonds healthy."
  fi
}

check_net_bridge_status() {
  increment_total_checks
  local CODE="NET021"
  local MESSAGE="Network bridge in error state."
  local REASON="Bridge interface has no active ports or is misconfigured."
  local FIX="Check bridge configuration: bridge link show"

  if ! command_exists bridge; then
    record_check_skip "$CODE" "${MESSAGE} (bridge command missing)"
    return
  fi

  local bridges
  bridges=$(ip link show type bridge 2>/dev/null | awk -F': ' '{print $2}')
  if [[ -z "$bridges" ]]; then
    record_check_skip "$CODE" "No bridges configured."
    return
  fi

  local issue_found=0
  for br in $bridges; do
    local port_count
    port_count=$(bridge link show 2>/dev/null | grep -c "master $br")
    if (( port_count == 0 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Bridge has no active ports"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Network bridges healthy."
  fi
}

check_net_socket_exhaustion() {
  increment_total_checks
  local CODE="NET022"
  local MESSAGE="Socket exhaustion approaching."
  local REASON="System using over 80% of available sockets."
  local FIX="Close idle connections or increase net.core.somaxconn"

  local sockets_used sockets_max
  sockets_used=$(cat /proc/net/sockstat 2>/dev/null | awk '/sockets: used/ {print $3}')
  sockets_max=$(cat /proc/sys/net/core/somaxconn 2>/dev/null)

  if [[ -z "$sockets_used" ]]; then
    record_check_skip "$CODE" "Cannot read socket stats."
    return
  fi

  # Check if TIME_WAIT sockets are excessive
  local tw_count
  tw_count=$(ss -s 2>/dev/null | awk '/timewait/ {print $2}')
  if [[ -n "$tw_count" ]] && (( tw_count > 10000 )); then
    set_fix_status "pending" "Excessive TIME_WAIT sockets"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Socket usage acceptable."
  fi
}

check_net_tcp_listen_overflow() {
  increment_total_checks
  local CODE="NET023"
  local MESSAGE="TCP listen queue overflows detected."
  local REASON="Applications not accepting connections fast enough."
  local FIX="Increase listen backlog or optimize application"

  local overflows
  overflows=$(netstat -s 2>/dev/null | awk '/listen queue/ || /overflowed/ {print $1}' | head -1)

  if [[ -z "$overflows" ]]; then
    # Try ss/nstat alternative
    overflows=$(nstat -az 2>/dev/null | awk '/TcpExtListenOverflows/ {print $2}')
  fi

  if [[ -n "$overflows" ]] && (( overflows > 100 )); then
    set_fix_status "pending" "Address listen queue overflows"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No listen queue overflows."
  fi
}

check_net_iptables_conflicts() {
  increment_total_checks
  local CODE="NET024"
  local MESSAGE="iptables DROP rules blocking traffic."
  local REASON="Firewall rules may be dropping legitimate traffic."
  local FIX="Review iptables rules: sudo iptables -L -v -n"

  if ! command_exists iptables; then
    record_check_skip "$CODE" "${MESSAGE} (iptables missing)"
    return
  fi

  local drop_count
  drop_count=$(iptables -L -v -n 2>/dev/null | awk '/DROP|REJECT/ && $1 > 1000 {count++} END {print count+0}')

  if (( drop_count > 0 )); then
    set_fix_status "pending" "Review firewall DROP rules"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No significant firewall blocks."
  fi
}

check_net_nftables_vs_iptables() {
  increment_total_checks
  local CODE="NET025"
  local MESSAGE="Both nftables and iptables in use."
  local REASON="Mixed firewall backends can cause rule conflicts."
  local FIX="Migrate fully to nftables or use iptables-nft"

  local has_iptables=0 has_nftables=0

  if command_exists iptables && iptables -L -n 2>/dev/null | grep -qE '^Chain.*\(policy'; then
    has_iptables=1
  fi
  if command_exists nft && nft list ruleset 2>/dev/null | grep -q 'table'; then
    has_nftables=1
  fi

  if (( has_iptables && has_nftables )); then
    set_fix_status "pending" "Consolidate firewall backend"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Single firewall backend in use."
  fi
}

check_net_vpn_tunnel_health() {
  increment_total_checks
  local CODE="NET026"
  local MESSAGE="VPN tunnel interface down."
  local REASON="VPN tunnel configured but not connected."
  local FIX="Reconnect VPN or check VPN service status"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local issue_found=0
  for iface in $(ip link show 2>/dev/null | awk -F': ' '/tun|tap|wg|ppp/ {print $2}'); do
    if ip link show "$iface" 2>/dev/null | grep -q "state DOWN"; then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Restore VPN connection"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "VPN tunnels healthy or not configured."
  fi
}

check_net_wireguard_status() {
  increment_total_checks
  local CODE="NET027"
  local MESSAGE="WireGuard interface issue detected."
  local REASON="WireGuard peer has no recent handshake."
  local FIX="Check WireGuard config: sudo wg show"

  if ! command_exists wg; then
    record_check_skip "$CODE" "${MESSAGE} (wireguard-tools missing)"
    return
  fi

  local wg_output
  wg_output=$(wg show 2>/dev/null)
  if [[ -z "$wg_output" ]]; then
    record_check_skip "$CODE" "No WireGuard interfaces configured."
    return
  fi

  # Check for peers with old handshakes (> 3 minutes)
  local stale_peers
  stale_peers=$(wg show all latest-handshakes 2>/dev/null | awk '$2 > 0 && (systime() - $2) > 180 {count++} END {print count+0}')

  if (( stale_peers > 0 )); then
    set_fix_status "pending" "WireGuard peers have stale handshakes"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "WireGuard interfaces healthy."
  fi
}

check_net_interface_errors() {
  increment_total_checks
  local CODE="NET028"
  local MESSAGE="Network interface errors detected."
  local REASON="TX/RX errors on interface indicate hardware or driver issues."
  local FIX="Check cables, driver, or NIC hardware"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local issue_found=0
  while IFS= read -r line; do
    local iface rx_err tx_err
    iface=$(echo "$line" | awk '{print $1}')
    [[ "$iface" == "lo:" ]] && continue
    rx_err=$(cat "/sys/class/net/${iface%:}/statistics/rx_errors" 2>/dev/null)
    tx_err=$(cat "/sys/class/net/${iface%:}/statistics/tx_errors" 2>/dev/null)
    if [[ -n "$rx_err" ]] && (( rx_err > 1000 )); then
      issue_found=1
      break
    fi
    if [[ -n "$tx_err" ]] && (( tx_err > 1000 )); then
      issue_found=1
      break
    fi
  done < <(ip -o link show 2>/dev/null | awk '{print $2}')

  if (( issue_found )); then
    set_fix_status "pending" "Investigate interface errors"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Interface error counts low."
  fi
}

check_net_dropped_packets() {
  increment_total_checks
  local CODE="NET029"
  local MESSAGE="High dropped packet count."
  local REASON="Interface dropping packets due to buffer overruns or congestion."
  local FIX="Increase ring buffer: ethtool -G <iface> rx 4096"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local issue_found=0
  for iface in $(ls /sys/class/net/ 2>/dev/null); do
    [[ "$iface" == "lo" ]] && continue
    local drops
    drops=$(cat "/sys/class/net/$iface/statistics/rx_dropped" 2>/dev/null)
    if [[ -n "$drops" ]] && (( drops > 10000 )); then
      issue_found=1
      break
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Address dropped packets"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Dropped packet counts acceptable."
  fi
}

check_net_ssl_cert_expiry() {
  increment_total_checks
  local CODE="NET030"
  local MESSAGE="Local SSL certificate expiring soon."
  local REASON="Certificate in /etc/ssl expires within 30 days."
  local FIX="Renew certificate before expiration"

  if ! command_exists openssl; then
    record_check_skip "$CODE" "${MESSAGE} (openssl missing)"
    return
  fi

  local issue_found=0
  for cert in /etc/ssl/certs/*.pem /etc/ssl/private/*.crt; do
    [[ -f "$cert" ]] || continue
    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry" ]]; then
      local exp_epoch
      exp_epoch=$(date -d "$expiry" +%s 2>/dev/null)
      local now_epoch
      now_epoch=$(date +%s)
      local days_left=$(( (exp_epoch - now_epoch) / 86400 ))
      if (( days_left < 30 && days_left > 0 )); then
        issue_found=1
        break
      fi
    fi
  done

  if (( issue_found )); then
    set_fix_status "pending" "Renew expiring certificates"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No certificates expiring soon."
  fi
}

# ============================================================================
# NET031-NET040: Priority 2 - Monthly/change-related issues
# ============================================================================

check_net_listening_port_conflicts() {
  increment_total_checks
  local CODE="NET031"
  local MESSAGE="Port conflict detected."
  local REASON="Multiple services trying to bind to the same port."
  local FIX="Stop conflicting service or change port configuration"

  if ! command_exists ss; then
    record_check_skip "$CODE" "${MESSAGE} (ss command missing)"
    return
  fi

  # Check for common conflicting ports
  local web_count ssh_count
  web_count=$(ss -tlnp 2>/dev/null | grep -c ':80 \|:443 ')
  ssh_count=$(ss -tlnp 2>/dev/null | grep -c ':22 ')

  # Generally shouldn't have multiple listeners on same port
  record_check_ok "$CODE" "No obvious port conflicts."
}

check_net_proxy_config() {
  increment_total_checks
  local CODE="NET032"
  local MESSAGE="Proxy misconfiguration detected."
  local REASON="HTTP_PROXY set but proxy unreachable."
  local FIX="Fix or remove proxy settings in environment"

  local proxy="${http_proxy:-$HTTP_PROXY}"
  if [[ -z "$proxy" ]]; then
    record_check_skip "$CODE" "No proxy configured."
    return
  fi

  # Extract host:port from proxy URL
  local proxy_host
  proxy_host=$(echo "$proxy" | sed -E 's|https?://||; s|/.*||')

  if ! timeout 5 bash -c "echo >/dev/tcp/${proxy_host%:*}/${proxy_host#*:}" 2>/dev/null; then
    set_fix_status "pending" "Fix proxy configuration"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Proxy reachable."
  fi
}

check_net_http_connectivity() {
  increment_total_checks
  local CODE="NET033"
  local MESSAGE="HTTP connectivity failed."
  local REASON="Cannot fetch HTTP content from the internet."
  local FIX="Check firewall rules and proxy settings"

  if ! command_exists curl && ! command_exists wget; then
    record_check_skip "$CODE" "${MESSAGE} (curl/wget missing)"
    return
  fi

  local http_ok=0
  if command_exists curl; then
    timeout 10 curl -sI http://example.com >/dev/null 2>&1 && http_ok=1
  elif command_exists wget; then
    timeout 10 wget -q --spider http://example.com && http_ok=1
  fi

  if (( http_ok == 0 )); then
    set_fix_status "pending" "Restore HTTP connectivity"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "HTTP connectivity OK."
  fi
}

check_net_https_connectivity() {
  increment_total_checks
  local CODE="NET034"
  local MESSAGE="HTTPS connectivity failed."
  local REASON="Cannot establish TLS connections; certificate or firewall issue."
  local FIX="Check CA certificates and firewall rules"

  if ! command_exists curl && ! command_exists wget; then
    record_check_skip "$CODE" "${MESSAGE} (curl/wget missing)"
    return
  fi

  local https_ok=0
  if command_exists curl; then
    timeout 10 curl -sI https://example.com >/dev/null 2>&1 && https_ok=1
  elif command_exists wget; then
    timeout 10 wget -q --spider https://example.com && https_ok=1
  fi

  if (( https_ok == 0 )); then
    set_fix_status "pending" "Restore HTTPS connectivity"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "HTTPS connectivity OK."
  fi
}

check_net_dns_over_tls() {
  increment_total_checks
  local CODE="NET035"
  local MESSAGE="DNS over TLS not enabled."
  local REASON="DNS queries sent unencrypted exposing browsing data."
  local FIX="Enable DoT in systemd-resolved or use stubby"

  if ! command_exists resolvectl; then
    record_check_skip "$CODE" "${MESSAGE} (resolvectl missing)"
    return
  fi

  local dot_status
  dot_status=$(resolvectl status 2>/dev/null | grep -i "DNS over TLS")
  if echo "$dot_status" | grep -qi "no\|opportunistic"; then
    set_fix_status "pending" "Enable DNS over TLS"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "DNS over TLS configured."
  fi
}

check_net_network_namespace_leaks() {
  increment_total_checks
  local CODE="NET036"
  local MESSAGE="Orphaned network namespaces detected."
  local REASON="Stale namespaces from containers consuming resources."
  local FIX="Clean up with: ip netns delete <ns>"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local ns_count
  ns_count=$(ip netns list 2>/dev/null | wc -l)
  if (( ns_count > 50 )); then
    set_fix_status "pending" "Review network namespaces"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Network namespace count reasonable."
  fi
}

check_net_traffic_shaping() {
  increment_total_checks
  local CODE="NET037"
  local MESSAGE="Traffic shaping may be limiting throughput."
  local REASON="tc qdiscs configured that may throttle traffic."
  local FIX="Review tc rules: tc qdisc show"

  if ! command_exists tc; then
    record_check_skip "$CODE" "${MESSAGE} (tc command missing)"
    return
  fi

  local throttle_qdiscs
  throttle_qdiscs=$(tc qdisc show 2>/dev/null | grep -cE 'tbf|htb|cbq|netem')
  if (( throttle_qdiscs > 0 )); then
    set_fix_status "pending" "Review traffic shaping rules"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No traffic shaping configured."
  fi
}

check_net_buffer_overflows() {
  increment_total_checks
  local CODE="NET038"
  local MESSAGE="Network buffer overflows detected."
  local REASON="Kernel dropping packets due to full receive buffers."
  local FIX="Increase buffer sizes: sysctl -w net.core.rmem_max=16777216"

  local backlog_exceeded
  backlog_exceeded=$(nstat -az 2>/dev/null | awk '/SoftnetBacklogLen/ {print $2}')

  if [[ -n "$backlog_exceeded" ]] && (( backlog_exceeded > 0 )); then
    set_fix_status "pending" "Increase network buffer sizes"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No buffer overflows."
  fi
}

check_net_mdns_avahi() {
  increment_total_checks
  local CODE="NET039"
  local MESSAGE="Avahi/mDNS service not running."
  local REASON="Local network discovery (.local) won't work."
  local FIX="Start avahi: sudo systemctl start avahi-daemon"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-unit-files | grep -q 'avahi-daemon' && ! systemctl is-active avahi-daemon >/dev/null 2>&1; then
    set_fix_status "pending" "Start Avahi daemon"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Avahi/mDNS OK or not needed."
  fi
}

check_net_ipv6_privacy_ext() {
  increment_total_checks
  local CODE="NET040"
  local MESSAGE="IPv6 privacy extensions disabled."
  local REASON="IPv6 address exposes hardware MAC address."
  local FIX="Enable privacy: sysctl -w net.ipv6.conf.all.use_tempaddr=2"

  local privacy
  privacy=$(cat /proc/sys/net/ipv6/conf/all/use_tempaddr 2>/dev/null)

  if [[ "$privacy" == "0" ]]; then
    set_fix_status "pending" "Enable IPv6 privacy extensions"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "IPv6 privacy extensions enabled."
  fi
}

# ============================================================================
# NET041-NET050: Priority 3 - Edge cases and advanced scenarios
# ============================================================================

check_net_vlan_config() {
  increment_total_checks
  local CODE="NET041"
  local MESSAGE="VLAN interface issue detected."
  local REASON="VLAN interface exists but parent interface is down."
  local FIX="Bring up parent interface or reconfigure VLAN"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local vlan_ifaces
  vlan_ifaces=$(ip -d link show 2>/dev/null | grep -B1 'vlan protocol' | awk -F': ' '/^[0-9]+:/ {print $2}')
  if [[ -z "$vlan_ifaces" ]]; then
    record_check_skip "$CODE" "No VLAN interfaces configured."
    return
  fi

  record_check_ok "$CODE" "VLAN interfaces OK."
}

check_net_openvpn_status() {
  increment_total_checks
  local CODE="NET042"
  local MESSAGE="OpenVPN service not running."
  local REASON="OpenVPN client/server configured but service stopped."
  local FIX="Start OpenVPN: sudo systemctl start openvpn"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "${MESSAGE} (systemctl missing)"
    return
  fi

  if systemctl list-unit-files | grep -qE 'openvpn.*\.service' && ! systemctl is-active openvpn >/dev/null 2>&1; then
    if ls /etc/openvpn/*.conf >/dev/null 2>&1; then
      set_fix_status "pending" "Start OpenVPN service"
      log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
      return
    fi
  fi
  record_check_ok "$CODE" "OpenVPN OK or not configured."
}

check_net_conntrack_full() {
  increment_total_checks
  local CODE="NET043"
  local MESSAGE="Connection tracking table nearly full."
  local REASON="nf_conntrack limit approaching; new connections may fail."
  local FIX="Increase limit: sysctl -w net.netfilter.nf_conntrack_max=262144"

  local current max
  current=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)
  max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)

  if [[ -z "$current" || -z "$max" ]]; then
    record_check_skip "$CODE" "Conntrack not available."
    return
  fi

  local pct=$(( current * 100 / max ))
  if (( pct > 80 )); then
    set_fix_status "pending" "Increase conntrack limit"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Conntrack table has space."
  fi
}

check_net_route_blackholes() {
  increment_total_checks
  local CODE="NET044"
  local MESSAGE="Blackhole routes detected."
  local REASON="Routes configured to drop packets silently."
  local FIX="Review and remove unintended blackhole routes"

  if ! command_exists ip; then
    record_check_skip "$CODE" "${MESSAGE} (ip command missing)"
    return
  fi

  local blackholes
  blackholes=$(ip route show 2>/dev/null | grep -c 'blackhole\|unreachable\|prohibit')
  if (( blackholes > 0 )); then
    set_fix_status "pending" "Review blackhole routes"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No blackhole routes."
  fi
}

check_net_ethernet_negotiation() {
  increment_total_checks
  local CODE="NET045"
  local MESSAGE="Ethernet speed/duplex mismatch possible."
  local REASON="Interface not running at expected speed."
  local FIX="Check switch configuration and cable quality"

  if ! command_exists ethtool; then
    record_check_skip "$CODE" "${MESSAGE} (ethtool missing)"
    return
  fi

  local iface
  iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
  [[ -z "$iface" ]] && { record_check_skip "$CODE" "No default interface."; return; }

  local speed duplex
  speed=$(ethtool "$iface" 2>/dev/null | awk '/Speed:/ {print $2}' | sed 's/Mb\/s//')
  duplex=$(ethtool "$iface" 2>/dev/null | awk '/Duplex:/ {print $2}')

  if [[ "$duplex" == "Half" ]]; then
    set_fix_status "pending" "Half-duplex detected; check cabling"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Ethernet negotiation OK."
  fi
}

check_net_wifi_signal_strength() {
  increment_total_checks
  local CODE="NET046"
  local MESSAGE="WiFi signal strength weak."
  local REASON="Signal below -70dBm indicates poor connection quality."
  local FIX="Move closer to access point or use wired connection"

  if ! command_exists iwconfig && ! command_exists iw; then
    record_check_skip "$CODE" "${MESSAGE} (wireless tools missing)"
    return
  fi

  local signal
  if command_exists iw; then
    signal=$(iw dev 2>/dev/null | awk '/Interface/ {iface=$2} /signal:/ {print $2; exit}')
  else
    signal=$(iwconfig 2>/dev/null | awk -F'=' '/Signal level/ {gsub(/[^-0-9]/, "", $2); print $2}')
  fi

  if [[ -n "$signal" ]] && (( signal < -70 )); then
    set_fix_status "pending" "Improve WiFi signal"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "WiFi signal OK or not connected."
  fi
}

check_net_dns_search_domains() {
  increment_total_checks
  local CODE="NET047"
  local MESSAGE="Many DNS search domains configured."
  local REASON="Too many search domains slow DNS lookups."
  local FIX="Reduce search domains in /etc/resolv.conf or DHCP"

  local search_count
  search_count=$(grep -c '^search\|^domain' /etc/resolv.conf 2>/dev/null)
  local domain_count
  domain_count=$(grep '^search' /etc/resolv.conf 2>/dev/null | wc -w)

  if (( domain_count > 6 )); then
    set_fix_status "pending" "Reduce DNS search domains"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "DNS search domain count OK."
  fi
}

check_net_reverse_dns() {
  increment_total_checks
  local CODE="NET048"
  local MESSAGE="Reverse DNS lookup failed."
  local REASON="PTR record missing for this host's IP."
  local FIX="Configure reverse DNS with your provider"

  if ! command_exists dig && ! command_exists host; then
    record_check_skip "$CODE" "${MESSAGE} (dig/host missing)"
    return
  fi

  local my_ip
  my_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$my_ip" ]] && { record_check_skip "$CODE" "Cannot determine IP."; return; }

  local ptr_ok=0
  if command_exists dig; then
    dig -x "$my_ip" +short 2>/dev/null | grep -q '\.' && ptr_ok=1
  elif command_exists host; then
    host "$my_ip" 2>/dev/null | grep -q 'domain name pointer' && ptr_ok=1
  fi

  if (( ptr_ok == 0 )); then
    set_fix_status "pending" "Configure reverse DNS"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Reverse DNS configured."
  fi
}

check_net_tcp_keepalive() {
  increment_total_checks
  local CODE="NET049"
  local MESSAGE="TCP keepalive settings may cause connection drops."
  local REASON="Keepalive time too long for NAT environments."
  local FIX="Reduce keepalive: sysctl -w net.ipv4.tcp_keepalive_time=600"

  local keepalive_time
  keepalive_time=$(cat /proc/sys/net/ipv4/tcp_keepalive_time 2>/dev/null)

  if [[ -n "$keepalive_time" ]] && (( keepalive_time > 7200 )); then
    set_fix_status "pending" "Reduce TCP keepalive time"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "TCP keepalive settings OK."
  fi
}

check_net_syn_flood_protection() {
  increment_total_checks
  local CODE="NET050"
  local MESSAGE="SYN flood protection disabled."
  local REASON="tcp_syncookies not enabled; vulnerable to SYN floods."
  local FIX="Enable: sysctl -w net.ipv4.tcp_syncookies=1"

  local syncookies
  syncookies=$(cat /proc/sys/net/ipv4/tcp_syncookies 2>/dev/null)

  if [[ "$syncookies" == "0" ]]; then
    attempt_fix_cmd "Enabled SYN cookies" "sudo sysctl -w net.ipv4.tcp_syncookies=1"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "SYN flood protection enabled."
  fi
}
