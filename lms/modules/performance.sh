#!/usr/bin/env bash
# Performance diagnostics: monitors resource saturation and bottlenecks.

if [[ -n "${LMS_PERFORMANCE_MODULE_LOADED:-}" ]]; then
  return
fi
export LMS_PERFORMANCE_MODULE_LOADED=1

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTIL_DIR="${MODULE_DIR%/modules}/utils"
# shellcheck source=../utils/logger.sh
source "${UTIL_DIR}/logger.sh"

run_performance_checks() {
  print_heading "Performance Diagnostics"
  check_perf_load_average
  check_perf_thermal_throttle
  check_perf_ram_usage
  check_perf_swap_usage
  check_perf_process_count
  check_perf_zombie_processes
  check_perf_file_descriptors
  check_perf_slow_boot_services
  check_perf_oom_events
  check_perf_cpu_temperature
  check_perf_high_cpu_process
  check_perf_high_memory_process
  check_perf_swappiness
  check_perf_cpu_governor
  check_perf_memory_psi
  check_perf_systemd_oomd
}

check_perf_load_average() {
  increment_total_checks
  local CODE="PERF001"
  local MESSAGE="System load average is excessive."
  local REASON="1-minute load average exceeds 1.5x available CPU cores."
  local FIX="Identify heavy processes: top -o %CPU"

  local cores load_scaled threshold_scaled
  cores=$(nproc 2>/dev/null)
  load_scaled=$(awk '{printf "%d", $1 * 100}' /proc/loadavg 2>/dev/null)
  if [[ -z "$cores" || -z "$load_scaled" ]]; then
    record_check_skip "$CODE" "Unable to read load statistics."
    return
  fi

  threshold_scaled=$(( cores * 150 ))
  if (( load_scaled > threshold_scaled )); then
    set_fix_status "pending" "Reduce CPU intensive workloads"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    local load_display
    load_display=$(awk 'BEGIN { printf "%.2f", '"$load_scaled"' / 100 }')
    record_check_ok "$CODE" "Load average ${load_display} within capacity."
  fi
}

check_perf_thermal_throttle() {
  increment_total_checks
  local CODE="PERF002"
  local MESSAGE="CPU thermal throttling detected."
  local REASON="Kernel log records temperature-based CPU frequency throttling."
  local FIX="Improve cooling or clean heatsinks"

  if ! command_exists dmesg; then
    record_check_skip "$CODE" "${MESSAGE} (dmesg missing)"
    return
  fi

  if dmesg --time-format=iso 2>/dev/null | tail -n 200 | grep -i "thermal throttling" >/dev/null 2>&1; then
    set_fix_status "pending" "Inspect cooling solution"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No recent thermal throttling events."
  fi
}

check_perf_ram_usage() {
  increment_total_checks
  local CODE="PERF003"
  local MESSAGE="RAM utilization critical."
  local REASON="Used memory exceeds 90% of available RAM."
  local FIX="Stop leaking services or add more memory"

  if [[ ! -r /proc/meminfo ]]; then
    record_check_skip "$CODE" "meminfo unavailable."
    return
  fi

  local mem_total mem_available used_pct
  mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  if [[ -z "$mem_total" || -z "$mem_available" ]]; then
    record_check_skip "$CODE" "Unable to parse meminfo."
    return
  fi

  local used=$(( mem_total - mem_available ))
  used_pct=$(( used * 100 / mem_total ))
  if (( used_pct > 90 )); then
    set_fix_status "pending" "Free memory by restarting heavy services"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "RAM usage at ${used_pct}%"
  fi
}

