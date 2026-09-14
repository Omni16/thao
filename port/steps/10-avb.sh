#!/usr/bin/env bash
# 10-avb: strip avb flags from every fstab under $IMG (vendor/odm/ramdisk...),
# then set disable-verity+verification flag on every vbmeta*.img.
# Runs for EVERY device (no allowlist): both layers are independent.
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
source "$HERE/../../lib/common.sh"
: "${IMG:?IMG env required}"
: "${TOOLS:?TOOLS env required}"

n=0
while IFS= read -r fstab; do
    [ -f "$fstab" ] || continue
    sed -i 's/,avb_keys=.*avbpubkey//g' "$fstab"
    sed -i 's/,avb=vbmeta_system//g' "$fstab"
    sed -i 's/,avb=vbmeta_vendor//g' "$fstab"
    sed -i 's/,avb=vbmeta//g' "$fstab"
    sed -i 's/,avb//g' "$fstab"
    sed -i 's/,avb.*system//g' "$fstab"
    sed -i 's/,avb,/,/g' "$fstab"
    sed -i 's/,avb=.*a,/,/g' "$fstab"
    sed -i 's/,avb_keys.*key//g' "$fstab"
    n=$((n+1))
done < <(find "$IMG" -type f -name '*fstab*' 2>/dev/null)
info "10-avb: stripped $n fstab files"

m=0
while IFS= read -r vb; do
    [ -f "$vb" ] || continue
    if python3 "$TOOLS/patch-vbmeta.py" "$vb" 2>/dev/null; then
        m=$((m+1))
    else
        warn "patch-vbmeta skipped $vb"
    fi
done < <(find "$IMG" -type f -name 'vbmeta*.img' 2>/dev/null)
info "10-avb: patched $m vbmeta images"
