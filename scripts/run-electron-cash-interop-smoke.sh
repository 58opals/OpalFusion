#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./scripts/run-electron-cash-interop-smoke.sh [run-count>=1]
       ./scripts/run-electron-cash-interop-smoke.sh --run-count N [--summary /non/repo/path.md] [--force]

Runs the env-gated Electron Cash 4.4.3-compatible interop smoke. Summary output is redacted and must be written outside this repository.

Options:
  --run-count N  Number of consecutive live smoke runs. Defaults to 1.
  --summary PATH Absolute summary output path outside this repository.
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
run_count="1"
has_run_count=0
summary_path=""
force=0

while (( $# > 0 )); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --run-count)
      if (( $# < 2 )); then
        usage
        exit 1
      fi
      run_count="$2"
      has_run_count=1
      shift 2
      ;;
    --summary)
      if (( $# < 2 )); then
        usage
        exit 1
      fi
      summary_path="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    <->)
      if (( has_run_count == 1 )); then
        usage
        exit 1
      fi
      run_count="$1"
      has_run_count=1
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ "$run_count" != <-> ]] || (( run_count < 1 )); then
  fail "Run count must be an integer greater than or equal to 1."
fi

canonical_summary_path=""
if [[ -n "$summary_path" ]]; then
  if [[ "$summary_path" != /* ]]; then
    fail "Summary output path must be absolute."
  fi

  summary_parent="${summary_path:h}"
  if [[ ! -d "$summary_parent" ]]; then
    fail "Summary output directory does not exist: $summary_parent"
  fi

  canonical_summary_parent="$(cd "$summary_parent" && pwd -P)"
  canonical_summary_path="${canonical_summary_parent}/${summary_path:t}"
  case "$canonical_summary_path" in
    "$repo_root"|"$repo_root"/*)
      fail "Summary output path must be outside this repository: $canonical_summary_path"
      ;;
  esac

  if [[ -e "$canonical_summary_path" && "$force" -ne 1 ]]; then
    fail "Summary output already exists. Pass --force to overwrite: $canonical_summary_path"
  fi
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

summary_rows=()
started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_status="passed"
overall_exit_status=0

write_summary() {
  if [[ -z "$canonical_summary_path" ]]; then
    return
  fi

  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  {
    echo "# Electron Cash Interop Smoke Summary"
    echo ""
    echo "- Baseline: Electron Cash 4.4.3-compatible CashFusion coordinator"
    echo "- Run count requested: $run_count"
    echo "- Overall result: $overall_status"
    echo "- Started at: $started_at"
    echo "- Finished at: $finished_at"
    echo "- Redaction: coordinator configuration, environment values, wallet material, addresses, private keys, and Tor settings are omitted"
    echo ""
    echo "| Run | Result | Exit Status | Elapsed Seconds |"
    echo "| --- | --- | --- | --- |"
    for row in "${summary_rows[@]}"; do
      echo "$row"
    done
  } > "$canonical_summary_path"
}

spm_package resolve

for (( run_index = 1; run_index <= run_count; run_index += 1 )); do
  echo "[interop smoke ${run_index}/${run_count}] Running Electron Cash 4.4.3 session-level proof"
  run_started_epoch="$(date +%s)"
  set +e
  spm_test --filter ElectronCashInteropValidator
  run_status=$?
  set -e
  run_finished_epoch="$(date +%s)"
  elapsed_seconds=$(( run_finished_epoch - run_started_epoch ))

  if (( run_status == 0 )); then
    result="passed"
  else
    result="failed"
    overall_status="failed"
    overall_exit_status="$run_status"
  fi

  summary_rows+=("| $run_index | $result | $run_status | $elapsed_seconds |")
  echo "[interop smoke ${run_index}/${run_count}] ${result} in ${elapsed_seconds}s"

  if (( run_status != 0 )); then
    break
  fi
done

write_summary
if [[ -n "$canonical_summary_path" ]]; then
  echo "[interop smoke] Wrote redacted summary to $canonical_summary_path"
fi

exit "$overall_exit_status"
