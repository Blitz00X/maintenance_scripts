#!/usr/bin/env bash
# LMS configuration file.
# Copy this file to config.sh and tweak settings as needed.

# Enable or disable modules by listing their short names. Valid entries:
#   network, disk, package, container, performance, security, system, firmware, boot, log
LMS_ENABLED_MODULES=(network disk package container performance security system firmware boot log)

# Default behaviour flags (0 = disabled, 1 = enabled).
LMS_DEFAULT_AUTO_FIX=0
LMS_DEFAULT_EXPLAIN=0

# Optional: specify a default report directory (will be created if missing).
# Leave empty to keep using lms/reports/.
LMS_REPORT_DIR=""

# Optional: pass additional flags every time (e.g., '--report /tmp/lms.txt').
LMS_DEFAULT_ARGS=()
