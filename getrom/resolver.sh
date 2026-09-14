#!/usr/bin/env bash
# getrom/resolver.sh — input detector + provider resolver (§9, §52-53 doc 1).
# Usage: type="$(detect_input "$input")"; resolved="$(resolve_url "$input" "$type")"
# Prints "<provider> <final-url-or-path>" on stdout for resolve_url.

set -u
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

detect_input() {
    local in="$1"
    if [ -f "$in" ]; then printf 'local'; return; fi
    case "$in" in
        magnet:\?*)            printf 'magnet'; return ;;
        file://*)              printf 'local'; return ;;
        *github.com*releases*|*github.com*download*) printf 'github'; return ;;
        *gitlab.com*{-/releases,*releases/download}*) printf 'gitlab'; return ;;
        *drive.google.com*)    printf 'gdrive'; return ;;
        *mifirm.net*)          printf 'mifirm'; return ;;
        *miui.com*|*xiaomi.com*|*hyperos*) printf 'xiaomi'; return ;;
        *.torrent)             printf 'torrent'; return ;;
        https://*|http://*)    printf 'direct_http'; return ;;
        ftp://*|sftp://*)      printf 'ftp'; return ;;
        *)                     printf 'unknown'; return ;;
    esac
}

# --- provider resolvers: each prints the real download URL ---

resolve_github() {
    # TAG form: https://github.com/USER/REPO/releases/tag/TAG (+ optional #asset=pattern)
    local url="$1" user_repo tag pattern re
    user_repo="$(printf '%s' "$url" | sed -n 's#.*github\.com/\([^/]*/[^/#?]*\).*#\1#p')"
    tag="$(printf '%s' "$url" | sed -n 's#.*/releases/tag/\([^/#?]*\).*#\1#p')"
    [ -n "$user_repo" ] && [ -n "$tag" ] || die "cannot parse github release URL: $url"
    pattern="$(printf '%s' "$url" | sed -n 's/.*[#?]asset=//p')"
    [ -n "$pattern" ] || pattern='*.zip'
    # resolve via API only (no download here); backend downloads the asset URL
    require_tool curl
    re="$(printf '%s' "$pattern" | sed 's/\./\\./g; s/\*/.*/g')"
    curl -fsSL "https://api.github.com/repos/${user_repo}/releases/tags/${tag}" \
        | grep -o "\"browser_download_url\": *\"[^\"]*\"" \
        | sed 's/.*": *"//; s/"$//' \
        | grep -m1 "$re" \
        || die "no matching asset ($pattern) in $user_repo@$tag"
}

resolve_gitlab() {
    # https://gitlab.com/GROUP/PROJ/-/releases/TAG -> API lookup
    local url="$1" proj tag enc
    require_tool curl
    proj="$(printf '%s' "$url" | sed -n 's#.*gitlab\.com/\(.*\)/-/releases/.*#\1#p')"
    tag="$(printf '%s' "$url" | sed -n 's#.*/-/releases/\([^/#?]*\).*#\1#p')"
    [ -n "$proj" ] && [ -n "$tag" ] || die "cannot parse gitlab release URL: $url"
    enc="$(printf '%s' "$proj" | sed 's#/#%2F#g')"
    curl -fsSL "https://gitlab.com/api/v4/projects/${enc}/releases/${tag}" \
        | grep -o "\"url\": *\"[^\"]*\"" \
        | sed 's/.*": *"//; s/"$//' | grep -m1 . \
        || die "no asset links in $proj@$tag"
}

resolve_mifirm_xiaomi() {
    # MiFirm/Xiaomi/HyperOS pages are JS-heavy: fetch HTML, extract first
    # direct CDN link (bigota / cdn). Best-effort fallback (§26 doc 1:
    # real fix is Playwright, out of scope for bash phase 1).
    local url="$1" cdn
    # already a direct file link (e.g. bn.d.miui.com/...zip)? use as-is —
    # never scrape a multi-GB file as if it were an HTML page.
    case "${url%%\?*}" in
        *.zip|*.tgz|*.tar.gz) printf '%s' "$url"; return ;;
    esac
    require_tool curl
    warn "page resolver is best-effort; prefer pasting the direct CDN link"
    cdn="$(curl -fsSL -A 'Mozilla/5.0' --max-time 60 "$url" \
        | grep -oiE 'https://[^"'"'"' >]*\.(zip|tgz|tar\.gz)(\?[^"'"'"' >]*)?' \
        | grep -m1 -iE 'bigota|cdn|miui|xiaomi|hyperos' || true)"
    [ -n "$cdn" ] || die "could not extract CDN link from page: $url"
    printf '%s' "$cdn"
}

resolve_url() {
    local input="$1" type="$2" strip
    case "$type" in
        local)
            strip="${input#file://}"
            [ -f "$strip" ] || die "local file not found: $strip"
            printf 'local %s' "$strip" ;;
        magnet|torrent)
            printf 'torrent %s' "$input" ;;
        github)
            printf 'github %s' "$(resolve_github "$input")" ;;
        gitlab)
            printf 'gitlab %s' "$(resolve_gitlab "$input")" ;;
        gdrive)
            require_tool rclone
            printf 'gdrive %s' "$input" ;;  # downloaded via rclone backend
        mifirm|xiaomi)
            printf '%s %s' "$type" "$(resolve_mifirm_xiaomi "$input")" ;;
        direct_http|ftp)
            check_url "$input"
            printf 'generic %s' "$input" ;;
        *)
            die "unknown input type for: $input" ;;
    esac
}
