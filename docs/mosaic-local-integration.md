# Local Mosaic integration

Mosaic gives macOS BCH builders protocol execution and recovery contracts for a peer-conducted collaborative transaction. A host retains its inputs, signing policy, durable state and broadcast authority. The current SPI is an experimental local integration surface; the public generic Mosaic session remains disabled.

Use `@_spi(MosaicPrivateAlpha) import OpalFusion` only in the protocol integration layer. Wallet builders should enter through OpalBase's wallet-host facade. Do not construct a second coordinator alongside `MosaicPrivateAlphaRuntime.Owner`.

## One attempt

1. Create a fresh binding and claim its `Owner`, or load exact authenticated recovery bytes for the original binding. Persist every requested transition and return exact durable readback before continuing.
2. Admit the signed formation documents and complete manifest agreement. Preserve the independent protocol (`Mosaic/0-opal-mainnet-alpha.4`), transport (`nostr-tor/0-opal-mainnet-alpha.5`) and private-deployment/bootstrap identifiers.
3. Bind the role's mailbox, journal, clock and route capabilities once. Construct contributor execution with the host's exact reservation/signing authority, or conductor execution with the existing authorization capabilities. Start that one execution.
4. Supervise `expiryUnixSeconds`. At the final deadline an authenticated timeout abort may still be valid. After it, call `stopIfExpired(currentUnixSeconds:)`; this stops inbound execution and requests outbound stop without issuing an expired signature or manufacturing a protocol abort. Claim termination to verify outbound drain. Earlier calls return `false`. Clock and wake scheduling remain host responsibilities.
5. Claim termination once. A post-sign stop retains its exact reservation recovery reference. Only validated protocol completion/abort evidence may authorize the corresponding terminal transition. Other outcomes require wallet/journal reconciliation; do not discard reservations or retry in place.

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
swift test --no-parallel --filter drainExpiredExecutionWithoutTerminalAuthority
swift test --no-parallel --filter requireRecoveryAfterSigningCancellation
./scripts/run-validation-loop.sh mosaic-private-alpha-consumer-surface
./scripts/run-validation-loop.sh mosaic-rehearsal
```

The expiry test uses the existing signed formation fixture, scripted route capabilities and journal readback to check the boundary, delayed wake, drain and recovery reference. The rehearsal executes real cryptographic authorization and exact transaction validation with synthetic host data. RSA fixtures and deterministic keys are public test material and must never hold value. These commands contact no relay, Tor deployment or chain service; ordinary package resolution may fetch dependencies. See [validation](validation.md) for required broader checks and runtime budgets.

Formation requires 7–9 candidates, including a noncontributing conductor, and a 300-second discovery epoch. Measure local execution separately from participant waiting and simulated protocol time. Local logical participants are not independent people. The [security model](mosaic-security-model.md) describes conductor/collusion, amount linkage, selective abort and Sybil limits, including the accepted off-commitment accountability limitation. This example establishes no anonymity or CashFusion-equivalent privacy claim.