check_perf_swap_usage() {
  increment_total_checks
  local CODE="PERF004"
  local MESSAGE="Swap usage excessive."
  local REASON="Swap utilization exceeds 60%, indicating memory pressure."
  local FIX="Investigate memory leaks and add RAM"

  if ! command_exists free; then
    record_check_skip "$CODE" "${MESSAGE} (free missing)"
    return
  fi

  local swap_total swap_used swap_pct
  read -r swap_total swap_used < <(free -m | awk '/Swap/ {print $2" "$3}')
  if [[ -z "$swap_total" || "$swap_total" -eq 0 ]]; then
    record_check_skip "$CODE" "Swap not configured."
    return
  fi
  swap_pct=$(( swap_used * 100 / swap_total ))
  if (( swap_pct > 60 )); then
    set_fix_status "pending" "Reduce swapping workloads"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Swap usage at ${swap_pct}%"
  fi
}

check_perf_process_count() {
  increment_total_checks
  local CODE="PERF005"
  local MESSAGE="Process count unusually high."
  local REASON="Number of processes exceeds 512, increasing scheduler overhead."
  local FIX="Review runaway processes with ps -e"

  if ! command_exists ps; then
    record_check_skip "$CODE" "${MESSAGE} (ps missing)"
    return
  fi

  local count
  count=$(ps -e --no-headers 2>/dev/null | wc -l)
  if [[ -n "$count" ]] && (( count > 512 )); then
    local REASON_DETAIL="${REASON} Count: ${count}"
    set_fix_status "pending" "Stop unnecessary background services"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Process count at ${count:-0}."
  fi
}

check_perf_zombie_processes() {
  increment_total_checks
  local CODE="PERF006"
  local MESSAGE="Zombie processes present."
  local REASON="ps reports defunct processes awaiting parent cleanup."
  local FIX="Restart parent service or kill orphaned processes"

  if ! command_exists ps; then
    record_check_skip "$CODE" "${MESSAGE} (ps missing)"
    return
  fi

  local zombies
  zombies=$(ps -eo stat 2>/dev/null | awk '/Z/ {z++} END{print z+0}')
  if (( zombies > 0 )); then
    local REASON_DETAIL="${REASON} Count: ${zombies}"
    set_fix_status "pending" "Identify parent with ps -ef | grep defunct"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "No zombie processes detected."
  fi
}

check_perf_file_descriptors() {
  increment_total_checks
  local CODE="PERF007"
  local MESSAGE="File descriptor usage nearing system limit."
  local REASON="/proc/sys/fs/file-nr indicates >80% utilization."
  local FIX="Increase fs.file-max or close unused services"

  if [[ ! -r /proc/sys/fs/file-nr ]]; then
    record_check_skip "$CODE" "file-nr unavailable."
    return
  fi

  read -r allocated unused max < /proc/sys/fs/file-nr
  if [[ -z "$max" || "$max" -eq 0 ]]; then
    record_check_skip "$CODE" "Invalid fs.file-nr data."
    return
  fi

  local in_use=$(( allocated - unused ))
  local pct=$(( in_use * 100 / max ))
  if (( pct > 80 )); then
    local REASON_DETAIL="${REASON} Usage: ${pct}%"
    set_fix_status "pending" "Tune fs.file-max and audit fd leaks"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "File descriptor usage at ${pct}%"
  fi
}

check_perf_slow_boot_services() {
  increment_total_checks
  local CODE="PERF008"
  local MESSAGE="Boot service startup slow."
  local REASON="systemd-analyze blame reports services taking longer than 30s."
  local FIX="Investigate slow services: systemd-analyze blame"

  if ! command_exists systemd-analyze; then
    record_check_skip "$CODE" "${MESSAGE} (systemd-analyze missing)"
    return
  fi

  local slow
  slow=$(systemd-analyze blame 2>/dev/null | awk '$1 ~ /s$/ {gsub("s", "", $1); if ($1+0 >= 30) print $0}' | head -n 5)
  if [[ -n "$slow" ]]; then
    local REASON_DETAIL="${REASON} Slow units: ${slow//$'\n'/; }"
    set_fix_status "pending" "Optimize slow startup services"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Boot services start promptly."
  fi
}

