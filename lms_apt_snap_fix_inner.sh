#!/usr/bin/env bash
# Run on the HOST as root (e.g. via: docker ... chroot /host bash /tmp/lms_apt_snap_fix_inner.sh)
set -u
export DEBIAN_FRONTEND=noninteractive

BRAVE_SNAP_NAME='brave'

echo "=== journal vacuum ==="
journalctl --vacuum-size=200M 2>/dev/null || true

echo "=== stale APT locks (fuser check) ==="
for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock; do
  [[ -f "$lock" ]] || continue
  if fuser "$lock" &>/dev/null; then
    echo "in use skip: $lock"
    continue
  fi
  rm -f "$lock" && echo "removed: $lock"
done

echo "=== apt clean ==="
apt-get clean

echo "=== remove disabled snap revisions (never brave) ==="
while IFS= read -r line; do
  [[ -z "$line" || "$line" == Name* ]] && continue
  [[ "$line" == *disabled* ]] || continue
  name=$(awk '{print $1}' <<<"$line")
  rev=$(awk '{print $3}' <<<"$line")
  [[ -n "$name" && -n "$rev" ]] || continue
  if [[ "${name,,}" == "$BRAVE_SNAP_NAME" ]]; then
    echo "SKIP brave r${rev}"
    continue
  fi
  echo "snap remove $name --revision=$rev"
  snap remove "$name" --revision="$rev" 2>&1 || true
done < <(snap list --all)

echo "=== apt update ==="
apt-get update -o Acquire::Retries=5 || true

echo "=== dpkg configure / fix broken ==="
dpkg --configure -a
apt-get -f install -y

echo "=== apt-get check ==="
apt-get check

echo "=== full-upgrade ==="
apt-get full-upgrade -y

echo "=== snap refresh ==="
snap refresh || true

echo "=== restart snapd ==="
systemctl try-restart snapd 2>/dev/null || true

echo "=== df ==="
df -h /
