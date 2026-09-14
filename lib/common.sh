#!/usr/bin/env bash
# lib/common.sh — shared helpers (log, tool check, URL validation, tiny JSON emit).
# Sourced by other scripts, never executed directly.
# shellcheck disable=SC2155

set -u

log()   { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
info()  { log "INFO:  $*"; }
warn()  { log "WARN:  $*"; }
error() { log "ERROR: $*"; }
die()   { error "$*"; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

# Escape a string for embedding in JSON double quotes.
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# --- URL safety (§60-62 doc 1): never interpolate raw user input into shell ---
valid_scheme() {
    case "$1" in
        https://*|http://*|ftp://*|sftp://*|magnet:\?*) return 0 ;;
        *) return 1 ;;
    esac
}

url_host() {
    # strip scheme, then cut at first / ? # :
    local no_scheme="${1#*://}"
    no_scheme="${no_scheme%%/*}"
    no_scheme="${no_scheme%%\?*}"
    no_scheme="${no_scheme%%\#*}"
    printf '%s' "${no_scheme%%:*}"
}

private_host() {
    # literal private/loopback/link-local hosts (SSRF guard, §62 doc 1)
    case "$1" in
        localhost|127.*|10.*|192.168.*|169.254.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|::1|fc*|fe80:*)
            return 0 ;;
        *) return 1 ;;
    esac
}

check_url() {
    valid_scheme "$1" || die "rejected URL (bad scheme, want http/https/ftp/sftp/magnet): $1"
    local host
    host="$(url_host "$1")"
    [ -n "$host" ] || die "rejected URL (empty host): $1"
    private_host "$host" && die "rejected URL (private/loopback host): $host"
}
