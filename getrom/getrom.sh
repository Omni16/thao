#!/usr/bin/env bash
# getrom/getrom.sh — Download Manager: detect -> resolve -> backend -> verify -> handoff.
# Usage: getrom.sh [--backend auto|aria2|curl|wget|rclone] [--sha256 HEX]
#                    [--min-bytes N] [--outdir DIR] <URL|local-path>
# Emits getrom.json path on stdout; also writes rom-info.json + job.json (next=detect).

set -u
HERE="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"
# shellcheck source=resolver.sh
source "$HERE/resolver.sh"
# shellcheck source=backends.sh
source "$HERE/backends.sh"
# shellcheck source=verify.sh
source "$HERE/verify.sh"

guess_filename() {
    # $1 = url; strip query, take basename; never trust it blindly (§64 doc 1)
    local base="${1%%\?*}"
    base="$(basename "$base")"
    base="$(printf '%s' "$base" | sed 's#\.\.#_#g; s#^[.]*##; s#[^A-Za-z0-9._-]#_#g')"
    [ -n "$base" ] || base="rom.bin"
    printf '%s' "$base"
}

BACKEND="auto"; EXPECTED=""; MINB=0; OUTBASE="downloads"; INPUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --backend) BACKEND="$2"; shift 2 ;;
        --sha256)  EXPECTED="$2"; shift 2 ;;
        --min-bytes) MINB="$2"; shift 2 ;;
        --outdir)  OUTBASE="$2"; shift 2 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) INPUT="$1"; shift ;;
    esac
done
[ -n "$INPUT" ] || die "usage: getrom.sh [opts] <URL|local-path>"

write_handoff() {  # $1=file $2=jobdir $3=verify_rc — rom info is best-effort
    local info="" rom="null" ready="false"
    info="$(bash "$HERE/resolve_rom.sh" --output "$2" "$1" 2>/dev/null || true)"
    [ -n "$info" ] && [ -f "$info" ] && rom="\"rom-info.json\""
    [ "$3" -eq 0 ] && ready="true"
    cat > "$2/job.json" <<EOF
{
  "job_id": "$(json_escape "$(basename "$2")")",
  "ready": $ready,
  "next": "detect",
  "getrom": "getrom.json",
  "rom": $rom
}
EOF
}

JOB="FUJI-DL-$(date +%Y%m%d)-$RANDOM"
JOBDIR="$OUTBASE/$JOB"
mkdir -p "$JOBDIR/logs"
printf '{"input": "%s", "state": "QUEUED"}\n' "$(json_escape "$INPUT")" > "$JOBDIR/state.json"

TYPE="$(detect_input "$INPUT")"
[ "$TYPE" = "unknown" ] && [ ! -f "$INPUT" ] && die "cannot handle input: $INPUT"
info "type=$TYPE"

# local files: copy -> verify -> analyze (no network, §32 doc 1)
if [ "$TYPE" = "local" ] || [ -f "$INPUT" ]; then
    SRC="${INPUT#file://}"
    cp -- "$SRC" "$JOBDIR/"
    FILE="$JOBDIR/$(basename "$SRC")"
    verify_and_report "$FILE" "$JOBDIR" "$INPUT" "local" "local" "$EXPECTED" "$MINB"
    rc=$?
    write_handoff "$FILE" "$JOBDIR" "$rc"
    exit "$rc"
fi

check_url "$INPUT"
read -r PROVIDER FINAL_URL <<< "$(resolve_url "$INPUT" "$TYPE")"
info "provider=$PROVIDER"
[ -n "$FINAL_URL" ] || die "resolver returned empty URL"
case "$PROVIDER" in
    generic|github|gitlab|mifirm|xiaomi) check_url "$FINAL_URL" ;;
esac

# disk-space precheck: need >= 3x Content-Length when known (ROM + unpack + repack)
SIZE="$(curl -fsSI --max-time 30 -- "$FINAL_URL" 2>/dev/null \
    | grep -i '^content-length:' | tr -d '\r' | awk '{print $2}' | tail -n1 || true)"
if [ -n "${SIZE:-}" ] && [ "$SIZE" -gt 0 ]; then
    AVAIL="$(df -B1 "$JOBDIR" | awk 'NR==2{print $4}')"
    [ "$(( AVAIL / (SIZE + 1) ))" -ge 3 ] \
        || die "disk full risk: need ~$(( SIZE * 3 )) bytes, have $AVAIL"
fi

NAME="$(guess_filename "$FINAL_URL")"
info "backend=$BACKEND file=$NAME"
FILE="$(backend_download "$BACKEND" "$FINAL_URL" "$JOBDIR" "$NAME" "$PROVIDER")" \
    || die "download failed, see $JOBDIR/logs/"
verify_and_report "$FILE" "$JOBDIR" "$INPUT" "$PROVIDER" "$BACKEND" "$EXPECTED" "$MINB"
rc=$?
write_handoff "$FILE" "$JOBDIR" "$rc"
exit "$rc"
