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
  mosaic-fast     Run the RSA-free Mosaic lifecycle and wiring lane.
  mosaic-rehearsal Run the explicitly slow, no-network mainnet-alpha rehearsal.
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

SPM_SCRATCH_PATH="${OPALFUSION_SPM_SCRATCH_PATH:-.build}"
SPM_CACHE_PATH="${OPALFUSION_SPM_CACHE_PATH:-$SPM_SCRATCH_PATH}"
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

MOSAIC_RSA_DEPENDENT_FILTER='MosaicMainnetAlphaRuntimeSessionValidator|MosaicMainnetAlphaAdmissionLedgerValidator|MosaicMainnetAlphaConductorCoordinatorValidator|MosaicMainnetAlphaContributorExecutorValidator|MosaicMainnetAlphaLocalBCHSignatureBuilderValidator|MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator|MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator|MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator|MosaicMainnetAlphaReservationCoordinatorValidator|MosaicMainnetAlphaContractValidator|MosaicOpalV0AuthorizationValidator'
MOSAIC_FAST_FILTER='MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator|MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator'
MOSAIC_MAINNET_REHEARSAL_FILTER='executeSixContributorConductor|executeThroughExactCommit'
MOSAIC_MATERIAL_FILTER='MosaicMainnetAlpha4MaterialValidator'
MAXIMUM_PARALLEL_TEST_WIDTH=4

assert_mosaic_fast_lane_is_rsa_free() {
  local banned_pattern='requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\('
  local fast_files=(
    Tests/OpalFusionTests/MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator.swift
    Tests/OpalFusionTests/MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator.swift
  )
  command -v rg >/dev/null 2>&1 \
    || fail "The Mosaic fast lane requires rg for its RSA-fixture guard."
  if rg -n "$banned_pattern" "${fast_files[@]}"; then
    fail "The Mosaic fast lane reached an RSA evaluator or real-material fixture."
  fi
}

assert_mosaic_reservation_dependency_lane_is_material_free() {
  local banned_pattern='requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\(|LocalContributionMaterial\.build\(|makeLocalContributionMaterial\(|makeMaterializedPreparation\('
  local dependency_file=Tests/OpalFusionTests/MosaicMainnetAlphaReservationCoordinatorDependencyValidator.swift
  command -v rg >/dev/null 2>&1 \
    || fail "The Mosaic reservation dependency lane requires rg for its material guard."
  if rg -n "$banned_pattern" "$dependency_file"; then
    fail "The Mosaic reservation dependency lane reached evaluator or material construction."
  fi
}

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
    assert_mosaic_fast_lane_is_rsa_free
    assert_mosaic_reservation_dependency_lane_is_material_free
    run_mosaic_rsa_dependent_tests
    run_serial_filter "$MOSAIC_MATERIAL_FILTER"
    run_serial_filter ClientSessionValidator
    run_bounded_test \
      --skip "$MOSAIC_RSA_DEPENDENT_FILTER|$MOSAIC_MATERIAL_FILTER|ClientSessionValidator"
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
    assert_mosaic_fast_lane_is_rsa_free
    assert_mosaic_reservation_dependency_lane_is_material_free
    run_mosaic_rsa_dependent_tests
    run_serial_filter "$MOSAIC_MATERIAL_FILTER"
    run_bounded_test --filter Mosaic \
      --skip "$MOSAIC_RSA_DEPENDENT_FILTER|$MOSAIC_MATERIAL_FILTER"
    run_filter FusionFacadeScaffoldValidator
    ;;
  mosaic-fast)
    assert_mosaic_fast_lane_is_rsa_free
    run_bounded_test --filter "$MOSAIC_FAST_FILTER"
    ;;
  mosaic-rehearsal)
    # These two tests share the real purpose-separated RSA fixtures in one process.
    # Their wallet host is in-memory, and OpalFusion exposes no broadcast callback.
    run_serial_filter "$MOSAIC_MAINNET_REHEARSAL_FILTER"
    ;;
  interop-parser)
    run_filter ElectronCashInteropValidator
    ;;
  *)
    usage
    fail "Unknown validation mode: $mode"
    ;;
esac
