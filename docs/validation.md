# OpalFusion Validation Guide

This guide separates fast deterministic package checks from slow live CashFusion proofing and future Mosaic conformance work. The default development loop should not depend on waiting for a real coordinator round.

## Default Local Loop

Run the full deterministic local suite for normal repo work:

```bash
swift test
```

Run a build-only check when you only need package compilation:

```bash
swift build
```

The current OpalCrypto dependency compiles a Metal library through a SwiftPM build plugin. Install the matching Xcode Metal Toolchain component before running package builds; a missing component stops the dependency build before OpalFusion sources or tests compile.

Use the validation wrapper when you want stable named loops:

```bash
./scripts/run-validation-loop.sh build
./scripts/run-validation-loop.sh all
./scripts/run-validation-loop.sh codec
./scripts/run-validation-loop.sh round
./scripts/run-validation-loop.sh runtime
./scripts/run-validation-loop.sh workflow
./scripts/run-validation-loop.sh client
./scripts/run-validation-loop.sh mosaic
./scripts/run-validation-loop.sh interop-parser
```

The wrapper keeps the live Electron Cash coordinator proof disabled for deterministic modes, even when the caller has an interop flag in their shell environment.

The local suite covers the protocol-neutral facade invariants, native protobuf primitives, official/manual CashFusion bytes, primary/covert codecs, pinned Electron Cash constants, round-engine scripts, production workflow materialization, loopback runtime behavior, host boundaries, and diagnostics.

## Coverage Boundary

Passing `swift test` or `./scripts/run-validation-loop.sh all` means the deterministic package checks passed. It does not prove complete OpalFusion capability, complete Electron Cash compatibility, successful operation against a real coordinator, or any live Mosaic support.

The current Mosaic checks cover the attempt, role, roster, reservation, transcript, terminal, retry, generation, deterministic simulation, Opal v0 authorization, canonical component, aggregate, relay-validation, strict replay, runtime-driver ordering, structural wallet-host boundaries, and the ordered host coordinator. Coordinator tests deterministically suspend reservation, publication, signing-request construction, and signing to prove both sides of the release-versus-publication/signing gates, late-lease release, release-before-terminal ordering, no automatic release after signing may have begun, terminal local-result source closure, exact complete-transaction commit instead of the legacy commit overload, and recovery-required release or commit failure. Mainnet-alpha coverage additionally pins the profile and genesis identifiers, role documents, complete manifest and locally agreed proposal context, PlayerCommit, profile-separated authorization and transcript digests, kind-bounded strict typed reassembly, authenticated outer-identity/control publisher/round/phase/expiry admission, anonymous sender and recipient binding, inner pre-sign acknowledgement, signature-set wire ordering, component-committed and resolved previous-output amount equality, P2PKH signature verification, the 100-byte unlocking script, exact unsigned-body matching, the 184-nonblank-component limit, and the complete-transaction payload. Cross-profile, malformed canonical bytes, foreign round, wrong phase or publisher, copied-root transaction substitution, legacy mainnet host markers, driver initialization, wrong outpoint, amount, or locking script, and invalid BCH signature cases fail closed.

The transcript-binding contract supports Opal v0 and mainnet-alpha, while `RuntimeSessionDriver` supports only Opal v0 and rejects draft and mainnet-alpha. The coordinator uses injected request, publication, inclusion, signature, and complete-transaction providers; these checks do not prove their production implementations, discovery, the Pedersen and commitment-opening/component-linkage algorithms, production lease-to-material or local-inclusion validation, previous-output resolution by a live host, anonymous BCH-signature authorization, mailbox-to-runtime integration, concrete Tor routing, durable crash recovery, independent protocol or side-channel review, mailbox unlinkability, anonymous transport, blame cryptography, broadcast safety, or live mainnet execution.

The current local suite does not replace a live coordinator smoke, reviewed transcript replay, wallet/app integration validation, or host-owned policy checks for coin selection, funding, signing authority, persistence, broadcast, retry behavior, and user-facing fusion controls. Those responsibilities remain separate proof gates or downstream integration concerns.

Use the fast loop to validate package behavior while editing. Use the live smoke and transcript replay path to establish CashFusion interoperability evidence.

