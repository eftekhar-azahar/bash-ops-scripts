#!/usr/bin/env bash
# system_health_check.sh - one-screen health summary for a Linux server.
#
# Checks CPU load (per core), memory, swap, disk, and zombie processes,
# then lists the top processes by CPU and memory.
#
# Usage: system_health_check.sh [--json]
# Thresholds can be overridden with environment variables:
#   LOAD_WARN=1.0  LOAD_CRIT=2.0   (1-minute load average per CPU core)
#   MEM_WARN=85    MEM_CRIT=95     (% memory used, excluding cache)
#   SWAP_WARN=50   SWAP_CRIT=80    (% swap used)
#   DISK_WARN=80   DISK_CRIT=90    (% used, worst filesystem)
# Exit: 0 OK, 1 WARN, 2 CRIT
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

LOAD_WARN=${LOAD_WARN:-1.0}; LOAD_CRIT=${LOAD_CRIT:-2.0}
MEM_WARN=${MEM_WARN:-85};    MEM_CRIT=${MEM_CRIT:-95}
SWAP_WARN=${SWAP_WARN:-50};  SWAP_CRIT=${SWAP_CRIT:-80}
DISK_WARN=${DISK_WARN:-80};  DISK_CRIT=${DISK_CRIT:-90}

json=false
[[ "${1:-}" == "--json" ]] && json=true

# grade <value> <warn> <crit>  (handles decimals via awk)
grade() {
    awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN { if (v >= c) print 2; else if (v >= w) print 1; else print 0 }'
}

cores=$(nproc 2>/dev/null || echo 1)
read -r load1 load5 load15 _ < /proc/loadavg
load_per_core=$(awk -v l="$load1" -v c="$cores" 'BEGIN { printf "%.2f", l / c }')

mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
mem_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))

swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
swap_pct=0
(( swap_total > 0 )) && swap_pct=$(( (swap_total - swap_free) * 100 / swap_total ))

read -r disk_pct disk_mount < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
    | awk 'NR > 1 { gsub("%", "", $5); if ($5 + 0 >= max) { max = $5 + 0; m = $6 } } END { print max + 0, m }')
disk_mount=${disk_mount:-/}

zombies=$(ps -eo stat= | awk '/^Z/ { n++ } END { print n + 0 }')

s_load=$(grade "$load_per_core" "$LOAD_WARN" "$LOAD_CRIT")
s_mem=$(grade "$mem_pct" "$MEM_WARN" "$MEM_CRIT")
s_swap=$(grade "$swap_pct" "$SWAP_WARN" "$SWAP_CRIT")
s_disk=$(grade "$disk_pct" "$DISK_WARN" "$DISK_CRIT")
s_zomb=$(( zombies > 0 ? STATUS_WARN : STATUS_OK ))

overall=$STATUS_OK
for s in "$s_load" "$s_mem" "$s_swap" "$s_disk" "$s_zomb"; do overall=$(worst "$overall" "$s"); done

if $json; then
    names=(OK WARN CRIT)
    printf '{"host":"%s","time":"%s","status":"%s",' "$(hostname)" "$(ts)" "${names[$overall]}"
    printf '"load_per_core":%s,"memory_pct":%s,"swap_pct":%s,"disk_pct":%s,"disk_mount":"%s","zombies":%s}\n' \
        "$load_per_core" "$mem_pct" "$swap_pct" "$disk_pct" "$disk_mount" "$zombies"
    exit "$overall"
fi

echo "== Health check: $(hostname) at $(ts) =="
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
printf '%-6s %-8s %s\n' "$(label_for "$s_load")" "Load"   "$load1 / $load5 / $load15 (1/5/15 min) on $cores cores = $load_per_core per core"
printf '%-6s %-8s %s\n' "$(label_for "$s_mem")"  "Memory" "${mem_pct}% used ($(( mem_avail / 1024 )) MiB available of $(( mem_total / 1024 )) MiB)"
printf '%-6s %-8s %s\n' "$(label_for "$s_swap")" "Swap"   "${swap_pct}% used"
printf '%-6s %-8s %s\n' "$(label_for "$s_disk")" "Disk"   "${disk_pct}% used on fullest filesystem ($disk_mount)"
printf '%-6s %-8s %s\n' "$(label_for "$s_zomb")" "Zombies" "$zombies"
echo
echo "Top 5 by CPU:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6
echo
echo "Top 5 by memory:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -6
echo
echo "Overall: $(label_for "$overall")"
exit "$overall"
