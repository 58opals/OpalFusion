#!/bin/zsh

set -euo pipefail

run_count="${1:-1}"
if [[ "${run_count}" != <-> ]] || (( run_count < 1 )); then
  echo "usage: ./scripts/run-electron-cash-interop-smoke.sh [run-count>=1]" >&2
  exit 1
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

spm_package resolve

for (( run_index = 1; run_index <= run_count; run_index += 1 )); do
  echo "[interop smoke ${run_index}/${run_count}] Running Electron Cash 4.4.3 session-level proof"
  spm_test --filter ElectronCashInteropValidator
done
