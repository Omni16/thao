#!/usr/bin/env bash
# detect/detect.sh — ROM Recognition: filename -> archive -> props (§5, §83-84 doc 2).
# Usage: detect.sh [--deep] [--output DIR] <rom-file>
# Prints report.json path on stdout; human summary goes to stderr.
# Never modifies the ROM (§74 doc 2).

set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

# Xiaomi region codes (§40 doc 2)
declare -A REGIONS=(
    [MIXM]="Global" [EUXM]="EEA" [INXM]="India" [CNXM]="China"
    [IDXM]="Indonesia" [TWXM]="Taiwan" [TRXM]="Turkey"
    [RUXM]="Russia" [JPXM]="Japan"
)

DEEP=0; OUTDIR=""; FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --deep) DEEP=1; shift ;;
        --output) OUTDIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
        *) FILE="$1"; shift ;;
    esac
done
[ -n "$FILE" ] && [ -f "$FILE" ] || die "usage: detect.sh [--deep] [--output DIR] <rom-file>"
require_tool file; require_tool unzip; require_tool sha256sum

BASE="$(basename "$FILE")"
SIZE="$(stat -c%s "$FILE")"
SHA="$(sha256sum "$FILE" | awk '{print $1}')"
MAGIC="$(file -b "$FILE" | cut -c1-80)"

# ---------- L1: filename hints (low confidence, §3 doc 2: never filename-only)
DEVICE="unknown"; VERSION="unknown"; REGION_CODE=""; FAMILY="unknown"; FAM_CONF="0.0"
case "$BASE" in
    miui_*)
        FAMILY="MIUI"; FAM_CONF="0.6"
        DEVICE="$(printf '%s' "$BASE" | cut -d_ -f2)"
        VERSION="$(printf '%s' "$BASE" | cut -d_ -f3)" ;;
    xiaomi.eu_*)
        FAMILY="HyperOS"; FAM_CONF="0.6"
        _F2="$(printf '%s' "$BASE" | cut -d_ -f2)"
        _F3="$(printf '%s' "$BASE" | cut -d_ -f3)"
        # field order varies (DEVICE_VERSION vs VERSION_DEVICE):
        # the version field matches ^(OS|V)[0-9]
        case "$_F2" in
            OS[0-9]*|V[0-9]*) DEVICE="$_F3"; VERSION="$_F2" ;;
            *) DEVICE="$_F2"; VERSION="$_F3" ;;
        esac
        unset _F2 _F3 ;;
    *-ota_full-*)
        FAMILY="HyperOS"; FAM_CONF="0.6"
        DEVICE="$(printf '%s' "$BASE" | cut -d- -f1)"
        VERSION="$(printf '%s' "$BASE" | cut -d- -f3)" ;;
    *_images_*)
        DEVICE="$(printf '%s' "$BASE" | cut -d_ -f1)"
        VERSION="$(printf '%s' "$BASE" | cut -d_ -f3)" ;;
esac
# normalize codename: strip market suffixes, lowercase (cf. getROM.sh)
DEVICE="$(printf '%s' "$DEVICE" \
    | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' \
    | tr '[:upper:]' '[:lower:]')"
[ -n "$DEVICE" ] || DEVICE="unknown"
# region code = trailing XXXM block in version string (§40 doc 2)
# region code = trailing XX-XM block in version string, e.g. VNCEUXM -> EUXM (§40 doc 2)
REGION_RE='MIXM|EUXM|INXM|CNXM|IDXM|TWXM|TRXM|RUXM|JPXM'
REGION_CODE="$(printf '%s' "$VERSION" | grep -oE "$REGION_RE" | tail -n1 || true)"
REGION_NAME="unknown"
[ -n "$REGION_CODE" ] && REGION_NAME="${REGIONS[$REGION_CODE]:-unknown}"

# ---------- L2: archive structure (§8-18 doc 2)
LISTING=""; PKG="unknown"; HAS_PAYLOAD="false"; HAS_SUPER="false"; HAS_DAT="false"
CONTAINER="unknown"
case "$MAGIC" in
    *Zip*) CONTAINER="zip"; LISTING="$(unzip -l "$FILE" 2>/dev/null | awk '{print $4}' || true)" ;;
    *gzip*) CONTAINER="tgz"; LISTING="$(tar -tzf "$FILE" 2>/dev/null || true)" ;;
esac
has() { printf '%s' "$LISTING" | grep -qm1 "$1"; }
if [ -n "$LISTING" ]; then
    has 'payload\.bin$' && { HAS_PAYLOAD="true"; PKG="ota"; }
    has '\.new\.dat\(\.br\)\?$' && { HAS_DAT="true"; [ "$PKG" = "unknown" ] && PKG="recovery"; }
    has '(^|/)super\.img' && HAS_SUPER="true"
    if has '(^|/)flash_all\.sh$' || has '(^|/)images/'; then PKG="fastboot"; fi
    if [ "$PKG" = "unknown" ] && has '(^|/)META-INF/'; then PKG="recovery"; fi
fi
# bare super.img passed directly
if [ "$PKG" = "unknown" ] && printf '%s' "$MAGIC" | grep -qi 'sparse'; then
    PKG="super_image"; HAS_SUPER="true"
fi

