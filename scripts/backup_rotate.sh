#!/usr/bin/env bash
# backup_rotate.sh - timestamped, verified tar.gz backups with retention.
#
# Usage: backup_rotate.sh -s SOURCE_DIR -d DEST_DIR [-k KEEP] [-n]
#   -s  directory to back up
#   -d  directory that holds the archives
#   -k  how many archives to keep for this source (default 7)
#   -n  dry run: show what would happen, change nothing
#
# Each archive is checked with `tar -tzf` before old ones are deleted, so a
# failed backup never triggers rotation. A SHA-256 checksum is written next to it.
# Exit: 0 success, 2 backup or verification failed, 3 bad arguments
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

src=""; dest=""; keep=7; dry=false

while getopts ":s:d:k:nh" opt; do
    case "$opt" in
        s) src=$OPTARG ;;
        d) dest=$OPTARG ;;
        k) keep=$OPTARG ;;
        n) dry=true ;;
        *) sed -n '2,12s/^# \{0,1\}//p' "$0"; exit "$STATUS_UNKNOWN" ;;
    esac
done

[[ -n "$src" && -n "$dest" ]] || die "both -s and -d are required"
[[ -d "$src" ]] || die "source is not a directory: $src"
if ! is_int "$keep" || (( keep < 1 )); then die "-k must be 1 or more"; fi

src=$(cd "$src" && pwd)
name=$(basename "$src")
stamp=$(date '+%Y%m%d_%H%M%S')
archive="$dest/${name}_${stamp}.tar.gz"

if $dry; then
    log "DRY RUN: would create $archive from $src"
else
    mkdir -p "$dest"
    log "Creating $archive"
    if ! tar -czf "$archive" -C "$(dirname "$src")" "$name"; then
        rm -f "$archive"
        warn "tar failed; nothing rotated"
        exit "$STATUS_CRIT"
    fi
    if ! tar -tzf "$archive" >/dev/null; then
        warn "verification failed for $archive; nothing rotated"
        exit "$STATUS_CRIT"
    fi
    (cd "$dest" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
    log "Verified: $(du -h "$archive" | cut -f1), $(tar -tzf "$archive" | wc -l) entries"
fi

# Rotation: newest first by name (the timestamp sorts correctly), keep $keep.
mapfile -t archives < <(find "$dest" -maxdepth 1 -name "${name}_*.tar.gz" -printf '%f\n' 2>/dev/null | sort -r)
removed=0
for old in "${archives[@]:$keep}"; do
    if $dry; then
        log "DRY RUN: would delete $dest/$old"
    else
        rm -f -- "$dest/$old" "$dest/$old.sha256"
        log "Deleted old archive $old"
    fi
    removed=$((removed + 1))
done

log "Done. ${#archives[@]} archive(s) found, $removed rotated out, keep=$keep"
exit "$STATUS_OK"
