#!/usr/bin/env bash
# Shared helpers: timestamped logging, status codes, colour only on a terminal.
# Source it:  . "$(dirname "$0")/lib/common.sh"

# Exit codes used by every check script (same convention as Nagios/Icinga plugins)
readonly STATUS_OK=0
readonly STATUS_WARN=1
readonly STATUS_CRIT=2
readonly STATUS_UNKNOWN=3
export STATUS_OK STATUS_WARN STATUS_CRIT STATUS_UNKNOWN

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_YEL=$'\e[33m'; C_GRN=$'\e[32m'; C_RST=$'\e[0m'
else
    C_RED=""; C_YEL=""; C_GRN=""; C_RST=""
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log()  { printf '%s [INFO] %s\n'  "$(ts)" "$*"; }
warn() { printf '%s [WARN] %s\n'  "$(ts)" "$*" >&2; }
die()  { printf '%s [ERROR] %s\n' "$(ts)" "$*" >&2; exit "$STATUS_UNKNOWN"; }

# label_for <status-code> -> OK / WARN / CRIT / UNKNOWN (coloured on a terminal)
label_for() {
    case "$1" in
        0) printf '%sOK%s'   "$C_GRN" "$C_RST" ;;
        1) printf '%sWARN%s' "$C_YEL" "$C_RST" ;;
        2) printf '%sCRIT%s' "$C_RED" "$C_RST" ;;
        *) printf 'UNKNOWN' ;;
    esac
}

# worst <a> <b> -> the more severe of two status codes
worst() { if (( $1 > $2 )); then echo "$1"; else echo "$2"; fi; }

# is_int <value>
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }
