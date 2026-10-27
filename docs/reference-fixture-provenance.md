# Independently qualified reference fixtures

The unchanged reference fixtures were independently requalified on October 27, 2026 against the official source bytes below. This establishes their present identity and derivation; it does not reconstruct their original import or generation history. No upstream Python, protobuf runtime, live coordinator or Tor service is needed by these offline checks.

## Electron Cash 4.4.3

The official `Electron-Cash/Electron-Cash` tag `4.4.3` resolved to commit `124a6d9be80190b987fbb4854d9931e9073b17f2`. The following hashes cover complete raw files at that immutable commit, including their notices and line endings.

| Reference | Immutable official source | SHA-256 |
| --- | --- | --- |
| Schema | [fusion.proto](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/124a6d9be80190b987fbb4854d9931e9073b17f2/electroncash_plugins/fusion/protobuf/fusion.proto) | `22b8a137176c28ecd12bb6fde8c44662b555a470e79a5203105e363abf9307da` |
| Framing | [connection.py](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/124a6d9be80190b987fbb4854d9931e9073b17f2/electroncash_plugins/fusion/connection.py) | `662d803626da26b304d88f139e35508f6ef0416f4c264ea77c767ec387307ef8` |
| Constants | [protocol.py](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/124a6d9be80190b987fbb4854d9931e9073b17f2/electroncash_plugins/fusion/protocol.py) | `1848765adcbd8cb5b235693aeaf824a0aa28df6f3d66570efac01e740b9728fb` |
| License | [LICENCE](https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/124a6d9be80190b987fbb4854d9931e9073b17f2/LICENCE) | `3e6dae555eb92787fc82d1d48355677f454c7f65aeb38d3f9e72bf9a3daf034b` |

`CashFusionOfficialProtobufFixtures.swift` retains all 37 existing arrays. Their independent reconstruction used schema field numbers and types, not OpalFusion's encoder or decoder. Following the [protobuf wire format](https://protobuf.dev/programming-guides/encoding/), a tag is the unsigned base-128 varint `(fieldNumber << 3) | wireType`; varints emit seven low bits per byte, with the continuation bit set except in the final byte. Length-delimited values prefix their byte length. `fixed64` values use eight little-endian bytes. Fields use ascending field-number order except for the deliberate unknown-field prefixes and conflicting-oneof concatenations below. Required empty/zero values remain encoded; absent optional and empty repeated fields are omitted.

The reconstruction rules for the complete named fixture inventory are:

| Fixture group | Independent input or deliberate mutation |
| --- | --- |
| `clientHelloEmptyVersion`, `serverHelloRequiredZero`, `poolTagRequiredZero`, `fusionBeginRequiredZero`, `startRoundRequiredZero`, `playerCommitRequiredZero`, `fusionResultRequiredFalse`, `myProofsListRequiredEmptyRandomNumber`, `relayedProofRequiredZero` | Encode the schema's required fields with empty bytes, zero integers, zero fixed64 times or false, as named. All names in this table have the `Bytes` suffix in Swift. |
| `serverHelloPackedTiers`, `serverHelloUnpackedTiers`, `fusionResultPackedBadComponents`, `fusionResultUnpackedBadComponents` | Repeated integers are `[1, 300]`; use either one length-delimited varint sequence or two individual varint fields, retaining the required zero/false fields. Both forms are protobuf-compatible inputs. |
| `joinPoolsEmpty`, `blindSigResponsesEmpty`, `allCommitmentsEmpty`, `shareCovertComponentsEmpty`, `theirProofsListEmpty`, `emptyError` | Empty repeated-only messages or an absent optional error message encode to zero bytes. |
| `tierStatusDuplicateMapKey`, `tierStatusLastWinsMapKey` | A map entry uses key field 1 and value field 2. Both keys are 1; the first nested status has `players=1`, the second `min_players=2`. Encode both entries for the duplicate case, or only the second for its last-wins expectation. |
| `blameProofSessionKey`, `blameProofPrivateKeyWithReason` | Respectively `which_proof=0, session_key=aa`; and `which_proof=1, privkey=bb, need_lookup_blockchain=true, blame_reason="ok"`. |
| `covertComponentWithoutRoundKey`, `covertTransactionSignatureWithoutRoundKey`, `errorMessage` | Respectively signature `30` and component `31`; input index 0 and signature `61`; UTF-8 error text `ok`. Omit the optional round key. |
| `clientBlamesEnvelopeWithoutDecrypter` | Wrap a `BlameProof` with only `which_proof=1` inside `Blames`, then inside `ClientMessage.blames`. The missing decrypter is intentional. |
| `conflictingClientEnvelope`, `conflictingCovertEnvelope`, `conflictingCovertResponseEnvelope` | Concatenate two alternatives of the relevant oneof: ClientHello(version `01`) then empty JoinPools; the component above then empty Ping; empty OK then empty Error. These deliberately invalid envelopes test rejection. |
| `serverFusionBeginEnvelopeWithInvalidDomain`, `serverFailureEnvelopeWithInvalidMessage`, `covertFailureEnvelopeWithInvalidMessage` | Wrap only covert-domain bytes `ff`, or error-message bytes `ff`, in the named envelope. Invalid UTF-8 and missing required fields remain deliberate. |
| `malformedServerEnvelopeLength`, `malformedCovertResponseLength` | A length-delimited FusionBegin or Error envelope declares two payload bytes but provides only tag byte `08` or `0a`. These test truncation rejection. |
| `serverHelloEnvelopeWithUnknownPrefix`, `covertMessageEnvelopeWithUnknownPrefix` | Prefix unknown varint field 99 with value 1, then encode the required-zero ServerHello or the component above inside its envelope. |

