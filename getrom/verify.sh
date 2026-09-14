#!/usr/bin/env bash
# getrom/verify.sh — size/sha256/file-magic check + getrom.json (§44-47, §55 doc 1).
# Usage: verify_and_report <file> <jobdir> <input> <provider> <backend> [expected_sha256]

set -u
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

verify_and_report() {
    local file="$1" jobdir="$2" input="$3" provider="$4" backend="$5" expected="${6:-}" minb="${7:-0}"
    local size sha magic verified="false" status="completed"
    [ -f "$file" ] || { status="failed"; verified="false"; }

    if [ "$status" = "completed" ]; then
        size="$(stat -c%s "$file")"
        [ "$size" -gt 0 ] || { status="failed"; size=0; }
    fi
    if [ "$status" = "completed" ] && [ "$minb" -gt 0 ] && [ "$size" -lt "$minb" ]; then
        status="failed"
        warn "file too small ($size bytes < $minb): likely a truncated/error download"
    fi
    if [ "$status" = "completed" ]; then
        magic="$(file -b "$file" | cut -c1-80)"
        # ROMs must be archives/images, not HTML error pages (§47 doc 1)
        if printf '%s' "$magic" | grep -qi 'html'; then
            status="failed"
            warn "file looks like an HTML error page, not a ROM"
        fi
    fi
    if [ "$status" = "completed" ]; then
        sha="$(sha256sum "$file" | awk '{print $1}')"
        if [ -n "$expected" ]; then
            if [ "$sha" = "$expected" ]; then verified="true";
            else status="corrupted";
                 warn "sha256 mismatch: got $sha want $expected"; fi
        else
            verified="size-only"
        fi
    else
        size="${size:-0}"; sha=""; magic="${magic:-unknown}"
    fi

    cat > "$jobdir/getrom.json" <<EOF
{
  "job_id": "$(json_escape "$(basename "$jobdir")")",
  "input": "$(json_escape "$input")",
  "provider": "$(json_escape "$provider")",
  "backend": "$(json_escape "$backend")",
  "filename": "$(json_escape "$(basename "$file")")",
  "path": "$(json_escape "$file")",
  "size": ${size:-0},
  "sha256": "${sha:-}",
  "file_type": "$(json_escape "${magic:-unknown}")",
  "status": "$status",
  "verified": "$verified"
}
EOF
    printf '%s/getrom.json' "$jobdir"
    [ "$status" = "completed" ]
}
