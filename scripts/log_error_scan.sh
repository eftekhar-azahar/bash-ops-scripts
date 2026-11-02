#!/usr/bin/env bash
# log_error_scan.sh - first-pass incident triage across one or more log files.
#
# Counts ERROR / FATAL / CRITICAL / Exception lines per file and groups the
# most frequent messages after masking numbers, IDs and timestamps, so the
# same fault repeated 500 times shows up as one line with a count.
#
# Usage: log_error_scan.sh [-p PATTERN] [-n TOP] [-s SINCE] FILE...
#   -p  extended regex to match (default: 'ERROR|FATAL|CRITICAL|Exception')
#   -n  how many top messages to show (default 10)
#   -s  only lines whose leading timestamp is >= SINCE ("YYYY-MM-DD HH:MM")
# Exit: 0 nothing found, 1 matches found, 3 bad arguments
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

pattern='ERROR|FATAL|CRITICAL|Exception'; top=10; since=""

while getopts ":p:n:s:h" opt; do
    case "$opt" in
        p) pattern=$OPTARG ;;
        n) top=$OPTARG ;;
        s) since=$OPTARG ;;
        *) sed -n '2,13s/^# \{0,1\}//p' "$0"; exit "$STATUS_UNKNOWN" ;;
    esac
done
shift $((OPTIND - 1))
(( $# > 0 )) || die "give at least one log file"
is_int "$top" || die "-n must be a whole number"

# Lines from the file, optionally filtered by leading timestamp (string compare
# works because the format is fixed-width and zero-padded).
read_lines() {
    if [[ -n "$since" ]]; then
        awk -v s="$since" 'substr($0, 1, length(s)) >= s' "$1"
    else
        cat "$1"
    fi
}

# Normalise a message: drop the leading timestamp, mask hex IDs, IPs and numbers.
normalise() {
    sed -E \
        -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:.,]+ *//' \
        -e 's/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/<uuid>/g' \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
        -e 's/\b0x[0-9a-fA-F]+\b/<hex>/g' \
        -e 's/[0-9]+/<n>/g'
}

total=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "== Log scan at $(ts)  pattern: /$pattern/${since:+  since: $since} =="
printf '%-8s %s\n' "MATCHES" "FILE"
for f in "$@"; do
    if [[ ! -r "$f" ]]; then warn "skipping unreadable file: $f"; continue; fi
    n=$(read_lines "$f" | grep -Ec -- "$pattern" || true)
    total=$((total + n))
    printf '%-8s %s\n' "$n" "$f"
    read_lines "$f" | grep -E -- "$pattern" | normalise >> "$tmp" || true
done

echo
if (( total == 0 )); then
    echo "No matching lines."
    exit "$STATUS_OK"
fi

echo "Top $top recurring messages (numbers, IPs and IDs masked):"
sort "$tmp" | uniq -c | sort -rn | head -n "$top"
echo
echo "Total matching lines: $total"
exit "$STATUS_WARN"
