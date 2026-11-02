# Bash Ops Scripts

![tests](https://github.com/eftekhar-azahar/bash-ops-scripts/actions/workflows/tests.yml/badge.svg)
![shell](https://img.shields.io/badge/shell-bash%204.4%2B-4EAA25?logo=gnubash&logoColor=white)

Small, dependable Bash scripts for day-to-day Linux operations: health checks, disk alerts, service monitoring, log triage and verified backups.

Every check script follows the Nagios/Icinga exit-code convention (`0` OK, `1` WARN, `2` CRIT, `3` UNKNOWN), so the same script works from a terminal, from cron, or from a monitoring agent.

| Script | What it does | When you'd use it |
|---|---|---|
| [`system_health_check.sh`](scripts/system_health_check.sh) | Load per core, memory, swap, fullest disk, zombie processes, top CPU/memory processes. `--json` for machine output | First command during an incident; daily morning check |
| [`disk_usage_alert.sh`](scripts/disk_usage_alert.sh) | Flags any real filesystem over warn/crit thresholds; optional log file | Every 15 minutes from cron |
| [`service_check.sh`](scripts/service_check.sh) | Checks systemd units, processes, TCP ports and HTTP endpoints from one config file | After a deployment or change; scheduled availability check |
| [`log_error_scan.sh`](scripts/log_error_scan.sh) | Counts ERROR/FATAL lines per file and groups repeats after masking numbers, IPs and UUIDs | Triage: "what is actually failing, and how often?" |
| [`backup_rotate.sh`](scripts/backup_rotate.sh) | Timestamped tar.gz, verified with `tar -tzf`, SHA-256 checksum, keeps the last N | Nightly config or data backups |

## Quick start

```bash
git clone https://github.com/eftekhar-azahar/bash-ops-scripts.git
cd bash-ops-scripts
./scripts/system_health_check.sh
./scripts/log_error_scan.sh examples/sample_app.log
```

Every script prints its usage with `-h`. A sample cron schedule is in [`examples/crontab.example`](examples/crontab.example).

## Examples

**Log triage:** 8 error lines collapse into 4 distinct problems:

```
$ ./scripts/log_error_scan.sh examples/sample_app.log
== Log scan  pattern: /ERROR|FATAL|CRITICAL|Exception/ ==
MATCHES  FILE
8        examples/sample_app.log

Top 10 recurring messages (numbers, IPs and IDs masked):
      3 ERROR Payment API timeout after <n> ms for order <n> from <ip>
      2 ERROR Session <uuid> rejected: token expired
      2 ERROR DB connection pool exhausted (active=<n>, max=<n>)
      1 FATAL Worker <n> crashed: java.lang.OutOfMemoryError: Java heap space

Total matching lines: 8
```

Add `-s "2026-10-30 10:00"` to look only at lines after a given time, for example since an incident started.

**Health check:**

```
$ ./scripts/system_health_check.sh
== Health check: app-server-01 ==
OK     Load     0.42 / 0.38 / 0.35 (1/5/15 min) on 2 cores = 0.21 per core
OK     Memory   5% used (7595 MiB available of 8027 MiB)
OK     Swap     0% used
CRIT   Disk     93% used on fullest filesystem (/opt/app)
OK     Zombies  0
...
Overall: CRIT
```

Thresholds can be changed per run, e.g. `DISK_WARN=85 DISK_CRIT=95 ./scripts/system_health_check.sh`.

**Service check** with [`examples/services.conf`](examples/services.conf):

```
service    cron
process    sshd
tcp        127.0.0.1:5432
http       https://github.com
```

**Backup with rotation:**

```
$ ./scripts/backup_rotate.sh -s /etc -d /backup/etc -k 14
[INFO] Creating /backup/etc/etc_20261103_013000.tar.gz
[INFO] Verified: 1.2M, 1840 entries
[INFO] Done. 15 archive(s) found, 1 rotated out, keep=14
```

A failed or unreadable archive stops the script *before* rotation, so a bad night never deletes good backups. Use `-n` for a dry run.

## Design choices

- `set -euo pipefail` everywhere; inputs are validated and bad arguments exit with `3`.
- Shared helpers (logging, status labels, colour only when writing to a terminal) live in [`scripts/lib/common.sh`](scripts/lib/common.sh).
- No dependencies beyond coreutils, procps, tar and curl, so the scripts work on minimal servers and in containers. `service_check.sh` falls back to a process check when systemd isn't available.

## Tests

```bash
./tests/run_tests.sh
```

29 functional tests (syntax, thresholds, exit codes, log grouping and time filter, backup rotation, checksum verification, dry run, service checks). CI also runs ShellCheck on every push.

## Author

**Md. Eftekhar Azahar**, Cloud PaaS Engineer (Cloud Managed Services). [GitHub](https://github.com/eftekhar-azahar) · [LinkedIn](https://www.linkedin.com/in/eftekhar-azahar)
