#!/usr/bin/env bash
# verify_checks.sh: Lists and counts all checks implemented in LMS modules.

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${BASE_DIR}/lms/modules"

echo "=== LMS Check Verification ==="
printf "%-15s | %-10s | %s\n" "Module" "Count" "Functions"
echo "--------------------------------------------------------"

total_all=0
for module in "${MODULE_DIR}"/*.sh; do
  if [[ -f "$module" ]]; then
    name=$(basename "$module" .sh)
    # Count functions matching check_*
    checks=$(grep -c "^check_" "$module")
    total_all=$((total_all + checks))
    printf "%-15s | %-10d\n" "$name" "$checks"
  fi
done

echo "--------------------------------------------------------"
echo "Total Checks Implemented: $total_all"
