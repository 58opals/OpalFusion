// OpalFusion+Mosaic+OpalV0+AnonymousComponentPayload.swift

extension OpalFusion.Mosaic.OpalV0 {
    /// One identity-free component submission bound to its attempt and authorization.
    struct AnonymousComponentPayload: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let authorizationToken: AuthorizationToken
        let component: Component

        init(
            roundIdentifier: [UInt8],
            authorizationToken: AuthorizationToken,
            component: Component
        ) throws {
            guard roundIdentifier.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard authorizationToken.input.roundIdentifier == roundIdentifier else {
                throw WireContractError.authorizationTokenRoundMismatch
            }
            self.roundIdentifier = Array(roundIdentifier)
            self.authorizationToken = authorizationToken
            self.component = component
        }
    }
}
