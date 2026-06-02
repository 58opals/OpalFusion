# Electron Cash Transcript Capture

This guide describes how to produce a reviewed Swift fixture candidate for pinned Electron Cash transcript replay. The capture path is intentionally env-gated, writes outside the repository, and does not commit coordinator bytes by itself.

## Capture Command

Run the capture only from a configured local environment that can already pass the live Electron Cash interop smoke:

```sh
./scripts/run-electron-cash-transcript-capture.sh --output /private/tmp/opalfusion-electron-cash-transcript.swift
```

Use `--force` only when deliberately replacing an existing reviewed candidate:

```sh
./scripts/run-electron-cash-transcript-capture.sh --output /private/tmp/opalfusion-electron-cash-transcript.swift --force
```

The script rejects relative paths and output paths inside this repository. It sets `OPALFUSION_EC_INTEROP=1` and `OPALFUSION_EC_CAPTURE_TRANSCRIPT=1`, runs `ElectronCashInteropValidator`, extracts the marked fixture candidate, and writes only that candidate to the requested file.

## Required Environment

The runner requires the same live smoke configuration as `scripts/run-electron-cash-interop-smoke.sh`:

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

The capture candidate is emitted only after the live smoke succeeds, the session reaches success, expected primary and covert message kinds are present, and all native decode-failure logs are empty.

## Review Checklist

Before any candidate is copied into a test fixture, inspect the output file manually:

- Confirm the provenance comment says it came from the env-gated Electron Cash interop smoke and fill in the capture date.
- Confirm the candidate contains only primary framed bytes, covert payload bytes, message-kind sequences, round outcomes, event summaries, and sanitized provenance strings.
- Reject and delete the candidate if it contains private keys, coordinator hostnames, Tor proxy settings, wallet addresses, reusable wallet material, raw environment dictionaries, or any secret-bearing local configuration.
- Keep the reviewed candidate outside the repository until the pinned replay slice copies only the approved fixture data into test-only source.

## Failure Behavior

The runner writes no fixture candidate when required configuration is missing, the live smoke fails, capture markers are absent, the marked block is empty, or the output path is unsafe. These failures should be fixed by correcting the live smoke setup or capture harness before attempting pinned replay.
