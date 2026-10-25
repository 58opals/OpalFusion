#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./scripts/run-validation-loop.sh [mode]
       ./scripts/run-validation-loop.sh cashfusion-focused FILTER
       ./scripts/run-validation-loop.sh mosaic-focused FILTER
       ./scripts/run-validation-loop.sh profile-log LOG

Runs local validation with live coordinator proof disabled.
Every engine test-harness build has a separate 300-second deadline.

Modes:
  develop         Default: bounded CashFusion lifecycle/codecs/runtime checks.
  fast / cashfusion-all Run every CashFusion test within 60 seconds after build.
  build           Build only the CashFusion test harness.
  cashfusion-focused Run the selected CashFusion tests within 60 seconds.
  mosaic-focused  Run an explicit Mosaic filter within 7,200 seconds.
  codec / round / runtime / workflow / client / interop-parser
                  Run the named CashFusion suites within 60 seconds.
  mosaic / mosaic-all Run every deferred Mosaic and facade test (7,200 seconds).
  mosaic-fast     Run the material-free Mosaic feedback selection (15 seconds).
  mosaic-private-alpha-consumer-surface / mosaic-private-alpha-spi /
  mosaic-private-alpha-transport / mosaic-rehearsal
                  Run the named deferred Mosaic selection (7,200 seconds).
  assurance / all Explicitly run both complete harnesses with separate budgets.
  profile-log     Rank completed test/suite wall times from an existing log.
                  Analysis only; does not run tests or grant acceptance.
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
mode="${1:-develop}"
focus=""
log=""
if [[ "$mode" == "cashfusion-focused" || "$mode" == "mosaic-focused" || "$mode" == "profile-log" ]]; then
  if (( $# != 2 )) || [[ -z "$2" ]]; then
    usage
    exit 1
  fi
  if [[ "$mode" == "profile-log" ]]; then
    log="$2"
  else
    focus="$2"
  fi
elif (( $# > 1 )); then
  usage
  exit 1
fi

case "$mode" in
  --help|-h)
    usage
    exit 0
    ;;
  develop|fast|build|cashfusion-all|cashfusion-focused|codec|round|runtime|workflow|client|interop-parser|profile-log)
    ;;
  mosaic|mosaic-all|all|assurance|mosaic-fast|mosaic-focused|mosaic-private-alpha-consumer-surface|mosaic-private-alpha-spi|mosaic-private-alpha-transport|mosaic-rehearsal)
    ;;
  *)
    usage
    fail "Unknown validation mode: $mode"
    ;;
esac
swift_tool="$(/usr/bin/xcrun --find swift)" \
  || fail "The validation lanes require the selected Swift toolchain."
tool_scratch="$repo_root/.build/validation-tools"
"$swift_tool" build --package-path "$repo_root/Tools/Validation" \
  --scratch-path "$tool_scratch" --jobs 2 --product fusion-validation >&2
tool_products="$("$swift_tool" build --package-path "$repo_root/Tools/Validation" \
  --scratch-path "$tool_scratch" --show-bin-path)"
arguments=(--repo-root "$repo_root" --mode "$mode")
if [[ "$mode" == "cashfusion-focused" || "$mode" == "mosaic-focused" ]]; then
  arguments+=(--focus "$focus")
fi
if [[ "$mode" == "profile-log" ]]; then
  arguments+=(--log "$log")
fi
exec "$tool_products/fusion-validation" "${arguments[@]}"
