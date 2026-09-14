#!/usr/bin/env bash
# 00-extract: *.img in $IMG -> sibling dirs ($IMG/../parts/<name>/).
# erofs via extract.erofs (vendored x86_64 or PATH), ext via MIO imgextractor
# (needs pip protobuf, CI-only). Unknown type -> warn + skip, never fail.
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
source "$HERE/../../lib/common.sh"
: "${IMG:?IMG env required}"

MIO="$HERE/../../third_party/mio"
EROFS="extract.erofs"
if [ "$(uname -m)" = "x86_64" ] && [ -x "$MIO/bins/Linux/x86_64/extract.erofs" ]; then
    EROFS="$MIO/bins/Linux/x86_64/extract.erofs"
fi
PARTS="$IMG/../parts"
n=0
for img in "$IMG"/*.img; do
    [ -e "$img" ] || continue
    name="$(basename "$img" .img)"
    [ -d "$PARTS/$name" ] && continue
    type="$(file -b "$img" | cut -c1-60)"
    case "$type" in
        *erofs*|*EROFS*)
            command -v "$EROFS" >/dev/null 2>&1 || { warn "need extract.erofs for $name"; continue; }
            mkdir -p "$PARTS/$name" && "$EROFS" -i "$img" -o "$PARTS/$name" -x \
                && n=$((n+1)) || warn "extract.erofs failed on $name" ;;
        *ext*|*Ext*)
            python3 -c "import google.protobuf" 2>/dev/null \
                || { warn "need pip protobuf for ext $name"; continue; }
            mkdir -p "$PARTS/$name" \
                && PYTHONPATH="$MIO" python3 -m mio_core.imgextractor "$img" "$PARTS/$name" \
                && n=$((n+1)) || warn "imgextractor failed on $name" ;;
        *) warn "skip $name (unknown type: $type)" ;;
    esac
done
info "00-extract: $n partitions extracted -> $PARTS"