check_perf_oom_events() {
  increment_total_checks
  local CODE="PERF009"
  local MESSAGE="Out-of-memory events detected."
  local REASON="Kernel logs contain OOM killer entries."
  local FIX="Analyze memory leaks and adjust limits"

  if ! command_exists journalctl && ! command_exists dmesg; then
    record_check_skip "$CODE" "Logging tools unavailable."
    return
  fi

  local logs
  if command_exists journalctl; then
    logs=$(journalctl -k -n 300 2>/dev/null)
  else
    logs=$(dmesg 2>/dev/null | tail -n 300)
  fi

  if grep -Ei "Out of memory|oom-killer" <<<"$logs" >/dev/null 2>&1; then
    set_fix_status "pending" "Inspect memory usage and adjust limits"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "No recent OOM events."
  fi
}

check_perf_cpu_temperature() {
  increment_total_checks
  local CODE="PERF010"
  local MESSAGE="CPU temperature high."
  local REASON="Thermal zone readings exceed 85°C."
  local FIX="Improve cooling or reduce CPU load"

  local sensors_dir="/sys/class/thermal"
  if [[ ! -d "$sensors_dir" ]]; then
    record_check_skip "$CODE" "Thermal sensors directory missing."
    return
  fi

  local overheat=0 max_temp=0
  local zone
  for zone in "$sensors_dir"/thermal_zone*/temp; do
    [[ -f "$zone" ]] || continue
    local temp
    temp=$(cat "$zone" 2>/dev/null)
    if [[ -z "$temp" ]]; then
      continue
    fi
    local celsius=$(( temp / 1000 ))
    (( celsius > max_temp )) && max_temp=$celsius
    if (( celsius >= 85 )); then
      overheat=1
      break
    fi
  done

  if (( overheat )); then
    local REASON_DETAIL="${REASON} Peak: ${max_temp}C"
    set_fix_status "pending" "Improve cooling and ensure fans operational"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "CPU temperature peak ${max_temp}C."
  fi
}

check_perf_high_cpu_process() {
  increment_total_checks
  local CODE="PERF011"
  local MESSAGE="Process consuming excessive CPU."
  local REASON="Top process uses more than 150% CPU."
  local FIX="Inspect process with sudo renice or restart"

  if ! command_exists ps; then
    record_check_skip "$CODE" "${MESSAGE} (ps missing)"
    return
  fi

  local top_proc
  top_proc=$(ps -eo pid,comm,%cpu --sort=-%cpu 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3}')
  if [[ -z "$top_proc" ]]; then
    record_check_skip "$CODE" "Unable to determine CPU usage."
    return
  fi

  local pid cmd cpu
  read -r pid cmd cpu <<<"$top_proc"
  cpu=${cpu%.*}
  if [[ -n "$cpu" ]] && (( cpu > 150 )); then
    local REASON_DETAIL="${REASON} Offender: ${cmd} (PID ${pid}) at ${cpu}%"
    set_fix_status "pending" "Throttle or restart ${cmd}"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Top CPU process ${cmd} at ${cpu}%"
  fi
}

check_perf_high_memory_process() {
  increment_total_checks
  local CODE="PERF012"
  local MESSAGE="Process consuming excessive memory."
  local REASON="Top process uses over 40% of RAM."
  local FIX="Restart or optimize memory-heavy service"

  if ! command_exists ps; then
    record_check_skip "$CODE" "${MESSAGE} (ps missing)"
    return
  fi

  local top_proc
  top_proc=$(ps -eo pid,comm,%mem --sort=-%mem 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3}')
  if [[ -z "$top_proc" ]]; then
    record_check_skip "$CODE" "Unable to determine memory usage."
    return
  fi

  local pid cmd mem
  read -r pid cmd mem <<<"$top_proc"
  mem=${mem%.*}
  if [[ -n "$mem" ]] && (( mem > 40 )); then
    local REASON_DETAIL="${REASON} Offender: ${cmd} (PID ${pid}) at ${mem}%"
    set_fix_status "pending" "Restart or optimize ${cmd}"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Top memory process ${cmd} at ${mem}%"
  fi
}

