#!/usr/bin/env bash
# service_check.sh - check that services, TCP ports and HTTP endpoints are up.
#
# Usage: service_check.sh [-f CONFIG] [-t TIMEOUT_SECONDS]
#
# CONFIG (default: examples/services.conf) has one check per line:
#   service  nginx                       systemd unit (falls back to a process-name match)
#   process  postgres                    process name is running
#   tcp      db.internal:5432            TCP port accepts connections
#   http     https://example.com/health  HTTP status is 2xx or 3xx
# Blank lines and lines starting with # are ignored.
# Exit: 0 all OK, 2 any check failed, 3 bad config
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

config="$(dirname "$0")/../examples/services.conf"
timeout_s=5

while getopts ":f:t:h" opt; do
    case "$opt" in
        f) config=$OPTARG ;;
        t) timeout_s=$OPTARG ;;
        *) sed -n '2,12s/^# \{0,1\}//p' "$0"; exit "$STATUS_UNKNOWN" ;;
    esac
done
[[ -r "$config" ]] || die "cannot read config: $config"
is_int "$timeout_s" || die "timeout must be a whole number of seconds"

check_service() {
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units --all --type=service >/dev/null 2>&1; then
        systemctl is-active --quiet "$1" && echo "active" && return 0
        systemctl is-active "$1" 2>/dev/null || true
        return 1
    fi
    check_process "$1"   # containers and minimal hosts have no systemd
}

check_process() {
    local n
    n=$(pgrep -c -x "$1" 2>/dev/null || true)
    (( ${n:-0} > 0 )) && { echo "$n running"; return 0; }
    echo "not running"; return 1
}

check_tcp() {
    local host=${1%:*} port=${1##*:}
    if timeout "$timeout_s" bash -c ": > /dev/tcp/$host/$port" 2>/dev/null; then
        echo "port open"; return 0
    fi
    echo "no connection"; return 1
}

check_http() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout_s" "$1" 2>/dev/null || true)
    [[ "$code" =~ ^[23][0-9][0-9]$ ]] && { echo "HTTP $code"; return 0; }
    echo "HTTP ${code:-000}"; return 1
}

overall=$STATUS_OK; total=0; failed=0
printf '%-6s %-8s %-40s %s\n' "STATUS" "TYPE" "TARGET" "DETAIL"

while read -r kind target _; do
    [[ -z "${kind:-}" || "$kind" == \#* ]] && continue
    total=$((total + 1))
    case "$kind" in
        service) fn=check_service ;;
        process) fn=check_process ;;
        tcp)     fn=check_tcp ;;
        http)    fn=check_http ;;
        *)       die "unknown check type '$kind' in $config" ;;
    esac
    if detail=$($fn "$target"); then s=$STATUS_OK; else s=$STATUS_CRIT; failed=$((failed + 1)); fi
    overall=$(worst "$overall" "$s")
    printf '%-6s %-8s %-40s %s\n' "$(label_for "$s")" "$kind" "$target" "$detail"
done < "$config"

echo "Checked $total, failed $failed. Overall: $(label_for "$overall")"
exit "$overall"
