#!/usr/bin/env bash
# test.sh — one runnable check: fixtures exercise download(local) + detect + unpack dispatch.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

for s in lib/common.sh getrom/resolver.sh getrom/backends.sh getrom/verify.sh \
          getrom/resolve_rom.sh getrom/getrom.sh detect/detect.sh unpack/unpack.sh fuji getRom test.sh; do
    bash -n "$HERE/$s" && ok "syntax $s" || bad "syntax $s"
done

T="$(mktemp -d)/dir with space"; mkdir -p "$T"; trap 'rm -rf "$T"' EXIT

# fixture 1: fake HyperOS OTA zip (payload + fingerprint-named file for realism)
mkdir -p "$T/fx/META-INF"
printf 'dummy' > "$T/fx/payload.bin"
printf 'dummy' > "$T/fx/payload_properties.txt"
(cd "$T/fx" && zip -qr "$T/houji-ota_full-OS2.0.8.0.VNCMIXM-user-15.0-abc.zip" .) >/dev/null
ROM="$T/houji-ota_full-OS2.0.8.0.VNCMIXM-user-15.0-abc.zip"
# $T contains a space: every script must survive it (quoting check)
[ -f "$ROM" ] && ok "fixture zip" || bad "fixture zip"

# detect: filename layer only
REP="$(bash "$HERE/detect/detect.sh" --output "$T" "$ROM" 2>/dev/null)"
grep -q '"codename": *"houji"' "$REP" && ok "detect codename=houji" || bad "detect codename"
grep -q '"code": *"MIXM"' "$REP" && ok "detect region=MIXM" || bad "detect region"
grep -q '"family": *"HyperOS"' "$REP" && ok "detect family=HyperOS" || bad "detect family"
grep -q '"payload": *true' "$REP" && ok "detect payload=true" || bad "detect payload"

# download manager on local file -> getrom.json completed + job.json handoff
DJ="$(bash "$HERE/getrom/getrom.sh" --outdir "$T/dl" "$ROM" 2>/dev/null)"
grep -q '"status": *"completed"' "$DJ" && ok "getrom local completed" || bad "getrom local"
grep -q '"provider": *"local"' "$DJ" && ok "getrom provider=local" || bad "getrom provider"
JD="$(dirname "$DJ")"
grep -q '"ready": *true' "$JD/job.json" && ok "job ready=true" || bad "job ready"
grep -q '"device": *"houji"' "$JD/rom-info.json" && ok "job rom device=houji" || bad "job rom device"
grep -q '"os": *"OS2"' "$JD/rom-info.json" && ok "job rom os=OS2" || bad "job rom os"

# resolve_rom.sh on bare names (offline): TW/TR before Global, xiaomi.eu order, miui
RI="$(bash "$HERE/getrom/resolve_rom.sh" --output "$T" 'houji_tw_global-ota_full-OS2.0.1.0.VNCTWXM-user-15.0-x.zip' 2>/dev/null)"
grep -q '"variant": *"TWGlobal"' "$RI" && ok "resolve TWGlobal (order fix)" || bad "resolve TWGlobal"
grep -q '"code": *"TWXM"' "$RI" && ok "resolve region=TWXM" || bad "resolve region"
RI="$(bash "$HERE/getrom/resolve_rom.sh" --output "$T" 'xiaomi.eu_HOUJI_OS2.0.8.0.VNCMIXM_15.zip' 2>/dev/null)"
grep -q '"device": *"houji"' "$RI" && ok "resolve xiaomi.eu device" || bad "resolve xiaomi.eu device"
grep -q '"base_rom": *"OS2.0.8.0.VNCMIXM"' "$RI" && ok "resolve xiaomi.eu base" || bad "resolve xiaomi.eu base"
RI="$(bash "$HERE/getrom/resolve_rom.sh" --output "$T" 'miui_HOUJI_V14.0.5.0.TNCMIXM_abc.zip' 2>/dev/null)"
grep -q '"family": *"MIUI"' "$RI" && ok "resolve miui family" || bad "resolve miui family"
grep -q '"os": *"MIUI14"' "$RI" && ok "resolve miui os" || bad "resolve miui os"

# --min-bytes rejects truncated/error downloads; handoff marked not ready
bash "$HERE/getrom/getrom.sh" --outdir "$T/dl2" --min-bytes 999999999999 "$ROM" 2>/dev/null \
    && bad "min-bytes" || ok "min-bytes rejects small file"
JD2="$(ls -d "$T"/dl2/FUJI-DL-* 2>/dev/null | head -n1)"
grep -q '"ready": *false' "$JD2/job.json" && ok "job ready=false" || bad "job not-ready"

# unpack dispatch must fail cleanly (no payload tools installed) without traceback
if bash "$HERE/unpack/unpack.sh" --type payload -d "$T/out" "$ROM" 2>"$T/err.log"; then
    bad "unpack payload should fail w/o tools"
