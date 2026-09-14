#!/usr/bin/env bash
# 40-selinux: regenerate fs_config + file_contexts per partition dir
# with Nothing's fix_selinux.py (correct vendor_file/vendor_dlkm_file map).
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
source "$HERE/../../lib/common.sh"
: "${IMG:?IMG env required}"
: "${TOOLS:?TOOLS env required}"

command -v python3 >/dev/null 2>&1 || die "need python3 for fix_selinux"
ROOT="$IMG"
[ -d "$IMG/../parts" ] && ROOT="$IMG/../parts"
mkdir -p "$ROOT/config"
n=0
for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = "config" ] && continue
    p="$(basename "$d")"
    python3 "$TOOLS/fix_selinux.py" "$d" "$ROOT/config/${p}_fs_config" "$ROOT/config/${p}_file_contexts" \
        && n=$((n+1)) || warn "fix_selinux failed on $p"
done
info "40-selinux: $n partitions -> $ROOT/config/"
