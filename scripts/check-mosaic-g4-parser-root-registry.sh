#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
registry="$repo_root/docs/mosaic-g4-parser-implementation-files-2026-08-23.txt"
actual=$(mktemp)
trap 'rm -f "$actual"' EXIT HUP INT TERM

if ! command -v rg >/dev/null 2>&1; then
    echo "required command is unavailable: rg" >&2
    exit 1
fi
if [ ! -f "$registry" ]; then
    echo "parser implementation registry is missing" >&2
    exit 1
fi

(
    cd "$repo_root"
    LC_ALL=C rg -l \
        'CanonicalDecoder\.decode|JSONDecoder\(\)\.decode' \
        Sources/OpalFusion/Mosaic | LC_ALL=C sort
) > "$actual"

if ! diff -u "$registry" "$actual"; then
    echo "Mosaic parser implementation files changed; review roots and update the registry" >&2
    exit 1
fi

count=$(wc -l < "$registry" | tr -d ' ')
if [ "$count" -ne 52 ]; then
    echo "expected 52 registered parser implementation files, found $count" >&2
    exit 1
fi

echo "Mosaic G4 parser implementation registry passed (52 files)"