check_perf_swappiness() {
  increment_total_checks
  local CODE="PERF013"
  local MESSAGE="Swappiness too aggressive."
  local REASON="vm.swappiness value above 80 can cause premature swapping."
  local FIX="Tune swappiness: sudo sysctl vm.swappiness=40"

  if [[ ! -r /proc/sys/vm/swappiness ]]; then
    record_check_skip "$CODE" "Swappiness interface missing."
    return
  fi

  local value
  value=$(cat /proc/sys/vm/swappiness)
  if [[ -n "$value" ]] && (( value > 80 )); then
    attempt_fix_cmd "Reduced swappiness" "sudo sysctl vm.swappiness=40"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "Swappiness at ${value}."
  fi
}

check_perf_cpu_governor() {
  increment_total_checks
  local CODE="PERF014"
  local MESSAGE="CPU governor set to powersave under load."
  local REASON="Scaling governor remains at powersave which can throttle performance."
  local FIX="Switch governor: sudo cpupower frequency-set --governor performance"

  local governor_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
  if [[ ! -f "$governor_file" ]]; then
    record_check_skip "$CODE" "CPU governor interface missing."
    return
  fi

  local governor
  governor=$(cat "$governor_file" 2>/dev/null)
  if [[ "$governor" == "powersave" ]]; then
    set_fix_status "pending" "Adjust governor to performance when needed"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  else
    record_check_ok "$CODE" "CPU governor ${governor}."
  fi
}

check_perf_memory_psi() {
  increment_total_checks
  local CODE="PERF015"
  local MESSAGE="Sustained memory pressure (PSI)."
  local REASON="/proc/pressure/memory reports high some backlog, indicating recurring cgroup allocation stalls."
  local FIX="Reduce memory usage, tune workloads, or add RAM; inspect high RSS processes"

  local psi_file="/proc/pressure/memory"
  if [[ ! -r "$psi_file" ]]; then
    record_check_skip "$CODE" "PSI memory interface not available."
    return
  fi

  local threshold="${LMS_PSI_MEM_AVG10_WARN:-15.0}"
  local avg10
  avg10=$(awk '/^some / {for (i=1; i<=NF; i++) if ($i ~ /^avg10=/) { sub(/^avg10=/, "", $i); print $i; exit}}' "$psi_file")
  if [[ -z "$avg10" ]]; then
    record_check_skip "$CODE" "Unable to parse PSI avg10."
    return
  fi

  if awk -v v="$avg10" -v t="$threshold" 'BEGIN { exit !(v+0 > t+0) }'; then
    local REASON_DETAIL="${REASON} some avg10=${avg10} (threshold ${threshold})."
    set_fix_status "pending" "Investigate memory pressure"
    log_issue "$CODE" "$MESSAGE" "$REASON_DETAIL" "$FIX"
  else
    record_check_ok "$CODE" "Memory PSI avg10=${avg10} within threshold ${threshold}."
  fi
}

check_perf_systemd_oomd() {
  increment_total_checks
  local CODE="PERF016"
  local MESSAGE="systemd-oomd enabled but not running."
  local REASON="The out-of-memory daemon should be active when enabled to avoid uncontrolled killer behaviour."
  local FIX="Start oomd: sudo systemctl start systemd-oomd"

  if ! command_exists systemctl; then
    record_check_skip "$CODE" "systemctl missing."
    return
  fi

  if ! systemctl list-unit-files 2>/dev/null | grep -q '^systemd-oomd\.service'; then
    record_check_skip "$CODE" "systemd-oomd not installed."
    return
  fi

  if ! systemctl is-enabled systemd-oomd >/dev/null 2>&1; then
    record_check_skip "$CODE" "systemd-oomd not enabled."
    return
  fi

  if systemctl is-active systemd-oomd >/dev/null 2>&1; then
    record_check_ok "$CODE" "systemd-oomd active."
  else
    attempt_fix_cmd "Started systemd-oomd" "sudo systemctl start systemd-oomd"
    log_issue "$CODE" "$MESSAGE" "$REASON" "$FIX"
  fi
}
