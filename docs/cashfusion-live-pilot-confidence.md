# Electron Cash Live Pilot Confidence

This guide describes the opt-in Electron Cash live smoke proof gate for the current OpalFusion pilot path. Normal local and CI validation do not run this smoke because it requires a real Electron Cash `4.4.3`-compatible coordinator and wallet material supplied through the environment.

The real coordinator session proof is registered as an opt-in Swift Testing test and remains disabled during normal local validation. The runner enables the interop gate for its test process and verifies that the live proof test identifier is registered before it starts a smoke run.

## Command

Run one configured live smoke:

```sh
./scripts/run-electron-cash-interop-smoke.sh --run-count 1
```

Run the current pilot-confidence target of three consecutive successful smokes:

```sh
./scripts/run-electron-cash-interop-smoke.sh 3
```

Write a redacted operational summary outside the repository:

```sh
./scripts/run-electron-cash-interop-smoke.sh --run-count 3 --summary /private/tmp/opalfusion-electron-cash-smoke-summary.md
```

Use `--force` only when deliberately replacing an existing summary file.

## Required Environment

The runner requires the same live coordinator configuration as the interop validator:

- `OPALFUSION_EC_COORDINATOR_HOST`
- `OPALFUSION_EC_COORDINATOR_PORT`
- `OPALFUSION_EC_GENESIS_HASH_HEX`
- `OPALFUSION_EC_JOIN_TIER`
- `OPALFUSION_EC_INPUT_TXID_HEX`
- `OPALFUSION_EC_INPUT_VOUT`
- `OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS`
- `OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX`
- `OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX`
- `OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX`
- `OPALFUSION_EC_OUTPUT_AMOUNT_SATOSHIS`

The script prints missing variable names when configuration is incomplete, but it never prints environment values. Optional Tor settings remain environment-owned and must not be copied into summaries or committed docs.

## Redacted Summary

The optional summary records the Electron Cash baseline, requested run count, overall pass/fail result, start and finish timestamps, and one row per attempted run with result, exit status, and elapsed seconds. It intentionally omits coordinator hostnames, ports, private keys, wallet addresses, raw scripts beyond what tests already own, Tor proxy details, and raw environment dictionaries.

Summary paths must be absolute and outside the repository. Missing environment configuration, invalid run counts, unsafe summary paths, and existing summary files without `--force` fail before writing a summary.

## Relationship To Transcript Replay

When a configured run passes, the live pilot-confidence runner demonstrates that the configured environment can reach session-level success against a real coordinator. It does not produce pinned transcript fixtures and does not replace local replay evidence.

Pinned transcript replay is a separate flow using `docs/cashfusion-transcript-capture.md` and `scripts/run-electron-cash-transcript-capture.sh`. Use the capture path only when the goal is to review and commit sanitized raw primary/covert bytes for native replay tests.