# ---------- L3: build props, only --deep and only if directly listable (§76 doc 2)
MODEL="unknown"; ANDROID="unknown"; SDK=""; BUILD_ID=""; FINGERPRINT=""
MIUI_VER=""; HYPER_VER=""; PROP_SRC="none"
if [ "$DEEP" = "1" ] && [ "$CONTAINER" = "zip" ]; then
    PROP_PATH="$(printf '%s' "$LISTING" | grep -m1 -E '(^|/)(system/build\.prop|build\.prop)$' || true)"
    if [ -n "$PROP_PATH" ]; then
        PROP_SRC="$PROP_PATH"
        PROPS="$(unzip -p "$FILE" "$PROP_PATH" 2>/dev/null || true)"
        prop() { printf '%s' "$PROPS" | grep -m1 "^$1=" | cut -d= -f2-; }
        [ "$(prop ro.product.device)" ] && DEVICE="$(prop ro.product.device)"
        [ "$(prop ro.product.model)" ] && MODEL="$(prop ro.product.model)"
        ANDROID="$(prop ro.build.version.release)"; : "${ANDROID:=unknown}"
        SDK="$(prop ro.build.version.sdk)"
        BUILD_ID="$(prop ro.build.id)"
        FINGERPRINT="$(prop ro.build.fingerprint)"
        MIUI_VER="$(prop ro.miui.ui.version.name)"
        HYPER_VER="$(prop ro.mi.os.version.name)"
        if [ -n "$HYPER_VER" ]; then FAMILY="HyperOS"; FAM_CONF="0.97";
        elif [ -n "$MIUI_VER" ]; then FAMILY="MIUI"; FAM_CONF="0.97"; fi
        # cross-check region from fingerprint when filename gave none (§41 doc 2)
        if [ -z "$REGION_CODE" ] && [ -n "$FINGERPRINT" ]; then
            REGION_CODE="$(printf '%s' "$FINGERPRINT" | grep -oE "$REGION_RE" | head -n1 || true)"
            [ -n "$REGION_CODE" ] && REGION_NAME="${REGIONS[$REGION_CODE]:-unknown}"
        fi
    fi
fi
REGION_CONF="0.6"; [ "$PROP_SRC" != "none" ] && REGION_CONF="0.9"
[ -z "$REGION_CODE" ] && { REGION_CODE="unknown"; REGION_NAME="unknown"; REGION_CONF="0.0"; }
# ---------- super manifest via vendored MIO getsuper (best-effort, never fails)
SUPER_GROUP=""; SUPER_PARTS_JSON=""
if [ "$HAS_PAYLOAD" = "true" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$HERE/../third_party/mio/mio_core/getsuper.py" ]; then
    GS="$(python3 "$HERE/../third_party/mio/mio_core/getsuper.py" "$FILE" 2>/dev/null || true)"
    SUPER_GROUP="$(printf '%s' "$GS" | grep -m1 '^super_group=' | cut -d'"' -f2 || true)"
    SUPER_LIST="$(printf '%s' "$GS" | grep -m1 '^super_list=' | cut -d'"' -f2 || true)"
    SUPER_PARTS_JSON="$(printf '%s' "$SUPER_LIST" | awk 'NF{for(i=1;i<=NF;i++)printf "%s\"%s\"", (i>1?",":""), $i}')"
fi

[ -n "$OUTDIR" ] || OUTDIR="$(dirname "$FILE")"
mkdir -p "$OUTDIR"
REPORT="$OUTDIR/report.json"
cat > "$REPORT" <<EOF
{
  "schema_version": 1,
  "status": "success",
  "source": {"filename": "$(json_escape "$BASE")", "sha256": "$SHA", "size": $SIZE, "file_type": "$(json_escape "$MAGIC")"},
  "device": {"codename": "$(json_escape "$DEVICE")", "model": "$(json_escape "$MODEL")"},
  "rom": {"family": "$FAMILY", "family_confidence": $FAM_CONF, "version": "$(json_escape "$VERSION")", "miui": "$(json_escape "${MIUI_VER:-}")", "hyperos": "$(json_escape "${HYPER_VER:-}")"},
  "android": {"version": "$(json_escape "$ANDROID")", "sdk": "$(json_escape "${SDK:-}")"},
  "build": {"id": "$(json_escape "${BUILD_ID:-}")", "fingerprint": "$(json_escape "${FINGERPRINT:-}")", "props_source": "$(json_escape "$PROP_SRC")"},
  "region": {"code": "$REGION_CODE", "name": "$REGION_NAME", "confidence": $REGION_CONF},
  "package": {"container": "$CONTAINER", "type": "$PKG", "payload": $HAS_PAYLOAD, "super": $HAS_SUPER, "dat": $HAS_DAT},
  "super_detail": {"group": "$(json_escape "$SUPER_GROUP")", "partitions": [$SUPER_PARTS_JSON]},
  "next_stage": {"recommended": "extract", "deep_needed": $([ "$PROP_SRC" = "none" ] && printf true || printf false)}
}
EOF

info "device=$DEVICE model=$MODEL family=$FAMILY version=$VERSION region=$REGION_CODE($REGION_NAME) package=$PKG payload=$HAS_PAYLOAD super=$HAS_SUPER"
printf '%s' "$REPORT"