## Focused Filters

Use focused filters while iterating on a specific layer:

```bash
swift test --filter CashFusionPrimaryMessageCodecValidator
swift test --filter CashFusionCovertMessageCodecValidator
swift test --filter CashFusionOfficialProtobufFixtureValidator
swift test --filter RoundEngineScriptedValidator
swift test --filter PrimaryRuntimeSessionValidator
swift test --filter LiveRuntimeDriverValidator
swift test --filter ProductionWorkflowValidator
swift test --filter ClientSessionValidator
swift test --filter FusionFacadeScaffoldValidator
swift test --filter MosaicAttemptCoreValidator
swift test --filter MosaicRoleElectionValidator
swift test --filter MosaicManifestAgreementValidator
swift test --filter MosaicManifestSignatureValidator
swift test --filter MosaicUnsignedTransactionTranscriptValidator
swift test --filter MosaicRuntimeSessionValidator
swift test --filter MosaicRuntimeSessionDriverValidator
swift test --filter MosaicRuntimeCoordinatorValidator
swift test --filter MosaicSemanticValidator
swift test --filter MosaicNostrRelayMessageCodecValidator
swift test --filter MosaicNIP01RelaySessionValidator
swift test --filter MosaicOpalV0ProfileValidator
swift test --filter MosaicOpalV0AuthorizationValidator
swift test --filter MosaicOpalV0WireContractValidator
swift test --filter MosaicOpalV0TransportContractValidator
swift test --filter MosaicHostContractValidator
swift test --filter MosaicMainnetAlphaContractValidator
```

Use these as fast feedback loops before running broader validation. They are deterministic and do not require coordinator credentials, wallet secrets, live UTXOs, Tor, or funded test material.

`./scripts/run-validation-loop.sh mosaic` runs every `Mosaic*` suite followed by `FusionFacadeScaffoldValidator`. Passing it proves only the bounded deterministic conformance and public-scaffold checks described above.

## Live Electron Cash Smoke

The live smoke runner is an opt-in proof gate for a configured Electron Cash `4.4.3`-compatible coordinator environment:

```bash
./scripts/run-electron-cash-interop-smoke.sh --run-count 1
./scripts/run-electron-cash-interop-smoke.sh 3
```

The real coordinator session proof is registered as an opt-in Swift Testing test and remains disabled for normal local validation. The runner enables the interop gate for the test process, verifies the live proof test identifier is registered, and then executes the filtered interop suite. A successful script run is still only live-smoke evidence for the configured environment; complete compatibility remains blocked until repeated smoke and reviewed transcript replay evidence exist.

The runner requires `OPALFUSION_EC_*` environment variables and intentionally omits their values from output. Keep coordinator hostnames, ports, wallet material, private keys, scripts, addresses, Tor settings, and raw environment dictionaries out of repo docs and committed artifacts.

## Transcript Capture And Replay Direction

Transcript capture is the bridge from slow live proofing to fast local replay:

```bash
./scripts/run-electron-cash-transcript-capture.sh --output /private/tmp/opalfusion-electron-cash-transcript.swift
```

Use capture only after a configured live smoke actually executes and passes the real coordinator session proof. The capture candidate must be reviewed outside the repository, stripped to approved test-only primary/covert byte fixtures, then committed in a later replay slice. Once replay fixtures exist, they should become the fast Electron Cash compatibility loop, while live smoke remains the slower confidence gate.

## Acceptance For Docs And Protocol Changes

- Run `swift test` after changes that touch examples, public API references, protocol behavior, or validation docs.
- Run the most relevant focused filter first when changing a narrow layer.
- Run live smoke only when the goal is coordinator-backed proof and the environment is configured.
- Update [Opal Fusion Specification](opal-fusion-specification.md), [Mosaic Protocol Specification](mosaic-protocol-specification.md), and [Mosaic Security Model](mosaic-security-model.md) together when shared boundaries or Mosaic invariants change.
- Update [CashFusion Official Protocol Matrix](cashfusion-official-protocol-matrix.md) when row-level support status or test evidence changes.
- Update [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) when the public support claim or remaining proof gates change.
