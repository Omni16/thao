#!/usr/bin/env bash
# unpack/unpack.sh — Extract Layer dispatcher: payload / dat.br / super / fastboot.
# Usage: unpack.sh [--type auto|payload|dat|super|fastboot] [--parts boot,system]
#                  [-d OUTDIR] <rom-file>
# Needs detect.sh report when --type auto (runs it if missing).

set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

TYPE="auto"; PARTS=""; OUTDIR="out"; FILE=""
# MIO vendored backends (third_party/mio, see ATTRIBUTION.md there).
MIO="$HERE/../third_party/mio"
MIOBIN="$MIO/bins/Linux/x86_64"
BROTLI="brotli"; SIMG2IMG="simg2img"
if [ "$(uname -m)" = "x86_64" ]; then
    [ -x "$MIOBIN/brotli" ] && BROTLI="$MIOBIN/brotli"
    [ -x "$MIOBIN/simg2img" ] && SIMG2IMG="$MIOBIN/simg2img"
fi
# payload_extract needs pip deps (CI installs requirements-mio.txt)
mio_payload_ok() { python3 -c "import zstandard, google.protobuf, requests" 2>/dev/null; }
while [ $# -gt 0 ]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --parts) PARTS="$2"; shift 2 ;;
        -d) OUTDIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
        *) FILE="$1"; shift ;;
    esac
done
[ -n "$FILE" ] && [ -f "$FILE" ] || die "usage: unpack.sh [opts] <rom-file>"
mkdir -p "$OUTDIR/images"

if [ "$TYPE" = "auto" ]; then
    REPORT="$(bash "$HERE/../detect/detect.sh" --output "$OUTDIR" "$FILE" 2>/dev/null)"
    PKG="$(grep -o '"type": *"[^"]*"' "$REPORT" | head -n1 | cut -d'"' -f4)"
    PAYLOAD="$(grep -o '"payload": *[a-z]*' "$REPORT" | head -n1 | awk '{print $2}')"
    DAT="$(grep -o '"dat": *[a-z]*' "$REPORT" | head -n1 | awk '{print $2}')"
    SUPER="$(grep -o '"super": *[a-z]*' "$REPORT" | head -n1 | awk '{print $2}')"
    if [ "$PAYLOAD" = "true" ]; then TYPE="payload";
    elif [ "$DAT" = "true" ]; then TYPE="dat";
    elif [ "$PKG" = "fastboot" ]; then TYPE="fastboot";
    elif [ "$SUPER" = "true" ] || [ "$PKG" = "super_image" ]; then TYPE="super";
    else die "cannot determine package type (see $REPORT)"; fi
    info "detected type=$TYPE"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unpack_payload() {
    # MIO reads payload straight from the zip (also -t url for streaming);
    # no multi-GB temp copy needed.
    if mio_payload_ok; then
        local mode="zip"
        [ "$(basename "$FILE")" = "payload.bin" ] && mode="bin"
        if [ -n "$PARTS" ]; then
            PYTHONPATH="$MIO" python3 -m mio_core.payload_extract \
                -t "$mode" -i "$FILE" -o "$OUTDIR/images" -X "${PARTS// /}" \
                || die "payload_extract (MIO) failed on $FILE"
        else
            PYTHONPATH="$MIO" python3 -m mio_core.payload_extract \
                -t "$mode" -i "$FILE" -o "$OUTDIR/images" \
                || die "payload_extract (MIO) failed on $FILE"
        fi
        return
    fi
    unzip -p "$FILE" payload.bin > "$TMP/payload.bin" \
        || die "payload.bin listed but unreadable"
    if command -v payload-dumper-go >/dev/null 2>&1; then
        if [ -n "$PARTS" ]; then
            payload-dumper-go -p "$PARTS" -o "$OUTDIR/images" "$TMP/payload.bin"
        else
            payload-dumper-go -o "$OUTDIR/images" "$TMP/payload.bin"
        fi
    elif command -v payload-extract >/dev/null 2>&1; then
        payload-extract extract -o "$OUTDIR/images" "$TMP/payload.bin"
    else
        die "need payload-dumper-go or payload-extract to unpack payload.bin"
    fi
}

unpack_dat() {
    command -v "$BROTLI" >/dev/null 2>&1 || die "need brotli to unpack *.dat.br"
    local sdat2img="sdat2img.py"
    command -v sdat2img.py >/dev/null 2>&1 || die "need sdat2img.py on PATH"
    unzip -j "$FILE" '*.new.dat.br' '*.transfer.list' -d "$TMP" >/dev/null \
        || die "dat.br entries unreadable"
    for br in "$TMP"/*.new.dat.br; do
        local name; name="$(basename "$br" .new.dat.br)"
        "$BROTLI" -d "$br" -o "$TMP/$name.new.dat"
        python3 "$sdat2img" "$TMP/$name.transfer.list" \
            "$TMP/$name.new.dat" "$OUTDIR/images/$name.img"
    done
}

unpack_super() {
    # merge sparse chunks if needed, then split logical partitions
    local super="$FILE"
    if [ "$(basename "$FILE")" != "super.img" ]; then
        unzip -j "$FILE" '*super.img*' -d "$TMP" >/dev/null \
            || die "no super.img* entries in $FILE"
        if ls "$TMP"/super.img.* >/dev/null 2>&1; then
            command -v "$SIMG2IMG" >/dev/null 2>&1 || die "need simg2img to merge super.img.*"
            "$SIMG2IMG" "$TMP"/super.img.* "$TMP/super.img" 2>/dev/null \
                || cat "$TMP"/super.img.* > "$TMP/super.img"
        fi
        super="$TMP/super.img"
        [ -f "$super" ] || die "super.img not found after extract"
    fi
    # vendored MIO shim is stdlib-only: preferred, works everywhere python3 does
    if command -v python3 >/dev/null 2>&1 && [ -f "$MIO/shim_lpunpack.py" ]; then
        # shellcheck disable=SC2086
        python3 "$MIO/shim_lpunpack.py" "$super" "$OUTDIR/images" ${PARTS//,/ } \
            || die "shim_lpunpack failed on $super"
        return
    fi
    command -v lpunpack >/dev/null 2>&1 || die "need lpunpack to split super.img"
    lpunpack "$super" "$OUTDIR/images"
}

unpack_fastboot() {
    tar -xzf "$FILE" -C "$OUTDIR" || die "fastboot archive unreadable"
}

case "$TYPE" in
    payload)  unpack_payload ;;
    dat)      unpack_dat ;;
    super)    unpack_super ;;
    fastboot) unpack_fastboot ;;
    *) die "unknown type: $TYPE (want payload|dat|super|fastboot)" ;;
esac

info "unpacked -> $OUTDIR/images/"
ls "$OUTDIR/images/"
