#!/usr/bin/env bash
# Convenience wrapper that ensures the LMS core is executed with the correct working directory.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT_DIR}/lms/lms.sh" "$@"
