#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./scripts/run-validation-loop.sh <mode>

Runs public-safe OpalFusion validation loops without live coordinator proofing.

Modes:
  build           Build the package.
  all             Run the deterministic local test suite.
  codec           Run primary/covert codec and official protobuf fixture tests.
  round           Run scripted round-engine tests.
  runtime         Run primary/covert runtime and live-driver loopback tests.
  workflow        Run production workflow tests.
  client          Run public client session tests.
  mosaic          Run the bounded Mosaic conformance and facade tests.
  interop-parser  Run Electron Cash interop parser/environment tests only.
  --help          Show this usage.
USAGE
}

fail() {
  echo "$1" >&2
  exit 1
}

script_path="${0:A}"
script_dir="${script_path:h}"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
cd "$repo_root"

if (( $# != 1 )); then
  usage
  exit 1
fi

mode="$1"

SPM_SCRATCH_PATH=".build"
SPM_CACHE_PATH=".build"
SPM_CONFIG_PATH=".swiftpm-cache/validation/config"
SPM_SECURITY_PATH=".swiftpm-cache/validation/security"
SPM_MODULE_CACHE_PATH=".swiftpm-cache/validation/module-cache"
SPM_LANE_FLAGS=(
  --disable-sandbox
  --scratch-path "$SPM_SCRATCH_PATH"
  --cache-path "$SPM_CACHE_PATH"
  --config-path "$SPM_CONFIG_PATH"
  --security-path "$SPM_SECURITY_PATH"
  --manifest-cache local
)
export CLANG_MODULE_CACHE_PATH="$repo_root/$SPM_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

run_build() {
  swift build "${SPM_LANE_FLAGS[@]}"
}

run_test() {
  OPALFUSION_EC_INTEROP= swift test "${SPM_LANE_FLAGS[@]}" "$@"
}

run_filter() {
  local filter_name="$1"
  run_test --filter "$filter_name"
}

run_serial_filter() {
  local filter_name="$1"
  run_test --no-parallel --filter "$filter_name"
}

MOSAIC_RSA_DEPENDENT_FILTER='MosaicMainnetAlphaRuntimeSessionValidator|MosaicMainnetAlphaAdmissionLedgerValidator|MosaicMainnetAlphaConductorCoordinatorValidator|MosaicMainnetAlphaContributorExecutorValidator|MosaicMainnetAlphaLocalBCHSignatureBuilderValidator|MosaicOpalV0AuthorizationValidator'
MOSAIC_MATERIAL_FILTER='MosaicMainnetAlpha4MaterialValidator'
MAXIMUM_PARALLEL_TEST_WIDTH=4

run_mosaic_rsa_dependent_tests() {
  # Keep the two real purpose-separated evaluator fixtures in one process and
  # outside the parallel pool. OpalCrypto serializes its Security.framework RSA operations.
  run_serial_filter "$MOSAIC_RSA_DEPENDENT_FILTER"
}

run_bounded_test() {
  run_test \
    --experimental-maximum-parallelization-width "$MAXIMUM_PARALLEL_TEST_WIDTH" \
    "$@"
}

case "$mode" in
  --help|-h)
    usage
    ;;
  build)
    run_build
    ;;
  all)
    run_mosaic_rsa_dependent_tests
    run_serial_filter "$MOSAIC_MATERIAL_FILTER"
    run_serial_filter MosaicMainnetAlphaContractValidator
    run_serial_filter ClientSessionValidator
    run_bounded_test \
      --skip "$MOSAIC_RSA_DEPENDENT_FILTER|$MOSAIC_MATERIAL_FILTER|MosaicMainnetAlphaContractValidator|ClientSessionValidator"
    ;;
  codec)
    run_filter CashFusionPrimaryMessageCodecValidator
    run_filter CashFusionCovertMessageCodecValidator
    run_filter CashFusionOfficialProtobufFixtureValidator
    ;;
  round)
    run_filter RoundEngineScriptedValidator
    ;;
  runtime)
    run_filter PrimaryRuntimeSessionValidator
    run_filter CovertRuntimeSessionValidator
    run_filter LiveRuntimeDriverValidator
    ;;
  workflow)
    run_filter ProductionWorkflowValidator
    ;;
  client)
    run_filter ClientSessionValidator
    ;;
  mosaic)
    run_mosaic_rsa_dependent_tests
    run_serial_filter "$MOSAIC_MATERIAL_FILTER"
    run_bounded_test --filter Mosaic \
      --skip "$MOSAIC_RSA_DEPENDENT_FILTER|$MOSAIC_MATERIAL_FILTER|MosaicMainnetAlphaContractValidator"
    run_serial_filter MosaicMainnetAlphaContractValidator
    run_filter FusionFacadeScaffoldValidator
    ;;
  interop-parser)
    run_filter ElectronCashInteropValidator
    ;;
  *)
    usage
    fail "Unknown validation mode: $mode"
    ;;
esac
