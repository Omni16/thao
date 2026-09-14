#!/usr/bin/env bash
# port/port.sh — Vendor Patch: extract -> avb -> props -> mods -> selinux.
# Usage: port.sh --report report.json --images images/ --out port-out/
# Reads device/os/region/android from report.json. Writes port.json.
# Steps run in numeric order; each is independent and skips cleanly
# when its input is absent (offline-safe test fixtures).

set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

REPORT=""; IMG=""; OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --report) REPORT="$2"; shift 2 ;;
        --images) IMG="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -f "$REPORT" ] || die "usage: port.sh --report report.json --images images/ --out port-out/"
[ -d "$IMG" ] || die "images dir not found: $IMG"

jget() { grep -o "\"$1\": *\"[^\"]*\"" "$REPORT" | head -n1 | cut -d'"' -f4; }
export DEVICE="$(jget codename)"; : "${DEVICE:=unknown}"
VER="$(jget version)"; : "${VER:=unknown}"
export REGION="$(jget name)"; : "${REGION:=unknown}"
# ANDROID key appears twice (rom + android blocks); take the android block one:
export ANDROID="$(grep -o '"android": {[^}]*}' "$REPORT" | grep -o '"version": *"[^"]*"' | head -n1 | cut -d'"' -f4)"
: "${ANDROID:=unknown}"
# OS family dir for mods: OS1/OS2/OS3/MIUI (Nothing convention)
case "$VER" in
    OS1*) export OS="OS1" ;; OS2*) export OS="OS2" ;; OS3*) export OS="OS3" ;;
    V*)   export OS="MIUI" ;; *)   export OS="unknown" ;;
esac
export IMG TOOLS="$HERE/tools" MODS="$HERE/mods"

mkdir -p "$OUT"
info "port device=$DEVICE os=$OS region=$REGION android=$ANDROID"

DONE=""
for step in "$HERE"/steps/*.sh; do
    name="$(basename "$step")"
    if bash "$step" >>"$OUT/steps.log" 2>&1; then
        info "step $name ok"
        DONE="$DONE $name"
    else
        die "step $name failed (see $OUT/steps.log)"
    fi
done

cat > "$OUT/port.json" <<EOF
{
  "status": "completed",
  "device": "$(json_escape "$DEVICE")",
  "os": "$OS",
  "region": "$(json_escape "$REGION")",
  "android": "$(json_escape "$ANDROID")",
  "steps": [$(printf '%s' "$DONE" | awk '{for(i=1;i<=NF;i++)printf "%s\"%s\"", (i>1?",":""), $i}')],
  "images": "$(json_escape "$IMG")"
}
EOF
printf '%s' "$OUT/port.json"
