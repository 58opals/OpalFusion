#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
registry="$repo_root/docs/mosaic-g4-parser-implementation-files-2026-08-23.txt"
root_map="$repo_root/docs/mosaic-g4-parser-root-map-2026-08-23.txt"
composite_map="$repo_root/docs/mosaic-g4-parser-composite-root-map-2026-08-23.txt"
actual=$(mktemp)
mapped=$(mktemp)
composite_actual=$(mktemp)
composite_mapped=$(mktemp)
trap 'rm -f "$actual" "$mapped" "$composite_actual" "$composite_mapped"' EXIT HUP INT TERM

if ! command -v rg >/dev/null 2>&1; then
    echo "required command is unavailable: rg" >&2
    exit 1
fi
if [ ! -f "$registry" ]; then
    echo "parser implementation registry is missing" >&2
    exit 1
fi
if [ ! -f "$root_map" ]; then
    echo "parser root map is missing" >&2
    exit 1
fi
if [ ! -f "$composite_map" ]; then
    echo "parser composite root map is missing" >&2
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

if ! awk -F ' :: ' '
    NF != 4 {
        printf "invalid parser root-map row %d: expected four fields\n", NR > "/dev/stderr"
        failed = 1
        next
    }
    $1 == "" || $3 == "" || $4 == "" {
        printf "invalid parser root-map row %d: empty field\n", NR > "/dev/stderr"
        failed = 1
    }
    $2 != "covered" && $2 != "partial-variants" && $2 != "closure-budget" {
        printf "invalid parser root-map disposition at row %d: %s\n", NR, $2 > "/dev/stderr"
        failed = 1
    }
    seen[$1]++ {
        printf "duplicate parser root-map implementation file at row %d: %s\n", NR, $1 > "/dev/stderr"
        failed = 1
    }
    END { exit failed }
' "$root_map"; then
    exit 1
fi

awk -F ' :: ' '{ print $1 }' "$root_map" | LC_ALL=C sort > "$mapped"
if ! diff -u "$registry" "$mapped"; then
    echo "Mosaic parser root map does not cover the exact implementation-file registry" >&2
    exit 1
fi

map_count=$(wc -l < "$root_map" | tr -d ' ')
covered_count=$(awk -F ' :: ' '$2 == "covered" { count += 1 } END { print count + 0 }' "$root_map")
partial_count=$(awk -F ' :: ' '$2 == "partial-variants" { count += 1 } END { print count + 0 }' "$root_map")
closure_count=$(awk -F ' :: ' '$2 == "closure-budget" { count += 1 } END { print count + 0 }' "$root_map")

if [ "$map_count" -ne 52 ] || [ "$covered_count" -ne 52 ] || [ "$partial_count" -ne 0 ] || [ "$closure_count" -ne 0 ]; then
    echo "unexpected parser root-map disposition counts: total=$map_count covered=$covered_count partial=$partial_count closure=$closure_count" >&2
    exit 1
fi

echo "Mosaic G4 parser root registry passed (52 files: 52 covered, 0 partial variants, 0 closure-budget)"

(
    cd "$repo_root"
    LC_ALL=C rg -o \
        'public static func (openTransportBootstrap[A-Za-z0-9_]+|restoreTransportBootstrapPublication)' \
        Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapConsensusEnvelope.swift \
        Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapEnvelope.swift \
        Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationRestoration.swift \
        | sed 's/.*public static func //' | LC_ALL=C sort -u
) > "$composite_actual"

if ! awk -F ' :: ' '
    NF != 4 {
        printf "invalid parser composite-root row %d: expected four fields\n", NR > "/dev/stderr"
        failed = 1
        next
    }
    $1 == "" || $2 == "" || $3 == "" || $4 == "" {
        printf "invalid parser composite-root row %d: empty field\n", NR > "/dev/stderr"
        failed = 1
    }
    seen[$1]++ {
        printf "duplicate parser composite root at row %d: %s\n", NR, $1 > "/dev/stderr"
        failed = 1
    }
    END { exit failed }
' "$composite_map"; then
    exit 1
fi

awk -F ' :: ' '{ print $1 }' "$composite_map" \
    | LC_ALL=C sort > "$composite_mapped"
if ! diff -u "$composite_actual" "$composite_mapped"; then
    echo "Mosaic parser composite map does not cover the exact public transport entrypoints" >&2
    exit 1
fi

composite_count=$(wc -l < "$composite_map" | tr -d ' ')
if [ "$composite_count" -ne 9 ]; then
    echo "expected 9 parser composite roots, found $composite_count" >&2
    exit 1
fi

if ! git -C "$repo_root" diff --quiet \
    117949b08f354f5a58b78075dbf14b2ec4e4f88f..79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46 \
    -- \
    Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapConsensusEnvelope.swift \
    Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapEnvelope.swift \
    Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationRestoration.swift \
    Tests/OpalFusionTests/MosaicPrivateAlphaTransportBootstrapValidator.swift; then
    echo "transport composite sources or their integration evidence changed after the passing G2 checkpoint" >&2
    exit 1
fi

echo "Mosaic G4 parser composite registry passed (9 transport parents; passing G2 parity retained)"
