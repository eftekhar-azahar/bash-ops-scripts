#!/usr/bin/env bash
# disk_usage_alert.sh - warn when any real filesystem crosses a usage threshold.
#
# Usage: disk_usage_alert.sh [-w WARN%] [-c CRIT%] [-x MOUNT]... [-l LOGFILE]
#   -w  warning threshold, percent used (default 80)
#   -c  critical threshold, percent used (default 90)
#   -x  mount point to skip (repeatable)
#   -l  also append results to LOGFILE
# Exit: 0 OK, 1 WARN, 2 CRIT, 3 bad arguments
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

warn_pct=80; crit_pct=90; logfile=""; excludes=()

usage() { sed -n '2,10s/^# \{0,1\}//p' "$0"; exit "$STATUS_UNKNOWN"; }

while getopts ":w:c:x:l:h" opt; do
    case "$opt" in
        w) warn_pct=$OPTARG ;;
        c) crit_pct=$OPTARG ;;
        x) excludes+=("$OPTARG") ;;
        l) logfile=$OPTARG ;;
        *) usage ;;
    esac
done

if ! is_int "$warn_pct" || ! is_int "$crit_pct"; then die "thresholds must be whole numbers"; fi
(( warn_pct <= crit_pct )) || die "warning threshold must not exceed critical"

overall=$STATUS_OK
report=()

# -P keeps one line per filesystem; skip pseudo filesystems.
while read -r fs size used avail pct mount; do
    for x in "${excludes[@]+"${excludes[@]}"}"; do
        [[ "$mount" == "$x" ]] && continue 2
    done
    p=${pct%\%}
    is_int "$p" || continue
    if   (( p >= crit_pct )); then s=$STATUS_CRIT
    elif (( p >= warn_pct )); then s=$STATUS_WARN
    else s=$STATUS_OK
    fi
    overall=$(worst "$overall" "$s")
    report+=("$(printf '%-6s %4s%%  %-28s %s used of %s, %s free (%s)' \
        "$(label_for "$s")" "$p" "$mount" "$used" "$size" "$avail" "$fs")")
done < <(df -P -h -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

(( ${#report[@]} )) || die "no filesystems found"

print_report() {
    echo "Disk usage on $(hostname) at $(ts)  (warn ${warn_pct}%, crit ${crit_pct}%)"
    printf '%s\n' "${report[@]}"
    echo "Overall: $(label_for "$overall")"
}
if [[ -n "$logfile" ]]; then print_report | tee -a "$logfile"; else print_report; fi

exit "$overall"
