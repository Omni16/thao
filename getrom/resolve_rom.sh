#!/usr/bin/env bash
# getrom/resolve_rom.sh — ROM filename -> device/os/variant/region (fixed getROM.sh).
# Usage: resolve_rom.sh [--output DIR] <rom-file-or-name>
# Prints rom-info.json path on stdout. Never touches the network.
# Fixes vs Nothing's getROM.sh: TW/TRGlobal checked BEFORE Global (were dead
# branches), xiaomi.eu_ field order auto-detected, no hardcoded ROM names,
# query strings stripped, always exits nonzero on failure.
set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

OUTDIR=""
NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTDIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) NAME="$1"; shift ;;
    esac
done
[ -n "$NAME" ] || die "usage: resolve_rom.sh [--output DIR] <rom-file-or-name>"

BASE="$(basename "${NAME%%\?*}")"
DEVICE_CODE="unknown"; BASE_ROM="unknown"; FAMILY="unknown"; FAM_CONF="0.0"; OS="unknown"

case "$BASE" in
    miui_*)
        FAMILY="MIUI"; FAM_CONF="0.6"
        DEVICE_CODE="$(printf '%s' "$BASE" | cut -d_ -f2)"
        BASE_ROM="$(printf '%s' "$BASE" | cut -d_ -f3)" ;;
    xiaomi.eu_*)
        FAMILY="HyperOS"; FAM_CONF="0.6"
        _F2="$(printf '%s' "$BASE" | cut -d_ -f2)"
        _F3="$(printf '%s' "$BASE" | cut -d_ -f3)"
        case "$_F2" in
            OS[0-9]*|V[0-9]*) DEVICE_CODE="$_F3"; BASE_ROM="$_F2" ;;
            *) DEVICE_CODE="$_F2"; BASE_ROM="$_F3" ;;
        esac ;;
    *-ota_full-*)
        FAMILY="HyperOS"; FAM_CONF="0.6"
        DEVICE_CODE="$(printf '%s' "$BASE" | cut -d- -f1)"
        BASE_ROM="$(printf '%s' "$BASE" | cut -d- -f3)" ;;
    *_images_*)
        DEVICE_CODE="$(printf '%s' "$BASE" | cut -d_ -f1)"
        BASE_ROM="$(printf '%s' "$BASE" | cut -d_ -f3)" ;;
esac
# codename: lowercase, drop underscores, strip market suffixes (cf. getROM.sh device_f)
DEVICE="$(printf '%s' "$DEVICE_CODE" | tr '[:upper:]' '[:lower:]' | tr -d '_' \
    | sed 's/\(eea\|in\|id\|ru\|jp\|tw\|tr\)\?global$//')"
[ -n "$DEVICE" ] || DEVICE="unknown"

# variant: longest suffixes FIRST (TW/TRGlobal before Global — getROM.sh bug);
# match case-insensitively on underscore-stripped name
# (ota names use tw_global, fastboot names use TWGlobal)
_DC_N="$(printf '%s' "$DEVICE_CODE" | tr '[:upper:]' '[:lower:]' | tr -d '_')"
case "$_DC_N" in
    *eeaglobal) VARIANT="EEAGlobal" ;;
    *inglobal)  VARIANT="INGlobal" ;;
    *idglobal)  VARIANT="IDGlobal" ;;
    *ruglobal)  VARIANT="RUGlobal" ;;
    *jpglobal)  VARIANT="JPGlobal" ;;
    *twglobal)  VARIANT="TWGlobal" ;;
    *trglobal)  VARIANT="TRGlobal" ;;
    *global)    VARIANT="Global" ;;
    *)          VARIANT="China" ;;
esac

# region code from version block, e.g. VNCEUXM -> EUXM
REGION_RE='MIXM|EUXM|INXM|CNXM|IDXM|TWXM|TRXM|RUXM|JPXM'
REGION_CODE="$(printf '%s' "$BASE_ROM" | grep -oE "$REGION_RE" | tail -n1 || true)"
[ -n "$REGION_CODE" ] || REGION_CODE="unknown"
case "$REGION_CODE" in
    MIXM) REGION_NAME="Global" ;; EUXM) REGION_NAME="EEA" ;;
    INXM) REGION_NAME="India" ;; CNXM) REGION_NAME="China" ;;
    IDXM) REGION_NAME="Indonesia" ;; TWXM) REGION_NAME="Taiwan" ;;
    TRXM) REGION_NAME="Turkey" ;; RUXM) REGION_NAME="Russia" ;;
    JPXM) REGION_NAME="Japan" ;; *) REGION_NAME="unknown" ;;
esac

# OS family generation from version block
case "$BASE_ROM" in
    OS1.*) OS="OS1" ;; OS2.*) OS="OS2" ;; OS3.*) OS="OS3" ;;
    V14.*) OS="MIUI14"; [ "$FAMILY" = "unknown" ] && { FAMILY="MIUI"; FAM_CONF="0.6"; } ;;
    V13.*) OS="MIUI13"; [ "$FAMILY" = "unknown" ] && { FAMILY="MIUI"; FAM_CONF="0.6"; } ;;
esac

[ -n "$OUTDIR" ] || OUTDIR="$(dirname "$NAME")"
[ -d "$OUTDIR" ] || OUTDIR="."
mkdir -p "$OUTDIR"
INFO="$OUTDIR/rom-info.json"
cat > "$INFO" <<EOF
{
  "filename": "$(json_escape "$BASE")",
  "device_code": "$(json_escape "$DEVICE_CODE")",
  "device": "$(json_escape "$DEVICE")",
  "base_rom": "$(json_escape "$BASE_ROM")",
  "family": "$FAMILY",
  "family_confidence": $FAM_CONF,
  "os": "$OS",
  "variant": "$(json_escape "$VARIANT")",
  "region": {"code": "$REGION_CODE", "name": "$REGION_NAME"}
}
EOF
info "device=$DEVICE ($DEVICE_CODE) base=$BASE_ROM family=$FAMILY os=$OS variant=$VARIANT region=$REGION_CODE"
printf '%s' "$INFO"
