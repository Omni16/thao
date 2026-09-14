#!/usr/bin/env bash
# 20-props: boot-spoof props + minimal vendor tweaks (dynamic, no codename branches).
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
source "$HERE/../../lib/common.sh"
: "${IMG:?IMG env required}"
: "${TOOLS:?TOOLS env required}"

# system build.prop: append spoof block once (marker guard)
SYS_PROP="$(find "$IMG" -path '*system*/build.prop' 2>/dev/null | head -n1 || true)"
if [ -n "$SYS_PROP" ] && ! grep -q 'PlayIntegrityFix' "$SYS_PROP"; then
    cat "$TOOLS/koushi-build.prop" >> "$SYS_PROP"
    info "20-props: appended spoof block to $SYS_PROP"
else
    info "20-props: system build.prop untouched"
fi

# system_ext cust whitelist: append allowed keys once
CUST="$(find "$IMG" -name 'cust_prop_white_keys_list' 2>/dev/null | head -n1 || true)"
if [ -n "$CUST" ]; then
    while IFS= read -r k; do
        [ -n "$k" ] && ! grep -qxF "$k" "$CUST" && printf '%s\n' "$k" >> "$CUST"
    done < "$TOOLS/koushi-cust.prop"
    info "20-props: extended $CUST"
fi

# vendor/build.prop: neutral tweaks only when the key already exists
VENDOR_PROP="$IMG/vendor/build.prop"
if [ -f "$VENDOR_PROP" ]; then
    grep -q '^persist.miui.extm.enable=1' "$VENDOR_PROP" \
        && sed -i 's/^persist.miui.extm.enable=1/persist.miui.extm.enable=0/' "$VENDOR_PROP"
    info "20-props: vendor/build.prop checked"
fi
