#!/usr/bin/env bash
# Provides ANSI color codes for human-friendly terminal output.

if [[ -n "${LMS_COLORS_LOADED:-}" ]]; then
  return
fi
export LMS_COLORS_LOADED=1

if [[ -t 1 ]]; then
  export LMS_COLOR_RESET=$'\033[0m'
  export LMS_COLOR_INFO=$'\033[38;5;39m'
  export LMS_COLOR_SUCCESS=$'\033[38;5;40m'
  export LMS_COLOR_WARN=$'\033[38;5;214m'
  export LMS_COLOR_ERROR=$'\033[38;5;196m'
  export LMS_COLOR_HEADING=$'\033[1;38;5;33m'
  export LMS_COLOR_MUTED=$'\033[38;5;245m'
else
  export LMS_COLOR_RESET=''
  export LMS_COLOR_INFO=''
  export LMS_COLOR_SUCCESS=''
  export LMS_COLOR_WARN=''
  export LMS_COLOR_ERROR=''
  export LMS_COLOR_HEADING=''
  export LMS_COLOR_MUTED=''
fi
