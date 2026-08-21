// MosaicPrivateAlphaTransportBootstrapValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic private-alpha transport bootstrap", .serialized)
struct MosaicPrivateAlphaTransportBootstrapValidator {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Canonicalize the reviewed relay policy and reject unsupported relay behavior")
    func canonicalizeRelayPolicy() throws {
        #expect(Runtime.transportBootstrapIdentifier
            == "nostr-tor/0-opal-mosaic-private-alpha-bootstrap.1")
        #expect(Runtime.transportBootstrapNostrSelector
            == "nostr-tor/0-opal-mosaic-boot.1")
        let registrations = (1 ... 3).map { index in
            Runtime.PrivateDeploymentRelayRegistration(
                endpoint: "WSS://Relay-\(index).Example:443/",
                reviewedOperatorRegistryLabel: "Operator \(index)",
                requiresNIP42Authentication: false,
                requiresProofOfWork: false
            )
        }
        let context = try Runtime.makePrivateDeploymentContextDocuments(
            opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
            relayRegistrations: registrations
        )
        #expect(context.relaySetDigest.count == 32)
        #expect(context.opaquePoolDocument.isEmpty == false)
        #expect(context.relaySetDocument.isEmpty == false)
        #expect(context.relayEndpointIdentifiers == [
            "wss://relay-1.example/",
            "wss://relay-2.example/",
            "wss://relay-3.example/",
        ])
        let reversed = try Runtime.makePrivateDeploymentContextDocuments(
            opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
            relayRegistrations: Array(registrations.reversed())
        )
        #expect(reversed == context)

        var nip42 = registrations
        nip42[0] = .init(
            endpoint: "wss://relay-1.example/",
            reviewedOperatorRegistryLabel: "Operator 1",
            requiresNIP42Authentication: true,
            requiresProofOfWork: false
        )
        #expect(throws: Runtime.PrivateDeploymentConfigurationFailure
            .unsupportedNIP42Authentication) {
            try Runtime.makePrivateDeploymentContextDocuments(
                opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
                relayRegistrations: nip42
            )
        }

        var proofOfWork = registrations
        proofOfWork[0] = .init(
            endpoint: "wss://relay-1.example/",
            reviewedOperatorRegistryLabel: "Operator 1",
            requiresNIP42Authentication: false,
            requiresProofOfWork: true
        )
        #expect(throws: Runtime.PrivateDeploymentConfigurationFailure
            .unsupportedProofOfWork) {
            try Runtime.makePrivateDeploymentContextDocuments(
                opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
                relayRegistrations: proofOfWork
            )
        }

        var duplicateOperator = registrations
        duplicateOperator[2] = .init(
            endpoint: "wss://relay-3.example/",
            reviewedOperatorRegistryLabel: "operator 1",
            requiresNIP42Authentication: false,
            requiresProofOfWork: false
        )
        #expect(throws: Runtime.PrivateDeploymentConfigurationFailure
            .duplicateRelayOperator) {
            try Runtime.makePrivateDeploymentContextDocuments(
                opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
                relayRegistrations: duplicateOperator
            )
        }

        var duplicateEndpoint = registrations
        duplicateEndpoint[2] = .init(
            endpoint: "wss://relay-1.example/",
            reviewedOperatorRegistryLabel: "Operator 3",
            requiresNIP42Authentication: false,
            requiresProofOfWork: false
        )
        #expect(throws: Runtime.PrivateDeploymentConfigurationFailure
            .duplicateRelayEndpoint) {
            try Runtime.makePrivateDeploymentContextDocuments(
                opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
                relayRegistrations: duplicateEndpoint
            )
        }

        var clearnetScheme = registrations
        clearnetScheme[0] = .init(
            endpoint: "https://relay-1.example/",
            reviewedOperatorRegistryLabel: "Operator 1",
            requiresNIP42Authentication: false,
            requiresProofOfWork: false
        )
        #expect(throws: Runtime.PrivateDeploymentConfigurationFailure
            .invalidRelayEndpoint) {
            try Runtime.makePrivateDeploymentContextDocuments(
                opaquePoolIdentifier: Data(repeating: 0x31, count: 32),
                relayRegistrations: clearnetScheme
            )
        }
    }

    @Test("Authenticate blind registration before minting either mailbox role")
    func authenticateCompleteMailboxDistribution() throws {
        let fixture = try Self.makeFixture()
        #expect(fixture.proof.controlIdentities.count >= 7)

        let discoveryIdentity = try #require(
            fixture.proof.preManifestEventIdentities.first(where: {
                !fixture.proof.controlIdentities.contains($0)
            })
        )
        let conductor = fixture.proof.conductorControlIdentity
        #expect(throws: Runtime.TransportBootstrapFailure.identityReuse) {
            try Runtime.makeTransportBootstrapControlMailboxClaim(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                controlSigningKey: try fixture.controlSigningKey(
                    for: conductor
                ),
                recipientEventVerificationKey: try .init(
                    rawRepresentation: discoveryIdentity
                ),
                anonymousMailboxRequest: nil,
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0x3A, count: 32)
                )
            )
        }

        let contributor = try #require(
            fixture.proof.contributorControlIdentities.first
        )
        let contributorRecipientKey = try #require(
            fixture.controlRecipientKeys[contributor]
        )
        let registration = try #require(
            fixture.registrations[contributor]
        )
        let request = try #require(fixture.requests[contributor])
        let anonymousSenderPrivateKey = try #require(
            fixture.anonymousSenderPrivateKeys[contributor]
        )
        let contributorIndex = try #require(
            fixture.proof.contributorControlIdentities.firstIndex(
                of: contributor
            )
        )
        let restoredRequest = try Runtime
            .restoreTransportBootstrapAnonymousMailboxRequest(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                authorizationNonce: Data(
                    repeating: UInt8(0x80 + contributorIndex),
                    count: 32
                ),
                anonymousSenderPrivateKey: anonymousSenderPrivateKey,
                recoveryState: request.recoveryState,
                expectedBlindedMessage: request.blindedMessage
            )
        #expect(restoredRequest.blindedMessage == request.blindedMessage)
        #expect(restoredRequest.recoveryState == request.recoveryState)
        #expect(throws: Runtime.TransportBootstrapFailure.invalidBinding) {
            try Runtime.restoreTransportBootstrapAnonymousMailboxRequest(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                authorizationNonce: Data(
                    repeating: UInt8(0x80 + contributorIndex),
                    count: 32
                ),
                anonymousSenderPrivateKey: anonymousSenderPrivateKey,
                recoveryState: request.recoveryState,
                expectedBlindedMessage: Data(repeating: 0xFF, count: 256)
            )
        }
        let conductorAssignment = try #require(
            fixture.conductorAssignments[contributor]
        )
        let assignment = conductorAssignment.assignment
        #expect(
            fixture.claimSet.canonicalDocument.range(
                of: registration.anonymousSenderEventIdentity
            ) == nil
        )
        #expect(
            fixture.registrationSet.canonicalDocument.range(
                of: registration.anonymousSenderEventIdentity
            ) == nil
        )
        for identity in assignment.recipientEventIdentities {
            #expect(
                fixture.registrationSet.canonicalDocument.range(
                    of: identity
                ) == nil
            )
        }
        #expect(throws: Runtime.TransportBootstrapFailure
            .invalidAcknowledgementSet) {
            try Runtime
                .makeTransportBootstrapRegistrationSetAcknowledgementSet(
                    proof: fixture.proof,
                    authorizationKey: fixture.authorizationKey,
                    claimSet: fixture.claimSet,
                    responseSet: fixture.responseSet,
                    registrationSet: fixture.registrationSet,
                    acknowledgements: Array(
                        fixture.acknowledgementSet.acknowledgements
                            .dropLast()
                    ),
                    currentUnixSeconds: fixture.currentUnixSeconds
                )
        }
        var duplicateRegistrations = Array(
            fixture.registrations.values
        )
        duplicateRegistrations[duplicateRegistrations.count - 1]
            = duplicateRegistrations[0]
        #expect(throws: Runtime.TransportBootstrapFailure
            .invalidRegistrationSet) {
            try Runtime
                .makeTransportBootstrapAnonymousMailboxRegistrationSet(
                    proof: fixture.proof,
                    authorizationKey: fixture.authorizationKey,
                    claimSet: fixture.claimSet,
                    responseSet: fixture.responseSet,
                    registrations: duplicateRegistrations,
                    conductorAssignments: Array(
                        fixture.conductorAssignments.values
                    ),
                    conductorControlSigningKey: try fixture.controlSigningKey(
                        for: conductor
                    ),
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating: 0x3C,
                            count: 32
                        )
                    ),
                    currentUnixSeconds: fixture.currentUnixSeconds
                )
        }

        var reusedKeys = try (0 ..< 23).map { slot in
            try Self.makePrivateKey(seed: 9_000 + slot)
        }
        reusedKeys[0] = try #require(
            fixture.controlRecipientPrivateKeys[conductor]
        )
        #expect(throws: Runtime.TransportBootstrapFailure.identityReuse) {
            try Runtime.makeTransportBootstrapAnonymousMailboxAssignment(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registration: registration,
                recipientPrivateKeys: reusedKeys,
                conductorControlSigningKey: try fixture.controlSigningKey(
                    for: conductor
                ),
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0x3B, count: 32)
                ),
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        }

        let contributorDistribution = try Runtime
            .makeContributorTransportBootstrapMailboxDistribution(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registration: registration,
                assignment: assignment,
                registrationSet: fixture.registrationSet,
                acknowledgementSet: fixture.acknowledgementSet,
                contributorControlIdentity: contributor,
                localControlRecipientSigningKey:
                    contributorRecipientKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(
            contributorDistribution.controlClaimSetDigest
                == fixture.claimSet.digest
        )
        #expect(
            contributorDistribution.registrationSetDigest
                == fixture.registrationSet.digest
        )
        #expect(
            contributorDistribution.mailboxCapabilities
                .controlMailboxes.count
                == fixture.proof.controlIdentities.count
        )
        if case let .contributor(keys) = contributorDistribution
            .mailboxCapabilities.anonymous {
            #expect(keys.count == 23)
            #expect(
                keys.map(\.rawRepresentation)
                    == assignment.recipientEventIdentities
            )
        } else {
            Issue.record("Contributor distribution returned conductor keys.")
        }

        let conductorKey = try fixture.controlSigningKey(for: conductor)
        let conductorRecipientKey = try #require(
            fixture.controlRecipientKeys[conductor]
        )
        let conductorDistribution = try Runtime
            .makeConductorTransportBootstrapMailboxDistribution(
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registrations: Array(fixture.registrations.values),
                conductorAssignments:
                    Array(fixture.conductorAssignments.values),
                registrationSet: fixture.registrationSet,
                acknowledgementSet: fixture.acknowledgementSet,
                localControlRecipientSigningKey:
                    conductorRecipientKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        if case let .conductor(keys) = conductorDistribution
            .mailboxCapabilities.anonymous {
            #expect(
                keys.count
                    == fixture.proof.contributorControlIdentities.count * 23
            )
        } else {
            Issue.record("Conductor distribution returned contributor keys.")
        }

        var tampered = fixture.registrationSet.canonicalDocument
        tampered[tampered.startIndex + 8] ^= 0x01
        #expect(throws: Runtime.TransportBootstrapFailure.self) {
            try Runtime.loadTransportBootstrapAnonymousMailboxRegistrationSet(
                from: tampered,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        }

        let anonymousRecipientKey = try #require(
            fixture.anonymousSenderKeys[contributor]
        )
        let assignmentPublication = try Runtime
            .sealTransportBootstrapAnonymousMailboxAssignment(
                assignment,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registration: registration,
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                wrapperSigningKey: try Self.makeSigningKey(seed: 7_900),
                reservedEventIdentities: [],
                timestamps: fixture.timestamps
            )
        let openedAssignment = try Runtime
            .openTransportBootstrapAnonymousMailboxAssignment(
                from: assignmentPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registration: registration,
                anonymousRecipientSigningKey: anonymousRecipientKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedAssignment.document == assignment)
        #expect(
            try Runtime.restoreTransportBootstrapPublication(
                canonicalEventBytes:
                    assignmentPublication.canonicalEventBytes,
                canonicalDocument: assignment.canonicalDocument,
                senderEventIdentity: conductor,
                recipientEventIdentity:
                    registration.anonymousSenderEventIdentity,
                proof: fixture.proof,
                binding: fixture.binding,
                expectedOperationIdentifier:
                    assignmentPublication.operationIdentifier,
                currentUnixSeconds: fixture.currentUnixSeconds
            ) == assignmentPublication
        )
        #expect(throws: Runtime.TransportBootstrapFailure.invalidBinding) {
            try Runtime.restoreTransportBootstrapPublication(
                canonicalEventBytes:
                    assignmentPublication.canonicalEventBytes,
                canonicalDocument: assignment.canonicalDocument,
                senderEventIdentity: contributor,
                recipientEventIdentity:
                    registration.anonymousSenderEventIdentity,
                proof: fixture.proof,
                binding: fixture.binding,
                expectedOperationIdentifier:
                    assignmentPublication.operationIdentifier,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        }
    }

    @Test("Seal and open every bootstrap document role")
    func sealAndOpenEveryDocumentRole() throws {
        let fixture = try Self.makeFixture()
        let conductor = fixture.proof.conductorControlIdentity
        let conductorKey = try fixture.controlSigningKey(for: conductor)
        let contributor = try #require(
            fixture.proof.contributorControlIdentities.first
        )
        let contributorKey = try fixture.controlSigningKey(for: contributor)
        let registration = try #require(
            fixture.registrations[contributor]
        )
        let anonymousSenderKey = try #require(
            fixture.anonymousSenderKeys[contributor]
        )
        let assignment = try #require(
            fixture.conductorAssignments[contributor]
        ).assignment
        let conductorAssignments = Array(
            fixture.conductorAssignments.values
        )
        var reservedEventIdentities = Set<Data>()

        let authorizationPublication = try Runtime
            .sealTransportBootstrapAuthorizationKeyDocument(
                fixture.authorizationKey,
                proof: fixture.proof,
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                recipientControlIdentity: contributor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_200),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        reservedEventIdentities.insert(
            authorizationPublication.wrapperEventIdentity
        )
        let openedAuthorization = try Runtime
            .openTransportBootstrapAuthorizationKeyDocument(
                from: authorizationPublication.canonicalEventBytes,
                proof: fixture.proof,
                recipientControlSigningKey: contributorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedAuthorization.document == fixture.authorizationKey)

        let responsePublication = try Runtime
            .sealTransportBootstrapBlindResponseSet(
                fixture.responseSet,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                recipientContributorControlIdentity: contributor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_201),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        reservedEventIdentities.insert(
            responsePublication.wrapperEventIdentity
        )
        let openedResponse = try Runtime
            .openTransportBootstrapBlindResponseSet(
                from: responsePublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                recipientContributorControlSigningKey: contributorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedResponse.document == fixture.responseSet)

        let registrationPublication = try Runtime
            .sealTransportBootstrapAnonymousMailboxRegistration(
                registration,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                binding: fixture.binding,
                anonymousSenderSigningKey: anonymousSenderKey,
                conductorControlIdentity: conductor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_202),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        reservedEventIdentities.insert(
            registrationPublication.wrapperEventIdentity
        )
        let openedRegistration = try Runtime
            .openTransportBootstrapAnonymousMailboxRegistration(
                from: registrationPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                conductorControlSigningKey: conductorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedRegistration.document == registration)

        let registrationSetPublication = try Runtime
            .sealTransportBootstrapAnonymousMailboxRegistrationSet(
                fixture.registrationSet,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                conductorAssignments: conductorAssignments,
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                recipientControlIdentity: contributor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_203),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        reservedEventIdentities.insert(
            registrationSetPublication.wrapperEventIdentity
        )
        #expect(throws: Runtime.TransportBootstrapFailure.invalidRecipient) {
            try Runtime.openTransportBootstrapAnonymousMailboxRegistrationSet(
                from: registrationSetPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                localAnonymousMailboxAssignment: nil,
                recipientControlSigningKey: contributorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        }
        let openedRegistrationSet = try Runtime
            .openTransportBootstrapAnonymousMailboxRegistrationSet(
                from: registrationSetPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                localAnonymousMailboxAssignment: assignment,
                recipientControlSigningKey: contributorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedRegistrationSet.document == fixture.registrationSet)
        #expect(throws: Runtime.TransportBootstrapFailure
            .invalidRegistrationSet) {
            try Runtime.sealTransportBootstrapAnonymousMailboxRegistrationSet(
                fixture.registrationSet,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                conductorAssignments: Array(
                    conductorAssignments.dropLast()
                ),
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                recipientControlIdentity: contributor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_204),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        }

        let acknowledgement = try #require(
            fixture.acknowledgementSet.acknowledgements.first(where: {
                $0.controlIdentity == contributor
            })
        )
        let acknowledgementPublication = try Runtime
            .sealTransportBootstrapRegistrationSetAcknowledgement(
                acknowledgement,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registrationSet: fixture.registrationSet,
                localAnonymousMailboxAssignment: assignment,
                binding: fixture.binding,
                senderControlSigningKey: contributorKey,
                conductorControlIdentity: conductor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_205),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        reservedEventIdentities.insert(
            acknowledgementPublication.wrapperEventIdentity
        )
        let openedAcknowledgement = try Runtime
            .openTransportBootstrapRegistrationSetAcknowledgement(
                from: acknowledgementPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registrationSet: fixture.registrationSet,
                conductorAssignments: conductorAssignments,
                conductorControlSigningKey: conductorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(openedAcknowledgement.document == acknowledgement)

        let acknowledgementSetPublication = try Runtime
            .sealTransportBootstrapRegistrationSetAcknowledgementSet(
                fixture.acknowledgementSet,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registrationSet: fixture.registrationSet,
                conductorAssignments: conductorAssignments,
                binding: fixture.binding,
                conductorControlSigningKey: conductorKey,
                recipientControlIdentity: contributor,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_206),
                reservedEventIdentities: reservedEventIdentities,
                timestamps: fixture.timestamps
            )
        let openedAcknowledgementSet = try Runtime
            .openTransportBootstrapRegistrationSetAcknowledgementSet(
                from: acknowledgementSetPublication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                claimSet: fixture.claimSet,
                responseSet: fixture.responseSet,
                registrationSet: fixture.registrationSet,
                localAnonymousMailboxAssignment: assignment,
                recipientControlSigningKey: contributorKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(
            openedAcknowledgementSet.document
                == fixture.acknowledgementSet
        )
    }

    @Test("Seal, open, and publish one byte-identical bootstrap wrapper")
    func sealOpenAndPublish() async throws {
        let fixture = try Self.makeFixture()
        let sender = try #require(fixture.proof.controlIdentities.first)
        let recipient = try #require(
            fixture.proof.controlIdentities.first(where: { $0 != sender })
        )
        let senderKey = try fixture.controlSigningKey(for: sender)
        let recipientKey = try fixture.controlSigningKey(for: recipient)
        let claim = try #require(fixture.claimSet.claims.first(where: {
            $0.controlIdentity == sender
        }))
        let publication = try Runtime
            .sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_000),
                reservedEventIdentities: [],
                timestamps: fixture.timestamps
            )
        let restored = try Runtime.restoreTransportBootstrapPublication(
            canonicalEventBytes: publication.canonicalEventBytes,
            canonicalDocument: claim.canonicalDocument,
            senderEventIdentity: sender,
            recipientEventIdentity: recipient,
            proof: fixture.proof,
            binding: fixture.binding,
            expectedOperationIdentifier: publication.operationIdentifier,
            currentUnixSeconds: fixture.currentUnixSeconds
        )
        #expect(restored == publication)
        #expect(throws: Runtime.TransportBootstrapFailure.invalidBinding) {
            try Runtime.restoreTransportBootstrapPublication(
                canonicalEventBytes: publication.canonicalEventBytes,
                canonicalDocument: claim.canonicalDocument,
                senderEventIdentity: sender,
                recipientEventIdentity: recipient,
                proof: fixture.proof,
                binding: fixture.binding,
                expectedOperationIdentifier: Data(
                    repeating: 0xFF,
                    count: 32
                ),
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        }
        #expect(throws: Runtime.TransportBootstrapFailure
            .wrapperIdentityReuse) {
            try Runtime.sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_000),
                reservedEventIdentities: [
                    publication.wrapperEventIdentity,
                ],
                timestamps: fixture.timestamps
            )
        }
        let unrelatedControlIdentity = try #require(
            fixture.proof.controlIdentities.first(where: {
                $0 != sender && $0 != recipient
            })
        )
        #expect(throws: Runtime.TransportBootstrapFailure
            .wrapperIdentityReuse) {
            try Runtime.sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try fixture.controlSigningKey(
                    for: unrelatedControlIdentity
                ),
                reservedEventIdentities: [],
                timestamps: fixture.timestamps
            )
        }
        #expect(throws: Runtime.TransportBootstrapFailure
            .wrapperIdentityReuse) {
            try Runtime.sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try #require(
                    fixture.controlRecipientKeys[sender]
                ),
                reservedEventIdentities: [],
                timestamps: fixture.timestamps
            )
        }
        let opened = try Runtime
            .openTransportBootstrapControlMailboxClaim(
                from: publication.canonicalEventBytes,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                recipientControlSigningKey: recipientKey,
                currentUnixSeconds: fixture.currentUnixSeconds
            )
        #expect(opened.document == claim)
        #expect(opened.senderEventIdentity == sender)
        #expect(opened.recipientEventIdentity == recipient)
        #expect(opened.wrapperEventIdentity == publication.wrapperEventIdentity)

        let endpoints = fixture.proof.relayEndpointIdentifiers
        let initialConnections = [true, false, false].map {
            ScriptedMosaicPrivateAlphaTorConnection(
                eventAcceptance: $0
            )
        }
        let initialRoutes = zip(endpoints, initialConnections).map {
            endpoint,
            connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let persistence = TransportBootstrapAcceptanceStore()
        await #expect(throws: Runtime.TransportBootstrapFailure
            .publicationRejected) {
            try await publication.publish(
                using: .init(
                    relays: .init(
                        provisionRoutes: { request in
                            #expect(request.purpose == .outbound)
                            #expect(
                                request.recipientEventIdentity
                                    == recipient
                            )
                            #expect(
                                request.relayEndpointIdentifiers
                                    == endpoints
                            )
                            return initialRoutes
                        },
                        makeSubscriptionIdentifier: { _, _ in "unused" }
                    ),
                    loadAcceptedRelayEndpointIdentifiers: { identifier in
                        await persistence.load(identifier)
                    },
                    recordAcceptedRelayEndpointIdentifier: {
                        identifier,
                        endpoint in
                        await persistence.record(identifier, endpoint)
                    }
                )
            )
        }
        #expect(
            await persistence.load(publication.operationIdentifier)
                == [endpoints[0]]
        )

        let retryEndpoints = Array(endpoints.dropFirst())
        let retryConnections = [true, false].map {
            ScriptedMosaicPrivateAlphaTorConnection(
                eventAcceptance: $0
            )
        }
        let retryRoutes = zip(retryEndpoints, retryConnections).map {
            endpoint,
            connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let receipt = try await publication.publish(
            using: .init(
                relays: .init(
                    provisionRoutes: { request in
                        #expect(
                            request.relayEndpointIdentifiers
                                == retryEndpoints
                        )
                        return retryRoutes
                    },
                    makeSubscriptionIdentifier: { _, _ in "unused" }
                ),
                loadAcceptedRelayEndpointIdentifiers: { identifier in
                    await persistence.load(identifier)
                },
                recordAcceptedRelayEndpointIdentifier: {
                    identifier,
                    endpoint in
                    await persistence.record(identifier, endpoint)
                }
            )
        )
        #expect(receipt.operationIdentifier == publication.operationIdentifier)
        #expect(
            receipt.acceptedRelayEndpointIdentifiers
                == Array(endpoints.prefix(2)).sorted()
        )
        for connection in initialConnections + retryConnections {
            #expect(await connection.openCount == 1)
            #expect(await connection.closeCount == 1)
            #expect(await connection.sentTexts.count == 1)
        }

        let recovered = try await publication.publish(
            using: .init(
                relays: .init(
                    provisionRoutes: { _ in
                        Issue.record("Durable quorum must not open routes.")
                        return []
                    },
                    makeSubscriptionIdentifier: { _, _ in "unused" }
                ),
                loadAcceptedRelayEndpointIdentifiers: { identifier in
                    await persistence.load(identifier)
                },
                recordAcceptedRelayEndpointIdentifier: {
                    identifier,
                    endpoint in
                    await persistence.record(identifier, endpoint)
                }
            )
        )
        #expect(recovered == receipt)

        let cancelledPublication = try Runtime
            .sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_001),
                reservedEventIdentities: [publication.wrapperEventIdentity],
                timestamps: fixture.timestamps
            )
        let cancelledConnections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection(
                eventAcceptance: nil
            )
        }
        let cancelledRoutes = zip(endpoints, cancelledConnections).map {
            endpoint,
            connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let cancelledPersistence = TransportBootstrapAcceptanceStore()
        let pendingPublication = Task {
            try await cancelledPublication.publish(
                using: .init(
                    relays: .init(
                        provisionRoutes: { _ in cancelledRoutes },
                        makeSubscriptionIdentifier: { _, _ in "unused" }
                    ),
                    loadAcceptedRelayEndpointIdentifiers: { identifier in
                        await cancelledPersistence.load(identifier)
                    },
                    recordAcceptedRelayEndpointIdentifier: {
                        identifier,
                        endpoint in
                        await cancelledPersistence.record(
                            identifier,
                            endpoint
                        )
                    }
                )
            )
        }
        var sentOnEveryRoute = false
        for _ in 0 ..< 1_000 {
            var currentRouteSetIsComplete = true
            for connection in cancelledConnections {
                if await connection.sentTexts.count != 1 {
                    currentRouteSetIsComplete = false
                }
            }
            if currentRouteSetIsComplete {
                sentOnEveryRoute = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(sentOnEveryRoute)
        pendingPublication.cancel()
        await #expect(throws: Runtime.TransportBootstrapFailure.cancelled) {
            try await pendingPublication.value
        }
        #expect(
            await cancelledPersistence.load(
                cancelledPublication.operationIdentifier
            ).isEmpty
        )
        for connection in cancelledConnections {
            #expect(await connection.openCount == 1)
            #expect(await connection.closeCount == 1)
            #expect(await connection.sentTexts.count == 1)
        }

        let provisioningCancelledPublication = try Runtime
            .sealTransportBootstrapControlMailboxClaim(
                claim,
                proof: fixture.proof,
                authorizationKey: fixture.authorizationKey,
                binding: fixture.binding,
                senderControlSigningKey: senderKey,
                recipientControlIdentity: recipient,
                wrapperSigningKey: try Self.makeSigningKey(seed: 8_002),
                reservedEventIdentities: [
                    publication.wrapperEventIdentity,
                    cancelledPublication.wrapperEventIdentity,
                ],
                timestamps: fixture.timestamps
            )
        let provisioningCancelledConnections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection()
        }
        let provisioningCancelledRoutes = zip(
            endpoints,
            provisioningCancelledConnections
        ).map { endpoint, connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let provisioningSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await provisioningSuspension.arm()
        let provisioningTask = Task {
            try await provisioningCancelledPublication.publish(
                using: .init(
                    relays: .init(
                        provisionRoutes: { _ in
                            await provisioningSuspension.suspendIfArmed()
                            return provisioningCancelledRoutes
                        },
                        makeSubscriptionIdentifier: { _, _ in "unused" }
                    ),
                    loadAcceptedRelayEndpointIdentifiers: { _ in [] },
                    recordAcceptedRelayEndpointIdentifier: { _, _ in }
                )
            )
        }
        await provisioningSuspension.waitUntilSuspended()
        provisioningTask.cancel()
        await #expect(throws: Runtime.TransportBootstrapFailure.cancelled) {
            try await provisioningTask.value
        }
        for connection in provisioningCancelledConnections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
            #expect(await connection.sentTexts.isEmpty)
        }
    }

    @Test("Fan in relay copies once and fail closed on source loss")
    func fanInAndSourceLoss() async throws {
        let fixture = try Self.makeFixture()
        let recipient = try #require(
            fixture.proof.controlIdentities.first
        )
        let canonicalEventBytes = try Self.makeRelayEvent(
            recipientEventIdentity: recipient,
            wrapperSeed: 8_100,
            content: "first"
        )
        let firstEvent = try OpalFusion.Mosaic.NostrNamespace.EventCodec
            .decode(
                canonicalEventBytes,
                limits: Runtime.transportBootstrapCodingLimits().event
            )
        let endpoints = fixture.proof.relayEndpointIdentifiers
        let provisioningCancelledConnections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection()
        }
        let provisioningCancelledRoutes = zip(
            endpoints,
            provisioningCancelledConnections
        ).map { endpoint, connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let provisioningSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await provisioningSuspension.arm()
        let provisioningCancelledInbox = try Runtime
            .TransportBootstrapInbox(
                proof: fixture.proof,
                binding: fixture.binding,
                recipientEventIdentity: recipient,
                capabilities: .init(
                    provisionRoutes: { _ in
                        await provisioningSuspension.suspendIfArmed()
                        return provisioningCancelledRoutes
                    },
                    makeSubscriptionIdentifier: { _, _ in "unused" }
                )
            )
        let startTask = Task {
            try await provisioningCancelledInbox.start()
        }
        await provisioningSuspension.waitUntilSuspended()
        startTask.cancel()
        await #expect(throws: Runtime.TransportBootstrapFailure.cancelled) {
            try await startTask.value
        }
        await provisioningCancelledInbox.waitForTermination()
        for connection in provisioningCancelledConnections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
            #expect(await connection.sentTexts.isEmpty)
        }

        let rejectedConnections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection()
        }
        let sharedIsolationIdentifier = UUID()
        let rejectedRoutes = zip(endpoints, rejectedConnections).map {
            endpoint,
            connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: sharedIsolationIdentifier
            )
        }
        let rejectedInbox = try Runtime.TransportBootstrapInbox(
            proof: fixture.proof,
            binding: fixture.binding,
            recipientEventIdentity: recipient,
            capabilities: .init(
                provisionRoutes: { _ in rejectedRoutes },
                makeSubscriptionIdentifier: { _, _ in "unused" }
            )
        )
        await #expect(throws: Runtime.TransportBootstrapFailure
            .invalidRelayAllocation) {
            _ = try await rejectedInbox.start()
        }
        await rejectedInbox.waitForTermination()
        for connection in rejectedConnections {
            #expect(await connection.closeCount == 1)
        }

        let connections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection()
        }
        let routes = zip(endpoints, connections).map { endpoint, connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let inbox = try Runtime.TransportBootstrapInbox(
            proof: fixture.proof,
            binding: fixture.binding,
            recipientEventIdentity: recipient,
            capabilities: .init(
                provisionRoutes: { request in
                    #expect(request.purpose == .inbound)
                    return routes
                },
                makeSubscriptionIdentifier: { _, endpoint in
                    "bootstrap-\(try #require(endpoints.firstIndex(of: endpoint)))"
                },
                maximumPendingEventCount: 8
            )
        )
        let stream = try await inbox.start()
        for (index, connection) in connections.enumerated() {
            let eventJSON = String(
                decoding: canonicalEventBytes,
                as: UTF8.self
            )
            let frame = Data(
                "[\"EVENT\",\"bootstrap-\(index)\",\(eventJSON)]".utf8
            )
            await connection.receive(.text(frame))
        }

        var iterator = stream.makeAsyncIterator()
        let received = try await iterator.next()
        #expect(received?.canonicalEventBytes == canonicalEventBytes)
        #expect(received?.replayEntry.messageIdentifier
            == firstEvent.identifier.rawRepresentation)
        let replayEntry = try #require(received?.replayEntry)

        await connections[0].close()
        await #expect(throws: Runtime.TransportBootstrapFailure.sourceLost) {
            while try await iterator.next() != nil {}
        }
        await inbox.waitForTermination()
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }

        #expect(throws: Runtime.TransportBootstrapFailure
            .wrapperIdentityReuse) {
            try Runtime.TransportBootstrapInbox(
                proof: fixture.proof,
                binding: fixture.binding,
                recipientEventIdentity: recipient,
                capabilities: .init(
                    provisionRoutes: { _ in [] },
                    makeSubscriptionIdentifier: { _, _ in "unused" }
                ),
                replayEntries: [
                    replayEntry,
                    .init(
                        wrapperEventIdentity:
                            replayEntry.wrapperEventIdentity,
                        messageIdentifier: Data(
                            repeating: 0xEE,
                            count: 32
                        )
                    ),
                ]
            )
        }

        let reconnectConnections = (0 ..< 3).map { _ in
            ScriptedMosaicPrivateAlphaTorConnection()
        }
        let reconnectRoutes = zip(endpoints, reconnectConnections).map {
            endpoint,
            connection in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: connection,
                isolationIdentifier: UUID()
            )
        }
        let reconnectInbox = try Runtime.TransportBootstrapInbox(
            proof: fixture.proof,
            binding: fixture.binding,
            recipientEventIdentity: recipient,
            capabilities: .init(
                provisionRoutes: { _ in reconnectRoutes },
                makeSubscriptionIdentifier: { _, endpoint in
                    guard let index = endpoints.firstIndex(of: endpoint) else {
                        throw Runtime.TransportBootstrapFailure
                            .invalidRelayAllocation
                    }
                    return "reconnect-\(index)"
                },
                maximumPendingEventCount: 8
            ),
            replayEntries: [replayEntry]
        )
        let reconnectStream = try await reconnectInbox.start()
        let duplicateFrame = String(
            decoding: canonicalEventBytes,
            as: UTF8.self
        )
        await reconnectConnections[0].receive(.text(Data(
            "[\"EVENT\",\"reconnect-0\",\(duplicateFrame)]".utf8
        )))
        let freshEventBytes = try Self.makeRelayEvent(
            recipientEventIdentity: recipient,
            wrapperSeed: 8_101,
            content: "fresh"
        )
        let freshFrame = String(decoding: freshEventBytes, as: UTF8.self)
        await reconnectConnections[1].receive(.text(Data(
            "[\"EVENT\",\"reconnect-1\",\(freshFrame)]".utf8
        )))
        var reconnectIterator = reconnectStream.makeAsyncIterator()
        #expect(
            try await reconnectIterator.next()?.canonicalEventBytes
                == freshEventBytes
        )
        await reconnectConnections[2].close()
        await #expect(throws: Runtime.TransportBootstrapFailure.sourceLost) {
            while try await reconnectIterator.next() != nil {}
        }
        await reconnectInbox.waitForTermination()
        for connection in reconnectConnections {
            #expect(await connection.closeCount == 1)
        }
    }

    private struct Fixture {
        let proof: Runtime.PrivateDeploymentProof
        let formation: MosaicPrivateDeploymentFixtures.Formation
        let binding: Runtime.Binding
        let authorizationKey:
            Runtime.TransportBootstrapAuthorizationKeyDocument
        let controlRecipientKeys:
            [Data: OpalCrypto.Secp256k1.SigningKey]
        let controlRecipientPrivateKeys:
            [Data: OpalCrypto.Secp256k1.PrivateKey]
        let claimSet: Runtime.TransportBootstrapControlMailboxClaimSet
        let responseSet: Runtime.TransportBootstrapBlindResponseSet
        let anonymousSenderKeys:
            [Data: OpalCrypto.Secp256k1.SigningKey]
        let anonymousSenderPrivateKeys:
            [Data: OpalCrypto.Secp256k1.PrivateKey]
        let requests:
            [Data: Runtime.TransportBootstrapAnonymousMailboxRequest]
        let registrations:
            [Data: Runtime.TransportBootstrapAnonymousMailboxRegistration]
        let conductorAssignments:
            [Data: Runtime.TransportBootstrapConductorMailboxAssignment]
        let registrationSet:
            Runtime.TransportBootstrapAnonymousMailboxRegistrationSet
        let acknowledgementSet:
            Runtime.TransportBootstrapRegistrationSetAcknowledgementSet
        let currentUnixSeconds: UInt64
        let timestamps: Runtime.TransportBootstrapLayerTimestamps

        func controlSigningKey(
            for identity: Data
        ) throws -> OpalCrypto.Secp256k1.SigningKey {
            let controlIdentity = Attempt.ControlIdentity(
                validatedBytes: Array(identity)
            )
            return formation.controlCandidate(for: controlIdentity).signingKey
        }
    }

    private static let cachedFixture = Result {
        try makeFixtureValue()
    }

    private static func makeFixture() throws -> Fixture {
        try cachedFixture.get()
    }

    private static func makeFixtureValue() throws -> Fixture {
        let runtimeFixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let proof = runtimeFixture.proof
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(repeating: 0xD1, count: 32),
            generationIdentifier: Data(repeating: 0xD2, count: 32),
            materialIdentifier: Data(repeating: 0xD3, count: 32)
        )
        let current = proof.phaseStartUnixSeconds + 1
        let timestamps = Runtime.TransportBootstrapLayerTimestamps(
            currentUnixSeconds: current,
            rumorCreatedAt: current,
            sealCreatedAt: proof.phaseStartUnixSeconds,
            giftWrapCreatedAt: proof.phaseStartUnixSeconds
        )
        let conductorIdentity = Attempt.ControlIdentity(
            validatedBytes: Array(proof.conductorControlIdentity)
        )
        let conductorKey = runtimeFixture.formation
            .controlCandidate(for: conductorIdentity).signingKey
        let authorizationSigningKey = try RFC9500RSATestKeyFixture
            .makeSigningKey()
        let authorizationKey = try Runtime
            .makeTransportBootstrapAuthorizationKeyDocument(
                proof: proof,
                authorizationSigningKey: authorizationSigningKey,
                conductorControlSigningKey: conductorKey,
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0x31, count: 32)
                )
            )

        var requests: [
            Data: Runtime.TransportBootstrapAnonymousMailboxRequest
        ] = [:]
        var anonymousSenderKeys: [
            Data: OpalCrypto.Secp256k1.SigningKey
        ] = [:]
        var anonymousSenderPrivateKeys: [
            Data: OpalCrypto.Secp256k1.PrivateKey
        ] = [:]
        for (index, contributor) in proof
            .contributorControlIdentities.enumerated() {
            let senderPrivateKey = try makePrivateKey(seed: 1_500 + index)
            let senderKey = senderPrivateKey.makeSigningKey()
            anonymousSenderKeys[contributor] = senderKey
            anonymousSenderPrivateKeys[contributor] = senderPrivateKey
            requests[contributor] = try Runtime
                .makeTransportBootstrapAnonymousMailboxRequest(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    authorizationNonce: Data(
                        repeating: UInt8(0x80 + index),
                        count: 32
                    ),
                    anonymousSenderPrivateKey: senderPrivateKey
                )
        }

        var recipientKeys: [Data: OpalCrypto.Secp256k1.SigningKey] = [:]
        var recipientPrivateKeys: [
            Data: OpalCrypto.Secp256k1.PrivateKey
        ] = [:]
        var claims: [Runtime.TransportBootstrapControlMailboxClaim] = []
        for (index, identity) in proof.controlIdentities.enumerated() {
            let recipientPrivateKey = try makePrivateKey(
                seed: 1_000 + index
            )
            let recipient = recipientPrivateKey.makeSigningKey()
            recipientKeys[identity] = recipient
            recipientPrivateKeys[identity] = recipientPrivateKey
            let controlIdentity = Attempt.ControlIdentity(
                validatedBytes: Array(identity)
            )
            let controlKey = runtimeFixture.formation
                .controlCandidate(for: controlIdentity).signingKey
            claims.append(
                try Runtime.makeTransportBootstrapControlMailboxClaim(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    controlSigningKey: controlKey,
                    recipientEventVerificationKey:
                        recipient.bip340VerificationKey,
                    anonymousMailboxRequest: requests[identity],
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating: UInt8(0x40 + index),
                            count: 32
                        )
                    )
                )
            )
        }
        let claimSet = try Runtime
            .makeTransportBootstrapControlMailboxClaimSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claims: claims
            )
        let responseSet = try Runtime.makeTransportBootstrapBlindResponseSet(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            authorizationSigningKey: authorizationSigningKey,
            conductorControlSigningKey: conductorKey,
            auxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0x61, count: 32)
            )
        )

        var registrations: [
            Data: Runtime.TransportBootstrapAnonymousMailboxRegistration
        ] = [:]
        var conductorAssignments: [
            Data: Runtime.TransportBootstrapConductorMailboxAssignment
        ] = [:]
        for (contributorIndex, contributor) in proof
            .contributorControlIdentities.enumerated() {
            let request = try #require(requests[contributor])
            let senderKey = try #require(
                anonymousSenderKeys[contributor]
            )
            let registration = try Runtime
                .makeTransportBootstrapAnonymousMailboxRegistration(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    contributorControlIdentity: contributor,
                    request: request,
                    anonymousSenderSigningKey: senderKey,
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating:
                                UInt8(0x70 + contributorIndex),
                            count: 32
                        )
                    )
                )
            registrations[contributor] = registration
            let keys = try (0 ..< 23).map { slot in
                try makePrivateKey(
                    seed: 2_000 + contributorIndex * 23 + slot
                )
            }
            conductorAssignments[contributor] = try Runtime
                .makeTransportBootstrapAnonymousMailboxAssignment(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    registration: registration,
                    recipientPrivateKeys: keys,
                    conductorControlSigningKey: conductorKey,
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating:
                                UInt8(0xA0 + contributorIndex),
                            count: 32
                        )
                    ),
                    currentUnixSeconds: current
                )
        }
        let orderedRegistrations = try proof
            .contributorControlIdentities.map {
                try #require(registrations[$0])
            }
        let orderedAssignments = try proof
            .contributorControlIdentities.map {
                try #require(conductorAssignments[$0])
            }
        let registrationSet = try Runtime
            .makeTransportBootstrapAnonymousMailboxRegistrationSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registrations: orderedRegistrations,
                conductorAssignments: orderedAssignments,
                conductorControlSigningKey: conductorKey,
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0xB0, count: 32)
                ),
                currentUnixSeconds: current
            )
        var acknowledgements: [
            Runtime.TransportBootstrapRegistrationSetAcknowledgement
        ] = []
        for (index, identity) in proof.controlIdentities.enumerated() {
            acknowledgements.append(
                try Runtime
                    .makeTransportBootstrapRegistrationSetAcknowledgement(
                        proof: proof,
                        authorizationKey: authorizationKey,
                        claimSet: claimSet,
                        responseSet: responseSet,
                        registrationSet: registrationSet,
                        controlSigningKey: runtimeFixture.formation
                            .controlCandidate(for: .init(
                                validatedBytes: Array(identity)
                            )).signingKey,
                        localAnonymousMailboxAssignment:
                            conductorAssignments[identity]?.assignment,
                        auxiliaryRandomness: try .init(
                            rawRepresentation: Data(
                                repeating: UInt8(0xC0 + index),
                                count: 32
                            )
                        ),
                        currentUnixSeconds: current
                    )
            )
        }
        let acknowledgementSet = try Runtime
            .makeTransportBootstrapRegistrationSetAcknowledgementSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registrationSet: registrationSet,
                acknowledgements: acknowledgements,
                currentUnixSeconds: current
            )
        return .init(
            proof: proof,
            formation: runtimeFixture.formation,
            binding: binding,
            authorizationKey: authorizationKey,
            controlRecipientKeys: recipientKeys,
            controlRecipientPrivateKeys: recipientPrivateKeys,
            claimSet: claimSet,
            responseSet: responseSet,
            anonymousSenderKeys: anonymousSenderKeys,
            anonymousSenderPrivateKeys: anonymousSenderPrivateKeys,
            requests: requests,
            registrations: registrations,
            conductorAssignments: conductorAssignments,
            registrationSet: registrationSet,
            acknowledgementSet: acknowledgementSet,
            currentUnixSeconds: current,
            timestamps: timestamps
        )
    }

    private static func makePrivateKey(
        seed: Int
    ) throws -> OpalCrypto.Secp256k1.PrivateKey {
        guard (1 ... Int(UInt32.max)).contains(seed) else {
            throw Runtime.TransportBootstrapFailure.invalidSigner
        }
        let scalar = UInt32(seed)
        return try .init(
            rawRepresentation: Data(repeating: 0, count: 28) + Data([
                UInt8(truncatingIfNeeded: scalar >> 24),
                UInt8(truncatingIfNeeded: scalar >> 16),
                UInt8(truncatingIfNeeded: scalar >> 8),
                UInt8(truncatingIfNeeded: scalar),
            ])
        )
    }

    private static func makeSigningKey(
        seed: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try makePrivateKey(seed: seed).makeSigningKey()
    }

    private static func makeRelayEvent(
        recipientEventIdentity: Data,
        wrapperSeed: Int,
        content: String
    ) throws -> Data {
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        let limits = try Runtime.transportBootstrapCodingLimits()
        let signingKey = try makeSigningKey(seed: wrapperSeed)
        let template = try Nostr.EventTemplate(
            createdAt: 1_800_000_000,
            kind: Nostr.NIP59EnvelopeCodec.DeliveryKind.regular.rawValue,
            tags: [[
                "p",
                Nostr.EventCodec.hexadecimal(
                    recipientEventIdentity
                ),
            ]],
            content: content,
            limits: limits.event
        )
        let event = try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(
                    repeating: UInt8(truncatingIfNeeded: wrapperSeed),
                    count: 32
                )
            ),
            limits: limits.event
        )
        return try Nostr.EventCodec.encode(event, limits: limits.event)
    }

}

private actor TransportBootstrapAcceptanceStore {
    private var endpointsByOperation: [Data: Set<String>] = [:]

    func load(_ operationIdentifier: Data) -> [String] {
        Array(endpointsByOperation[operationIdentifier, default: []])
            .sorted()
    }

    func record(
        _ operationIdentifier: Data,
        _ endpoint: String
    ) {
        endpointsByOperation[operationIdentifier, default: []]
            .insert(endpoint)
    }
}
