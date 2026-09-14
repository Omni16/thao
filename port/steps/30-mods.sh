#!/usr/bin/env bash
# 30-mods: run mods/<OS>/*.sh then mods/universal/*.sh (Nothing insmod pattern).
# Ships empty: copy device mod scripts from Omni16/nothingsvn_xiaomi-toolbuild
# bin/modfile/ here (see mods/README.md). No-op when empty, never fails.
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
source "$HERE/../../lib/common.sh"
: "${MODS:?MODS env required}"
: "${OS:=unknown}"

run_dir() {
    local d="$1" s n=0
    [ -d "$d" ] || return 0
    while IFS= read -r s; do
        [ -f "$s" ] || continue
        [ "$(basename "$s")" = "$(basename "$0")" ] && continue
        bash "$s" && n=$((n+1)) || warn "mod failed: $s"
    done < <(find "$d" -type f -name '*.sh' 2>/dev/null | sort)
    info "30-mods: $n scripts from $d"
}
run_dir "$MODS/$OS"
run_dir "$MODS/universal"