else
    if grep -q 'need payload-dumper-go' "$T/err.log"; then
        ok "unpack clean missing-tool error"
    elif grep -q 'payload_extract (MIO) failed' "$T/err.log"; then
        ok "unpack MIO backend attempted (pip deps present)"
    else
        bad "unpack error msg"
    fi
fi

# MIO vendored backends (offline-safe: stdlib-only parts + static bins)
MIO="$HERE/third_party/mio" python3 -c '
import glob, os
d = os.environ["MIO"]
fs = glob.glob(d + "/mio_core/*.py") + [d + "/shim_lpunpack.py"]
assert len(fs) >= 10, fs
for f in fs:
    compile(open(f, encoding="utf-8").read(), f, "exec")
' 2>/dev/null && ok "mio py compile (no pycache)" || bad "mio py compile"
python3 "$HERE/third_party/mio/mio_core/getsuper.py" 2>/dev/null \
    && bad "getsuper usage" || ok "getsuper usage error"
python3 "$HERE/third_party/mio/shim_lpunpack.py" /nonexistent "$T/x" 2>/dev/null \
    && bad "shim missing-file" || ok "shim rejects missing file"
ELF_OK=1
for b in "$HERE"/third_party/mio/bins/Linux/x86_64/*; do
    [ "$(head -c 4 "$b")" = "$(printf '\x7fELF')" ] || ELF_OK=0
done
[ "$ELF_OK" = "1" ] && ok "mio bins are static ELF" || bad "mio bins ELF"
grep -q '"super_detail"' "$REP" && ok "detect super_detail key" || bad "detect super_detail"

# fixture 2: fake super zip -> shim path fails cleanly on garbage
mkdir -p "$T/fx2"; printf 'dummy' > "$T/fx2/super.img"
(cd "$T/fx2" && zip -qr "$T/fake-super.zip" .) >/dev/null
if bash "$HERE/unpack/unpack.sh" --type super -d "$T/out2" "$T/fake-super.zip" 2>"$T/err2.log"; then
    bad "unpack super should fail on garbage"
else
    grep -q 'shim_lpunpack failed' "$T/err2.log" && ok "unpack super clean shim error" || bad "unpack super error msg"
fi

# ./getRom wrapper: positional links only, no flags
GETROM_OUTDIR="$T/g" bash "$HERE/getRom" "$ROM" 2>/dev/null \
    | grep -q 'job.json' && ok "getRom wrapper ok" || bad "getRom wrapper"
JD_G="$(ls -d "$T"/g/FUJI-DL-* 2>/dev/null | head -n1)"
grep -q '"ready": *true' "$JD_G/job.json" && ok "getRom job ready" || bad "getRom job"
bash "$HERE/getRom" 2>/dev/null && bad "getRom usage" || ok "getRom usage error"

# backend noise on stdout must not leak into the returned filepath (aria2c bug)
mkdir -p "$T/bin" "$T/bk"
cat > "$T/bin/aria2c" <<'EOF'
#!/usr/bin/env bash
echo "NOTICE noise to stdout"
while [ $# -gt 0 ]; do case "$1" in -d) d="$2"; shift 2 ;; -o) o="$2"; shift 2 ;; *) shift ;; esac; done
printf x > "$d/$o"
EOF
chmod +x "$T/bin/aria2c"
OUT="$(PATH="$T/bin:$PATH" bash -c 'source "$0/getrom/backends.sh" >/dev/null 2>&1; backend_download aria2 "http://example.com/rom.zip" "$1" "rom.zip" generic' "$HERE" "$T/bk" 2>/dev/null)"
[ "$OUT" = "$T/bk/rom.zip" ] && ok "backend stdout clean" || bad "backend stdout leak"

# xiaomi/miui direct file link must NOT be scraped as a page (offline: no curl hit)
RU="$(bash -c 'source "'"$HERE"'/getrom/resolver.sh" >/dev/null 2>&1; resolve_url "https://bn.d.miui.com/OS3/xuanyuan-ota_full-OS3.0.312.0.WOACNXM-user-16.0-x.zip" xiaomi' 2>/dev/null)"
[ "$RU" = "xiaomi https://bn.d.miui.com/OS3/xuanyuan-ota_full-OS3.0.312.0.WOACNXM-user-16.0-x.zip" ] \
    && ok "xiaomi direct link passthrough" || bad "xiaomi direct link"

# URL guards: private host + bad scheme rejected
bash "$HERE/getrom/getrom.sh" --outdir "$T/dl" 'http://127.0.0.1/rom.zip' 2>/dev/null \
    && bad "SSRF guard" || ok "SSRF guard rejects 127.0.0.1"
bash "$HERE/fuji" getRom 'javascript:alert(1)' 2>/dev/null \
    && bad "scheme guard" || ok "scheme guard rejects javascript:"

printf '\npass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
