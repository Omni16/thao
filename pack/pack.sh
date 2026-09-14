#!/usr/bin/env bash
# pack/pack.sh — Repack: partition dirs -> *.img -> super.img -> flashable zip.
# Usage: pack.sh --parts parts/ --device marble [--os OS3] [-o dist/] [--dry-run]
# Layout read from pack/devices/<device>/{super,parts_info} (UR SuperConfig).
# --dry-run prints the lpmake command + checks without needing tools.

set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

PARTS=""; DEVICE=""; OS="port"; OUT="dist"; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --parts) PARTS="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --os) OS="$2"; shift 2 ;;
        -o) OUT="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -d "$PARTS" ] || die "usage: pack.sh --parts parts/ --device <codename> [--os OS3] [-o dist/]"
[ -n "$DEVICE" ] || die "usage: pack.sh --parts parts/ --device <codename> [--os OS3] [-o dist/]"
DEVDIR="$HERE/devices/$DEVICE"
[ -f "$DEVDIR/super" ] || die "no super layout for device: $DEVICE (see $HERE/devices/)"
command -v python3 >/dev/null 2>&1 || die "need python3 to read super layout"

# real super size + slot mode from the device JSON (never a default constant)
read -r SUPER_SIZE SLOTS < <(python3 -c "
import json
d = json.load(open('$DEVDIR/super'))
bd = d['block_devices'][0]
print(bd['size'], d.get('metadata_slot_count', 2))")
VAB=0; [ "$SLOTS" = "3" ] && VAB=1
# partition list + fstype from parts_info; fallback = every dir in parts/
mapfile -t PLIST < <(python3 -c "
import json, os
try:
    print('\n'.join(json.load(open('$DEVDIR/parts_info')).keys()))
except Exception:
    print('\n'.join(sorted(x for x in os.listdir('$PARTS')
                           if os.path.isdir(os.path.join('$PARTS', x)) and x != 'config')))")
[ "${#PLIST[@]}" -gt 0 ] || die "no partitions found in $PARTS"
info "pack device=$DEVICE size=$SUPER_SIZE slots=$SLOTS parts=${PLIST[*]}"

mkdir -p "$OUT"
IMGDIR="$OUT/images"
mkdir -p "$IMGDIR"

build_part() {
    local p="$1" src="$PARTS/$p" fstype=""
    # already an image (unpacked but not extracted): reuse directly
    if [ -f "$src" ]; then cp "$src" "$IMGDIR/$p.img"; return 0; fi
    [ -d "$src" ] || { warn "missing $p, skipped"; return 0; }
    fstype="$(python3 -c "
import json
print(json.load(open('$DEVDIR/parts_info')).get('$p', ''))" 2>/dev/null || true)"
    local cfg="$PARTS/config/${p}_fs_config" ctx="$PARTS/config/${p}_file_contexts"
    case "$fstype" in
        erofs|"")
            command -v mkfs.erofs >/dev/null 2>&1 || die "need mkfs.erofs to build $p"
            if [ -f "$cfg" ] && [ -f "$ctx" ]; then
                mkfs.erofs --fs-config-file="$cfg" --file-contexts="$ctx" \
                    --mount-point="/$p" -zlz4 "$IMGDIR/$p.img" "$src"
            else
                mkfs.erofs --mount-point="/$p" -zlz4 "$IMGDIR/$p.img" "$src"
            fi ;;
        ext*)
            command -v make_ext4fs >/dev/null 2>&1 || die "need make_ext4fs to build $p"
            if [ -f "$cfg" ] && [ -f "$ctx" ]; then
                make_ext4fs -T 0 -S "$ctx" -C "$cfg" -l "$(du -sb "$src" | awk '{print $1+104857600}')" \
                    "$IMGDIR/$p.img" "$src"
            else
                make_ext4fs -l "$(du -sb "$src" | awk '{print $1+104857600}')" "$IMGDIR/$p.img" "$src"
            fi ;;
        *) die "unknown fstype '$fstype' for $p" ;;
    esac
}

if [ "$DRY" = "0" ]; then
    for p in "${PLIST[@]}"; do build_part "$p"; done
fi

# lpmake args (Nothing packROM.sh formula, full partition list both modes)
GROUP_SIZE=$((SUPER_SIZE - 268435456)) # 256MB margin, fixes lpmake -22
if [ "$VAB" = "1" ]; then
    LPARGS="-F --virtual-ab --output $OUT/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --block-size 4096 --device super:$SUPER_SIZE --group=qti_dynamic_partitions_a:$GROUP_SIZE --group=qti_dynamic_partitions_b:$GROUP_SIZE"
    for p in "${PLIST[@]}"; do
        sub=0; [ -f "$IMGDIR/$p.img" ] && sub="$(stat -c%s "$IMGDIR/$p.img")"
        LPARGS="$LPARGS --partition ${p}_a:readonly:${sub}:qti_dynamic_partitions_a --image ${p}_a=$IMGDIR/$p.img --partition ${p}_b:readonly:0:qti_dynamic_partitions_b"
    done
else
    LPARGS="-F --output $OUT/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$SUPER_SIZE --group=qti_dynamic_partitions:$GROUP_SIZE"
    for p in "${PLIST[@]}"; do
        sub=0; [ -f "$IMGDIR/$p.img" ] && sub="$(stat -c%s "$IMGDIR/$p.img")"
        LPARGS="$LPARGS --partition ${p}:readonly:${sub}:qti_dynamic_partitions --image ${p}=$IMGDIR/$p.img"
    done
fi

if [ "$DRY" = "1" ]; then
    printf 'lpmake %s\n' "$LPARGS"
    exit 0
fi
command -v lpmake >/dev/null 2>&1 || die "need lpmake to build super.img"
# shellcheck disable=SC2086
lpmake $LPARGS || die "lpmake failed"
[ -f "$OUT/super.img" ] || die "super.img not produced"

# flashable zip: super + loose images + flash skeleton
ZIP="$OUT/${OS}_${DEVICE}_port.zip"
cp "$IMGDIR"/*.img "$OUT/" 2>/dev/null || true
cp -r "$HERE/flash/com" "$HERE/flash/Data" "$OUT/" 2>/dev/null || true
cp "$HERE"/flash/*.sh "$HERE"/flash/*.bat "$OUT/" 2>/dev/null || true
(cd "$OUT" && zip -qr "$(basename "$ZIP")" "$(basename "$OUT/super.img")" com Data 2>/dev/null) \
    || (cd "$OUT" && zip -qr "$(basename "$ZIP")" super.img)
info "packed -> $ZIP"

cat > "$OUT/pack.json" <<EOF
{
  "status": "completed",
  "device": "$(json_escape "$DEVICE")",
  "os": "$(json_escape "$OS")",
  "super_size": $SUPER_SIZE,
  "slots": $SLOTS,
  "zip": "$(json_escape "$ZIP")"
}
EOF
printf '%s' "$OUT/pack.json"
