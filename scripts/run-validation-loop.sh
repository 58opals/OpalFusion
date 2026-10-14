#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./scripts/run-validation-loop.sh [mode]
       ./scripts/run-validation-loop.sh cashfusion-focused FILTER

Runs local validation with live coordinator proof disabled.
Every build has a separate 300-second deadline.

Modes:
  fast / cashfusion-all Run every CashFusion test within 60 seconds after build.
  build           Build only the CashFusion test harness.
  cashfusion-focused Run the selected CashFusion tests within 60 seconds.
  codec / round / runtime / workflow / client / interop-parser
                  Run the named CashFusion suites within 60 seconds.
  mosaic / mosaic-all Run every deferred Mosaic and facade test (7,200 seconds).
  mosaic-fast     Run the material-free Mosaic feedback selection (15 seconds).
  mosaic-private-alpha-consumer-surface / mosaic-private-alpha-spi /
  mosaic-private-alpha-transport / mosaic-rehearsal
                  Run the named deferred Mosaic selection (7,200 seconds).
  all             Explicitly run both complete harnesses with separate budgets.
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
mode="${1:-fast}"
focus=""
if [[ "$mode" == "cashfusion-focused" ]]; then
  if (( $# != 2 )) || [[ -z "$2" ]]; then
    usage
    exit 1
  fi
  focus="$2"
elif (( $# > 1 )); then
  usage
  exit 1
fi

assert_mosaic_fast_lane_is_rsa_free() {
  local banned_pattern='requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\('
  local fast_files=(
    Tests/Mosaic/Tests/MosaicEngineTests/MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator.swift
    Tests/Mosaic/Tests/MosaicEngineTests/MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator.swift
  )
  command -v rg >/dev/null 2>&1 \
    || fail "The Mosaic fast lane requires rg for its RSA-fixture guard."
  if rg -n "$banned_pattern" "${fast_files[@]}"; then
    fail "The Mosaic fast lane reached an RSA evaluator or real-material fixture."
  fi
}

assert_mosaic_reservation_dependency_lane_is_material_free() {
  local banned_pattern='requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\(|LocalContributionMaterial\.build\(|makeLocalContributionMaterial\(|makeMaterializedPreparation\('
  local dependency_file=Tests/Mosaic/Tests/MosaicEngineTests/MosaicMainnetAlphaReservationCoordinatorDependencyValidator.swift
  command -v rg >/dev/null 2>&1 \
    || fail "The Mosaic reservation dependency lane requires rg for its material guard."
  if rg -n "$banned_pattern" "$dependency_file"; then
    fail "The Mosaic reservation dependency lane reached evaluator or material construction."
  fi
}

assert_mosaic_private_alpha_consumer_surface_is_not_testable() {
  local consumer_file=Tests/Mosaic/Tests/MosaicEngineTests/MosaicPrivateAlphaRuntimeRecoveryValidator.swift
  command -v rg >/dev/null 2>&1 \
    || fail "The private-alpha consumer-surface lane requires rg for its import guard."
  if rg -n '@testable[[:space:]]+import[[:space:]]+(OpalFusion|OpalFusionCore|MosaicEngine)' "$consumer_file"; then
    fail "The private-alpha consumer-surface lane must not use @testable import."
  fi
}

assert_mosaic_private_alpha_transport_is_generation_free() {
  local transport_files=(
    Tests/Mosaic/Tests/MosaicEngineTests/MosaicPrivateAlphaTransportBootstrapValidator.swift
    Tests/Mosaic/Tests/MosaicEngineTests/RFC9500RSATestKeyFixture.swift
  )
  command -v rg >/dev/null 2>&1 \
    || fail "The private-alpha transport lane requires rg for its RSA-generation guard."
  if rg -n -U 'RSABSSA\.SigningKey[[:space:]]*\.generate\(' "${transport_files[@]}"; then
    fail "The private-alpha transport lane must use its standard public test key fixture."
  fi
}

case "$mode" in
  --help|-h)
    usage
    exit 0
    ;;
  fast|build|cashfusion-all|cashfusion-focused|codec|round|runtime|workflow|client|interop-parser)
    ;;
  mosaic|mosaic-all|all)
    assert_mosaic_fast_lane_is_rsa_free
    assert_mosaic_reservation_dependency_lane_is_material_free
    assert_mosaic_private_alpha_consumer_surface_is_not_testable
    assert_mosaic_private_alpha_transport_is_generation_free
    ;;
  mosaic-fast)
    assert_mosaic_fast_lane_is_rsa_free
    ;;
  mosaic-private-alpha-consumer-surface)
    assert_mosaic_private_alpha_consumer_surface_is_not_testable
    ;;
  mosaic-private-alpha-spi|mosaic-private-alpha-transport)
    assert_mosaic_private_alpha_transport_is_generation_free
    ;;
  mosaic-rehearsal)
    ;;
  *)
    usage
    fail "Unknown validation mode: $mode"
    ;;
esac
command -v python3 >/dev/null 2>&1 \
  || fail "The validation lanes require Python 3."
arguments=(--repo-root "$repo_root" --mode "$mode")
if [[ "$mode" == "cashfusion-focused" ]]; then
  arguments+=(--focus "$focus")
fi
exec python3 -B "$script_dir/run-fast-validation.py" "${arguments[@]}"
