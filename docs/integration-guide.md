# OpalFusion Integration Guide

This guide is for app and OpalBase integrators wiring the current OpalFusion pilot surface into a wallet-owned product layer.

## Integration Model

OpalFusion owns CashFusion protocol/runtime behavior. The host owns coordinator selection, wallet policy, participant reservation, signing, persistence, broadcast, user-facing copy, and any retry cadence above the package-level reconnect policy.

The public session boundary is `OpalFusion.Client.Session`. The host supplies:

- `OpalFusion.Client.Configuration` for primary coordinator connection settings and covert-channel request settings.
- `OpalFusion.ProtocolModel.JoinPools` for the tiers and pool tags the host is willing to join.
- `OpalFusion.Host.ParticipantReservationSource` for round-scoped reserved inputs and outputs.
- `OpalFusion.Host.TransactionAssembler` for host-side transaction validation and signing.
- Optional `OpalFusion.Host.EventObserver` for coarse round events.
- Optional `OpalFusion.Client.StateObserver` for display-safe session snapshots.

## Session Setup

Use app-owned coordinator values. OpalFusion validates and consumes them, but it does not provide production defaults.

```swift
let covertChannel = OpalFusion.Transport.CovertChannelConfiguration(
    entryPath: "/fusion",
    maxPayloadBytes: 32_768,
    requestTimeoutMilliseconds: 15_000
)

let configuration = OpalFusion.Client.Configuration(
    coordinatorHost: "coordinator.example.invalid",
    coordinatorPort: 8787,
    coordinatorRequiresTLS: true,
    covertChannel: covertChannel,
    torSocks5: nil
)

let joinPools = OpalFusion.ProtocolModel.JoinPools(
    tiers: [10_000],
    tags: []
)
```

Primary TLS follows `coordinatorRequiresTLS`. Covert HTTP(S) follows the coordinator's `FusionBegin.covert_ssl`. Tor SOCKS5, when configured, applies to the covert HTTP(S) path only.

## Host Reservation Boundary

`ParticipantReservationSource` is called after `StartRound` gives OpalFusion the round identifier, selected tier, component count, fee rate, and excess-fee bounds. Use this context to reserve wallet-owned inputs and outputs atomically enough that the app will not double-spend them elsewhere while the round is active.

The current pilot-supported reservation path is intentionally narrow:

- Every local input must be standard compressed-key P2PKH.
- `ParticipantInput.publicKey` must contain the compressed public key matching the input locking script.
- Input outpoint hashes are passed in standard display order.
- Input and output locking scripts are raw BCH script bytecode and must be treated as diagnostics-private.
- Reservation failures should be thrown through typed host failures where possible so OpalFusion can surface `hostRejected` instead of a generic failure.

## Transaction Finalization Boundary

`TransactionAssembler` receives an `OpalFusion.Host.TransactionFinalizationProposal` containing the unsigned fusion transaction bytes, optional session hash, and expected transaction shape. The host must validate the proposal against wallet policy, sign only the intended local inputs, and return `OpalFusion.Host.FinalizedTransaction`.

For the current live path, the finalized transaction must preserve standard Schnorr P2PKH unlocking scripts for local inputs. OpalFusion parses those local unlocking scripts, verifies signatures against the reserved input public keys, extracts the 64-byte Schnorr signatures, and submits them through the covert channel.

Do not put broadcast, persistence, transaction-history mutation, or product approval prompts inside OpalFusion. Those remain host-owned decisions before or after the package returns round state.

## Observers And State

Use `StateObserver` when the app needs session-level display-safe snapshots. Use `EventObserver` when the host needs round-scoped progress events for orchestration, diagnostics routing, or integration logs.

`lastErrorSummary` and host event summaries are sanitized integration diagnostics. Do not supplement them with raw coordinator messages, OS errors, private keys, scripts, transaction bytes, addresses, Tor settings, or environment dictionaries in user-facing surfaces.

## Supported Pilot Checklist

- Provide a non-empty coordinator host, nonzero port, explicit TLS choice, valid covert entry path, positive covert payload limit, and positive covert timeout.
- Provide an optional 32-byte BCH genesis hash when the integration has one.
- Join at least one positive unique tier.
- Keep pool tags non-empty with positive limits when using them.
- Reserve compressed-key standard P2PKH inputs with matching public keys.
- Return a finalized transaction that preserves local Schnorr P2PKH unlocking scripts.
- Treat `.notImplemented` as an unsupported-path signal, not as coordinator incompatibility.

## Next References

- Use [Validation Guide](validation.md) to pick a fast local loop before trying live rounds.
- Use [Architecture Guide](architecture.md) to understand the package layers behind the public session.
- Use [CashFusion Native Swift Support Statement](cashfusion-native-support-statement.md) before making public support claims.
