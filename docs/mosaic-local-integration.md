# Local Mosaic integration

Mosaic gives macOS BCH builders protocol execution and recovery contracts for a peer-conducted collaborative transaction. A host retains its inputs, signing policy, durable state and broadcast authority. The current SPI is an experimental local integration surface; the public generic Mosaic session remains disabled.

Use `@_spi(MosaicPrivateAlpha) import OpalFusion` only in the protocol integration layer. Wallet builders should enter through OpalBase's wallet-host facade. Do not construct a second coordinator alongside `MosaicPrivateAlphaRuntime.Owner`.

## Discovery preparation

`MosaicPrivateAlphaRuntime.DiscoveryPreparation` validates a 300-second-aligned epoch and constructs its canonical pool and relay documents through the existing deployment-context factory. Supply a fresh 32-byte deployment-scoped pool identifier and three reviewed relay registrations. Distinct operator labels are required, but labels alone do not establish independent ownership; two endpoints advertising the same operator key must not be counted as independent operators.

Its `findAvailabilityNonce(discoveryVerificationKey:startingAt:count:)` searches a bounded batch using the frozen availability-work validator. A batch contains 1–65,536 nonces; zero, larger batches and overflowing ranges are rejected. Call off the UI actor, check cancellation between batches, and stop before `beaconCutoffUnixSeconds`. The host owns scheduling and fresh discovery/control key custody. Preparation creates no wallet, signature, network connection or persistent state and grants no permission to publish or spend.

## Public formation reception

`MosaicPrivateAlphaRuntime.PrivateDeploymentInbox` opens exactly three endpoint-bound Tor routes from the validated preparation. The routes must use distinct connection objects and isolation identifiers. It subscribes to the fixed formation kinds and epoch, authenticates the canonical event envelope, deduplicates relay copies, and records the first local receipt time. Supply the resulting `PrivateDeploymentEvent` to the existing durable `Owner`; the inbox does not authorize pool membership, roster agreement, or late admission.

The distinct-event and pending-stream bounds are explicit. Source loss, malformed input, or overflow terminates the inbox; cancellation closes its owned routes. The default 256-event limit can be lowered or raised to at most 1,024. A caller may inject a clock for deterministic tests, but a live host must use actual receipt time. This SPI creates no wallet authority and is separate from `TransportBootstrapInbox`, which receives recipient-bound encrypted post-manifest bootstrap envelopes.

## One attempt

1. Create a fresh binding and claim its `Owner`, or load exact authenticated recovery bytes for the original binding. Persist every requested transition and return exact durable readback before continuing.
2. Admit the signed formation documents and complete manifest agreement. Preserve the independent protocol (`Mosaic/0-opal-mainnet-alpha.4`), transport (`nostr-tor/0-opal-mainnet-alpha.5`) and private-deployment/bootstrap identifiers.
3. Bind the role's mailbox, journal, clock and route capabilities once. Construct contributor execution with the host's exact reservation/signing authority, or conductor execution with the existing authorization capabilities. Start that one execution.
4. Supervise `expiryUnixSeconds`. At the final deadline an authenticated timeout abort may still be valid. After it, call `stopIfExpired(currentUnixSeconds:)`; this stops inbound execution and requests outbound stop without issuing an expired signature or manufacturing a protocol abort. Claim termination to verify outbound drain. Earlier calls return `false`. Clock and wake scheduling remain host responsibilities.
5. Claim termination once. A post-sign stop retains its exact reservation recovery reference. Only validated protocol completion/abort evidence may authorize the corresponding terminal transition. Other outcomes require wallet/journal reconciliation; do not discard reservations or retry in place.

Fresh conductor execution publishes the complete authenticated manifest through its existing control bridge after receive intake starts. Every role, including the conductor, admits that message through the normal authenticated receive path before advancing. The host must not inject a synthetic manifest or start a competing publisher. Terminal reconstruction consumes the manifest's recorded publication batches before replaying coordinator outputs; it does not republish the manifest or allocate live routes.

```swift
// `execution` is the one owner-created PostManifestExecution.
// The supervisor supplies its clock and calls again after scheduled wakes.
let expiry = await execution.expiryUnixSeconds
if now > expiry {
    await execution.stopIfExpired(currentUnixSeconds: now)
}
// Claim waitForTermination once through the owning integration, then persist
// the resulting exact disposition. A stop is never broadcast permission.
```

## Reproduce with public synthetic fixtures

With Swift 6.4, macOS 27 and the matching Metal toolchain installed:

```sh
swift test --package-path Tests/Mosaic --no-parallel --filter drainExpiredExecutionWithoutTerminalAuthority
swift test --package-path Tests/Mosaic --no-parallel --filter requireRecoveryAfterSigningCancellation
./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface
./scripts/run-validation-loop.sh mosaic-rehearsal
```

The expiry test uses the existing signed formation fixture, scripted route capabilities and journal readback to check the boundary, delayed wake, drain and recovery reference. The rehearsal executes real cryptographic authorization and exact transaction validation with synthetic host data. RSA fixtures and deterministic keys are public test material and must never hold value. These commands contact no relay, Tor deployment or chain service; ordinary package resolution may fetch dependencies. See [validation](validation.md) for required broader checks and runtime budgets.

Formation requires 7–9 candidates, including a noncontributing conductor, and a 300-second discovery epoch. Measure local execution separately from participant waiting and simulated protocol time. Local logical participants are not independent people. The [security model](mosaic-security-model.md) describes conductor/collusion, amount linkage, selective abort and Sybil limits, including the accepted off-commitment accountability limitation. This example establishes no anonymity or CashFusion-equivalent privacy claim.

## Bounded route startup

Post-manifest receive setup starts at most 16 relay connections concurrently while retaining every required isolated route. Completion schedules the next route; cancellation or source loss stops queued startup and closes all owned routes. No relay selection, wire format, recipient capability or deadline changes. This bounds native handshake resource pressure; applications must still measure the complete route count and actual network latency against the frozen schedule.


## Durable acknowledgement coalescing

Concurrent publishers share their attempt's publication journal. A bounded recorder coalesces acknowledgement observations already waiting for persistence; it never waits for a missing relay. The journal validates the complete batch, atomically appends acknowledgements and their derived completions, and resolves an uncertain append through exact old/new snapshot readback. Every publisher waits for that durable result before reporting success. Cancellation does not discard an acknowledgement already observed; invalid or corrupt persistence still fails closed. This changes local write amplification only, preserving event bytes, endpoint isolation, quorum, retry authority and protocol deadlines.


Publication journal appends pass their complete validated prior records into the persistence adapter. The adapter re-encodes those canonical comparison bytes and uses the existing app-owned atomic compare-and-swap; it does not reload the same prior snapshot immediately before that comparison. Any different durable bytes are still rejected, including a divergent snapshot with the same record count. Uncertain writes still perform a fresh durable reload through the journal's reconciliation boundary. Stored bytes, exact readback, bounds and public interfaces remain unchanged.
