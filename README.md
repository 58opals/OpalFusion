# Opal Fusion

Opal Fusion is the BCH CashFusion protocol and runtime package in the Opal stack. It sits below `OpalBase` and above `OpalCrypto` so CashFusion-specific coordinator connectivity, covert transport, round state handling, commitments, blind-signature flow, and blame handling can live in one focused package.

## Scope

This bootstrap keeps the package intentionally narrow:

- CashFusion protocol/runtime boundaries only.
- No Wallet UI or product-shell behavior.
- No generic BCH app orchestration that belongs in `OpalBase`.
- No generic cryptography helpers that belong in `OpalCrypto`.
- No Fulcrum transport responsibilities that belong in `SwiftFulcrum`.

## Current Status

- Class `D` dual-remote package scaffold.
- Minimal public `OpalFusion` namespace and host boundary only.
- No external package dependencies yet.
- Real interop work, protocol message models, and `OpalCrypto` wiring come later.

## Requirements

- Swift tools version: `6.2`
- Platforms:
  - `macOS 26`
  - `iOS 26`
  - `watchOS 26`
  - `tvOS 26`
  - `visionOS 26`

## Build

```bash
swift build
```