The malformed and conflicting fixtures are local negative tests. Qualification establishes their source field positions and explicit mutations, not upstream server acceptance or rejection. In particular, generic protobuf decoders allow last-one-wins oneof handling; these samples preserve OpalFusion's stricter envelope-rejection contract. The `ff` domain is invalid for the native UTF-8 hostname interpretation even though the upstream field is bytes.

The resulting canonical inventory is 1,587 bytes with SHA-256 `deaed7aa5129170e3269c262d4fc34c2f9906d9bc34ccce9a35fd566fcb3ffd5`: sort the 37 Swift fixture names by ASCII order, then concatenate each UTF-8 name, one zero byte, its UInt32 big-endian byte count, and its unchanged array bytes. The added test recomputes this identity and binds this document to the pinned sources. Existing codec and malformed-input assertions remain authoritative for behavior.

The existing `FrameConfigurationValidator`, `TransportBaselineConfigurationValidator`, `ProtocolIdentityConfigurationValidator`, `CovertTimingConfigurationValidator` and `RoundTimingConfigurationValidator` expectations were checked against those raw files. Framing is magic `765be8b4e4396dcf`, a four-byte big-endian payload length, and a `200 * 1024` byte maximum. Identity constants are `alpha13`, `FUZ\0`, minimum output 10,000 satoshis, and Pedersen tag byte `02` followed by UTF-8 `CashFusion gives us fungibility.`. Covert connect timeout/window are 15/15 seconds, submit timeout/window 3/5 seconds, and spare count 6. The existing round timing assertions retain the source's clock discrepancy 5, warmup 30/slop 3, commitments 3, component start/deadline 5/15, signature start/deadline 20/30, conclusion 35, close/blame-close 45/80, standard timeout 3 and blame verification 5 seconds. No timing value or protocol byte changed.

This is current source and byte qualification, not captured live interoperability, complete upstream implementation equivalence, anonymity, a security audit or production readiness. The source files remain external references rather than vendored executable code. Offline tests guard qualified local bytes and pinned source metadata; they do not download or rehash absent upstream source files.

## RFC 9500 public RSA test key

The fixed publication is [RFC 9500, section 2.1](https://www.rfc-editor.org/rfc/rfc9500.html#section-2.1). The complete official [rfc9500.txt](https://www.rfc-editor.org/rfc/rfc9500.txt) fetched for this qualification has SHA-256 `838d15624be54dc05b5b803d1b7e117f3e15ad34337e83c1b24e9ce7bf0f2a1a`. This is a numbered RFC publication and content-hash pin, not a Git revision.

Select the PEM block following `RSA-2048 key "testRSA2048":`, remove its `BEGIN/END RSA PRIVATE KEY` delimiters and whitespace, then apply standard base64 decoding without ASN.1 re-encoding. Its 1,191 PKCS#1 DER bytes are exactly the existing fixture, with SHA-256 `5882709c242c6f47cef05fb6a601322092635fd40c639d7548e4f488f4fbddf8`. `ReferenceFixtureProvenanceTests` in the existing dependency-free validation target hashes the actual fixture source literal with CryptoKit and checks this source binding. It requires exactly one named private literal, removes only ASCII space/tab/line endings, rejects escapes or interpolation, and applies strict base64 decoding. This source-artifact check does not compile Mosaic or prove Security import/signing behavior; existing cryptographic tests continue to own those operations with the same fixture bytes.

The original IETF copyright and Revised BSD notice remain in `RFC9500RSATestKeyFixture.swift`; the [third-party notices](../THIRD_PARTY_NOTICES.md) retain attribution. This publicly known key has no security properties and remains confined to test targets. Neither current qualification nor its test asserts historical import provenance or independently regenerates the RSA key.

## Focused offline checks

Use the existing CashFusion runner and native validation-tool test target with compatible cache lanes:

```sh
./scripts/run-validation-loop.sh cashfusion-focused 'CashFusionOfficialProtobufFixtureValidator|FrameConfigurationValidator|TransportBaselineConfigurationValidator|ProtocolIdentityConfigurationValidator|CovertTimingConfigurationValidator|RoundTimingConfigurationValidator'
env -u SDKROOT /usr/bin/xcrun swift test --package-path Tools/Validation --scratch-path .build/validation-tools --jobs 2 --filter ReferenceFixtureProvenanceTests
```

The CashFusion fixture test also belongs to the existing default development selection. The RSA source check constructs no signing key, evaluator, material or live transport. Complete assurance remains separate, and live coordinator proof remains deferred.
