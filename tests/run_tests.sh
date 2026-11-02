#!/usr/bin/env bash
# Functional tests for the scripts. Run: ./tests/run_tests.sh
set -uo pipefail
cd "$(dirname "$0")/.."
S=scripts
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

check() {  # check "<name>" <expected-exit> <command...>
    local name=$1 want=$2; shift 2
    local out got
    out=$("$@" 2>&1); got=$?
    if [[ "$got" == "$want" ]]; then pass=$((pass+1)); echo "PASS  $name"
    else fail=$((fail+1)); echo "FAIL  $name (exit $got, wanted $want)"; echo "$out" | sed 's/^/      /'; fi
}
contains() {  # contains "<name>" "<text>" <command...>
    local name=$1 text=$2; shift 2
    local out; out=$("$@" 2>&1 || true)   # scripts exit non-zero by design when they find problems
    if grep -qF -- "$text" <<< "$out"; then pass=$((pass+1)); echo "PASS  $name"
    else fail=$((fail+1)); echo "FAIL  $name (missing: $text)"; fi
}

echo "-- syntax"
for f in "$S"/*.sh "$S"/lib/*.sh tests/*.sh; do check "bash -n $f" 0 bash -n "$f"; done

echo "-- disk_usage_alert"
check    "OK at 100% thresholds"           0 "$S"/disk_usage_alert.sh -w 100 -c 100
check    "CRIT at 0% thresholds"           2 "$S"/disk_usage_alert.sh -w 0 -c 0
check    "rejects warn > crit"             3 "$S"/disk_usage_alert.sh -w 95 -c 90
check    "rejects non-numeric"             3 "$S"/disk_usage_alert.sh -w abc
"$S"/disk_usage_alert.sh -w 100 -c 100 -l "$tmp/disk.log" >/dev/null
contains "writes log file"   "Overall:"    cat "$tmp/disk.log"

echo "-- system_health_check"
check    "runs with relaxed thresholds"    0 env LOAD_WARN=999 LOAD_CRIT=999 MEM_WARN=100 MEM_CRIT=100 SWAP_WARN=101 SWAP_CRIT=101 DISK_WARN=101 DISK_CRIT=101 "$S"/system_health_check.sh
contains "JSON output"       '"status":'   "$S"/system_health_check.sh --json
check    "CRIT when thresholds are zero"   2 env MEM_WARN=0 MEM_CRIT=0 "$S"/system_health_check.sh --json

echo "-- log_error_scan"
check    "finds errors (exit 1)"           1 "$S"/log_error_scan.sh examples/sample_app.log
contains "groups repeated messages" "3 ERROR Payment API timeout after <n> ms for order <n> from <ip>" "$S"/log_error_scan.sh examples/sample_app.log
contains "masks UUIDs"       "<uuid> rejected" "$S"/log_error_scan.sh examples/sample_app.log
contains "since filter"      "Total matching lines: 2" "$S"/log_error_scan.sh -s "2026-10-30 10:00" examples/sample_app.log
check    "custom pattern, no match (exit 0)" 0 "$S"/log_error_scan.sh -p 'PANIC' examples/sample_app.log
check    "needs a file"                    3 "$S"/log_error_scan.sh

echo "-- backup_rotate"
mkdir -p "$tmp/src/data"; echo hello > "$tmp/src/data/a.txt"
for i in 1 2 3 4; do "$S"/backup_rotate.sh -s "$tmp/src" -d "$tmp/bk" -k 2 >/dev/null; sleep 1.1; done
n=$(find "$tmp/bk" -name 'src_*.tar.gz' | wc -l)
check    "keeps only 2 archives"           0 test "$n" -eq 2
check    "checksums verify"                0 bash -c "cd '$tmp/bk' && sha256sum -c --quiet ./*.sha256"
contains "archive contains file" "src/data/a.txt" bash -c "tar -tzf \"\$(ls -1 '$tmp'/bk/*.tar.gz | head -1)\""
check    "dry run changes nothing"         0 bash -c "$S/backup_rotate.sh -s '$tmp/src' -d '$tmp/bk' -k 1 -n >/dev/null && test \$(ls '$tmp'/bk/*.tar.gz | wc -l) -eq 2"
check    "rejects missing source"          3 "$S"/backup_rotate.sh -s "$tmp/nope" -d "$tmp/bk"

echo "-- service_check"
printf 'process bash\ntcp 127.0.0.1:1\n' > "$tmp/svc.conf"
check    "fails when a port is closed"     2 "$S"/service_check.sh -f "$tmp/svc.conf" -t 2
printf 'process bash\n# comment\n\n' > "$tmp/ok.conf"
check    "passes when process runs"        0 "$S"/service_check.sh -f "$tmp/ok.conf"
printf 'ftp something\n' > "$tmp/bad.conf"
check    "rejects unknown check type"      3 "$S"/service_check.sh -f "$tmp/bad.conf"

echo; echo "$pass passed, $fail failed"
(( fail == 0 ))
