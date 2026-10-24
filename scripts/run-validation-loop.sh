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

case "$mode" in
  --help|-h)
    usage
    exit 0
    ;;
  fast|build|cashfusion-all|cashfusion-focused|codec|round|runtime|workflow|client|interop-parser)
    ;;
  mosaic|mosaic-all|all|mosaic-fast|mosaic-private-alpha-consumer-surface|mosaic-private-alpha-spi|mosaic-private-alpha-transport|mosaic-rehearsal)
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
