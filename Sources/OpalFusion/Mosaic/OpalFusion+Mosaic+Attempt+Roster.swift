// OpalFusion+Mosaic+Attempt+Roster.swift

extension OpalFusion.Mosaic.Attempt {
    /// An opaque one-time control identity that an upstream cryptographic seam has validated.
    struct ControlIdentity: Sendable, Hashable {
        let validatedBytes: [UInt8]

        init(validatedBytes: [UInt8]) {
            self.validatedBytes = validatedBytes
        }
    }

    /// One candidate's role after role selection has completed.
    struct RosterMember: Sendable, Equatable {
        let controlIdentity: ControlIdentity
        let role: OpalFusion.Mosaic.Role

        init(
            controlIdentity: ControlIdentity,
            role: OpalFusion.Mosaic.Role
        ) {
            self.controlIdentity = controlIdentity
            self.role = role
        }
    }

    /// A role-selected roster for one Mosaic attempt.
    struct Roster: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidCandidateCount(actual: Int)
            case invalidRoleCounts(conductors: Int, contributors: Int)
            case duplicateControlIdentity(ControlIdentity)
        }

        let members: [RosterMember]
        let conductor: ControlIdentity
        let contributors: [ControlIdentity]

        init(members: [RosterMember]) throws {
            guard (7 ... 9).contains(members.count) else {
                throw ValidationError.invalidCandidateCount(actual: members.count)
            }

            var seenControlIdentities: Set<ControlIdentity> = []
            for member in members {
                guard seenControlIdentities.insert(member.controlIdentity).inserted else {
                    throw ValidationError.duplicateControlIdentity(member.controlIdentity)
                }
            }

            let conductors = members.filter { $0.role == .conductor }
            let contributors = members.filter { $0.role == .contributor }
            guard conductors.count == 1, (6 ... 8).contains(contributors.count) else {
                throw ValidationError.invalidRoleCounts(
                    conductors: conductors.count,
                    contributors: contributors.count
                )
            }

            self.members = members
            self.conductor = conductors[0].controlIdentity
            self.contributors = contributors.map(\.controlIdentity)
        }

        var candidateCount: Int {
            members.count
        }

        var controlIdentities: [ControlIdentity] {
            members.map(\.controlIdentity)
        }
    }
}
