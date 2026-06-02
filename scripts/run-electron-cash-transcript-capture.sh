#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./scripts/run-electron-cash-transcript-capture.sh --output /non/repo/path.swift [--force]

Runs the env-gated Electron Cash interop smoke with transcript capture enabled, then writes the sanitized Swift fixture candidate to the requested output path.

Options:
  --output PATH  Absolute output path outside this repository.
  --force        Overwrite PATH when it already exists.
  --help         Show this usage.
USAGE
}

fail() {
  echo "$1" >&2
  exit 1
}

script_path="${0:A}"
script_dir="${script_path:h}"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
output_path=""
force=0

while (( $# > 0 )); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --output)
      if (( $# < 2 )); then
        usage
        exit 1
      fi
      output_path="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$output_path" ]]; then
  fail "Missing required --output /non/repo/path.swift"
fi
if [[ "$output_path" != /* ]]; then
  fail "Capture output path must be absolute."
fi

output_parent="${output_path:h}"
if [[ ! -d "$output_parent" ]]; then
  fail "Capture output directory does not exist: $output_parent"
fi

canonical_output_parent="$(cd "$output_parent" && pwd -P)"
canonical_output_path="${canonical_output_parent}/${output_path:t}"
case "$canonical_output_path" in
  "$repo_root"|"$repo_root"/*)
    fail "Capture output path must be outside this repository: $canonical_output_path"
    ;;
esac

if [[ -e "$canonical_output_path" && "$force" -ne 1 ]]; then
  fail "Capture output already exists. Pass --force to overwrite: $canonical_output_path"
fi

required_vars=(
  OPALFUSION_EC_COORDINATOR_HOST
  OPALFUSION_EC_COORDINATOR_PORT
  OPALFUSION_EC_GENESIS_HASH_HEX
  OPALFUSION_EC_JOIN_TIER
  OPALFUSION_EC_INPUT_TXID_HEX
  OPALFUSION_EC_INPUT_VOUT
  OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS
  OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX
  OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX
  OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX
  OPALFUSION_EC_OUTPUT_AMOUNT_SATOSHIS
)

missing_vars=()
for variable_name in "${required_vars[@]}"; do
  if [[ -z "${(P)variable_name:-}" ]]; then
    missing_vars+=("${variable_name}")
  fi
done

if (( ${#missing_vars[@]} > 0 )); then
  echo "Missing required Electron Cash interop environment variables:" >&2
  for variable_name in "${missing_vars[@]}"; do
    echo "  - ${variable_name}" >&2
  done
  exit 1
fi

export OPALFUSION_EC_INTEROP=1
export OPALFUSION_EC_CAPTURE_TRANSCRIPT=1

SPM_SCRATCH_PATH=".swiftpm-cache/swiftpm/build"
SPM_CACHE_PATH=".swiftpm-cache/swiftpm/cache"
SPM_CONFIG_PATH=".swiftpm-cache/swiftpm/config"
SPM_SECURITY_PATH=".swiftpm-cache/swiftpm/security"
SPM_LANE_FLAGS=(
  --disable-sandbox
  --scratch-path "$SPM_SCRATCH_PATH"
  --cache-path "$SPM_CACHE_PATH"
  --config-path "$SPM_CONFIG_PATH"
  --security-path "$SPM_SECURITY_PATH"
)

spm_package() { swift package "${SPM_LANE_FLAGS[@]}" "$@"; }
spm_test() { swift test "${SPM_LANE_FLAGS[@]}" "$@"; }

begin_marker="-----BEGIN OPALFUSION ELECTRON CASH TRANSCRIPT CAPTURE-----"
end_marker="-----END OPALFUSION ELECTRON CASH TRANSCRIPT CAPTURE-----"
tmp_log=""
tmp_output=""
cleanup() {
  if [[ -n "$tmp_log" ]]; then
    rm -f "$tmp_log"
  fi
  if [[ -n "$tmp_output" ]]; then
    rm -f "$tmp_output"
  fi
}
trap cleanup EXIT

tmp_log="$(mktemp -t opalfusion-ec-capture.XXXXXX.log)"
tmp_output="$(mktemp -t opalfusion-ec-capture.XXXXXX.swift)"

spm_package resolve

echo "[transcript capture] Running Electron Cash 4.4.3 session-level proof"
if ! spm_test --filter ElectronCashInteropValidator 2>&1 | tee "$tmp_log"; then
  fail "Transcript capture smoke failed; no fixture candidate was written."
fi

if ! awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin {
    capturing = 1
    found = 1
    next
  }
  $0 == end && capturing {
    capturing = 0
    done = 1
    exit
  }
  capturing {
    print
  }
  END {
    if (!found || !done) {
      exit 2
    }
  }
' "$tmp_log" > "$tmp_output"; then
  fail "Transcript capture markers were not found; no fixture candidate was written."
fi

if [[ ! -s "$tmp_output" ]]; then
  fail "Transcript capture fixture candidate was empty; no fixture candidate was written."
fi

mv "$tmp_output" "$canonical_output_path"
tmp_output=""
echo "[transcript capture] Wrote sanitized fixture candidate to $canonical_output_path"
