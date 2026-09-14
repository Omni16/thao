#!/usr/bin/env bash
# getrom/backends.sh — downloader backends, priority: aria2 > curl > wget (§49 doc 1).
# Usage: backend_download <backend|auto> <url> <outdir> <filename>
# Echoes final filepath on stdout. All args quoted — never eval user input.

set -u
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have() { command -v "$1" >/dev/null 2>&1; }

pick_backend() {
    # $1 = provider hint (torrent|gdrive|ftp|generic)
    case "$1" in
        torrent) have aria2c && { printf 'aria2'; return; }
                 have transmission-cli && { printf 'transmission'; return; }
                 die "no torrent backend (need aria2c)" ;;
        gdrive)  have rclone && { printf 'rclone'; return; }
                 die "gdrive needs rclone" ;;
        ftp)     have aria2c && { printf 'aria2'; return; }
                 have curl && { printf 'curl'; return; }
                 have wget && { printf 'wget'; return; }
                 die "no ftp-capable backend" ;;
        *)       have aria2c && { printf 'aria2'; return; }
                 have curl && { printf 'curl'; return; }
                 have wget && { printf 'wget'; return; }
                 die "no HTTP backend (need aria2c/curl/wget)" ;;
    esac
}

dl_aria2() {  # $1 url, $2 outdir, $3 filename
    aria2c -c -x 16 -s 16 -k 1M --max-tries=10 --retry-wait=5 \
        --connect-timeout=30 --timeout=120 \
        --file-allocation=none --allow-overwrite=true \
        -d "$2" -o "$3" -- "$1"
}

dl_curl() {
    curl -fL --retry 10 --retry-all-errors -C - \
        --connect-timeout 30 -- "$1" -o "$2/$3"
}

dl_wget() {
    wget -c --tries=10 --timeout=60 \
        -O "$2/$3" -- "$1"
}

dl_rclone() {
    if [[ "$1" == drive:* ]] || [[ "$1" == *drive.google.com* ]]; then
        rclone copyurl --auto-filename -- "$1" "$2"
    else
        rclone copyurl -- "$1" "$2/$3"
    fi
}

dl_transmission() {
    transmission-cli -w "$2" -- "$1"
}

backend_download() {
    local backend="$1" url="$2" outdir="$3" filename="$4"
    local provider="$5"  # hint for auto-pick
    [ "$backend" = "auto" ] && backend="$(pick_backend "$provider")"
    mkdir -p "$outdir" "$outdir/logs"
    case "$backend" in
        aria2)        dl_aria2 "$url" "$outdir" "$filename" ;;
        curl)         dl_curl "$url" "$outdir" "$filename" ;;
        wget)         dl_wget "$url" "$outdir" "$filename" ;;
        rclone)       dl_rclone "$url" "$outdir" "$filename" ;;
        transmission) dl_transmission "$url" "$outdir" ;;
        *) die "unknown backend: $backend" ;;
    esac >"$outdir/logs/backend.log" 2>&1 || return 1
    # rclone --auto-filename may choose its own name
    if [ -f "$outdir/$filename" ]; then
        printf '%s/%s' "$outdir" "$filename"
    else
        ls -t "$outdir" | head -n1 | sed "s#^#$outdir/#"
    fi
}
