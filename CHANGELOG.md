# Changelog

## Unreleased

- Added the Opal Fusion umbrella specification, Mosaic draft protocol and security specifications, and compile-time facade scaffolding for explicit CashFusion, Mosaic, and pre-reservation automatic selection modes.
- Added this changelog to track public-facing package changes.
- Added guarded Electron Cash interop test registration and a focused validation-loop script for faster local development checks.
- Documented the boundary between deterministic local validation, live coordinator proofing, transcript replay, and downstream wallet/app responsibilities.
- Refreshed public developer documentation with an integrator-first README, integration guide, validation guide, architecture guide, and clearer live-smoke proof caveats.
- Updated the `OpalCrypto` `develop` dependency lock from `bf0aaf1ec9ad2d3d273ffd2cb7e7731bb8540b90` to `4788919cc9772b5123554b84428f6fbeb5bfc91b`.
- Migrated `OpalDiagnostics` from `develop` revision `c3556731176e2be04c90d5542cf7049c8abe1f79` to SemVer `0.2.0` at `8c42eeb40d64776789e70694e4e5006d2afa400c`, refreshed `OpalCrypto` `develop` to `9903d6fc6fb90f2a4e8e8a27319db9e2049ae5af`, and adapted explicit diagnostics privacy, trace identifiers, canonical Pedersen setup, and proof ciphertext budgets.
