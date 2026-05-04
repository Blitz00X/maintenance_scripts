#!/usr/bin/env bash
# Brave-safe system remediation: frees space, repairs APT/snaps, syncs time, etc.
# Explicitly NEVER removes the Brave snap (any revision), never purges Brave .deb,
# and never deletes under /var/snap/brave, ~/snap/brave, or ~/.config/BraveSoftware.
#
# Usage: sudo bash brave_safe_system_fix.sh
# Or:    sudo ./brave_safe_system_fix.sh

set -euo pipefail

BRAVE_SNAP_NAME='brave'

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo $0"

export DEBIAN_FRONTEND=noninteractive

if pgrep -x apt-get >/dev/null 2>&1 || pgrep -x apt >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; then
  die "apt/dpkg is running; wait until it finishes."
fi

echo "==> Vacuum systemd journal (free disk)"
journalctl --vacuum-size=300M

echo "==> Remove stale APT/dpkg lock files (only if not in use)"
for lock in /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/apt/lists/lock /var/lib/dpkg/lock; do
  if [[ -f "$lock" ]] && ! lsof "$lock" >/dev/null 2>&1; then
    rm -f "$lock"
    echo "    removed stale $lock"
  fi
done

echo "==> Detach unused loop devices"
losetup -D 2>/dev/null || true

echo "==> APT clean, update, configure, upgrade"
apt-get clean
apt-get update
dpkg --configure -a
apt-get -f install -y
apt-get full-upgrade -y

echo "==> Skip apt autoremove (safer for mixed snap setups; avoids accidental removals)"

echo "==> Refresh all snaps (Brave kept; only refreshes current revisions)"
snap refresh

echo "==> Remove old *disabled* snap revisions only (never Brave)"
while IFS= read -r line; do
  [[ -z "$line" || "$line" == Name* ]] && continue
  [[ "$line" == *disabled* ]] || continue
  name=$(awk '{print $1}' <<<"$line")
  rev=$(awk '{print $3}' <<<"$line")
  [[ -n "$name" && -n "$rev" ]] || continue
  if [[ "${name,,}" == "$BRAVE_SNAP_NAME" ]]; then
    echo "    SKIP snap remove: ${name} rev ${rev} (Brave protected)"
    continue
  fi
  echo "    Removing old revision: ${name} r${rev}"
  snap remove "$name" --revision="$rev" || echo "    warning: could not remove ${name} r${rev}"
done < <(snap list --all)

echo "==> Enable time sync"
systemctl enable --now systemd-timesyncd 2>/dev/null || true

echo "==> Fix /etc/hosts 127.0.1.1 for current hostname"
h="$(hostname)"
if grep -q '^127\.0\.1\.1' /etc/hosts; then
  if ! grep '^127\.0\.1\.1' /etc/hosts | grep -qw "$h"; then
    rest=$(grep '^127\.0\.1\.1' /etc/hosts | head -1 | sed -e 's/^127\.0\.1\.1[[:space:]]\{1,\}//')
    sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 $h $rest/" /etc/hosts
    echo "    Updated 127.0.1.1 line to include $h"
  fi
else
  echo "127.0.1.1 $h" >>/etc/hosts
  echo "    Appended 127.0.1.1 $h"
fi

echo "==> Purge very old rotated logs (*.gz older than 180 days under /var/log)"
find /var/log -type f -name '*.gz' -mtime +180 -delete 2>/dev/null || true

echo
echo "Done. If /var/run/reboot-required exists, reboot when convenient:"
if [[ -f /var/run/reboot-required ]]; then
  cat /var/run/reboot-required 2>/dev/null || true
  echo "  sudo reboot"
fi
df -h /
echo
echo "Re-run: ./lms.sh --explain"
