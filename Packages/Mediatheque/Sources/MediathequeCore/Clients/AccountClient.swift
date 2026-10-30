import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Demande de réservation : le formulaire de retrait à soumettre et les lieux proposés.
public struct HoldRequest: Hashable, Sendable {
    public let recordID: Int
    public let pickupPath: String
    public let pickupLibraries: [Library]
    public let defaultPickup: Library?

    public init(recordID: Int, pickupPath: String, pickupLibraries: [Library], defaultPickup: Library?) {
        self.recordID = recordID
        self.pickupPath = pickupPath
        self.pickupLibraries = pickupLibraries
        self.defaultPickup = defaultPickup
    }
}

public enum HoldError: Error, Equatable, Sendable {
    case notHoldable
    case refused(message: String)
}

/// Compte abonné. Tous les appels passent par `SessionManager.perform`,
/// qui rouvre la session si elle a expiré.
@DependencyClient
public struct AccountClient: Sendable {
    public var patron: @Sendable () async throws -> Patron
    public var loans: @Sendable () async throws -> [Loan]
    public var holds: @Sendable () async throws -> [Hold]
    /// Le site ne dit pas si un prêt est prolongeable : on tente, puis on compare les dates.
    public var renew: @Sendable (_ loanIDs: [Loan.ID]) async throws -> [RenewalResult]
    public var cancelHold: @Sendable (_ holdID: Hold.ID) async throws -> Void
    public var prepareHold: @Sendable (_ recordID: Int) async throws -> HoldRequest
    /// Renvoie le message de confirmation du site.
    public var placeHold: @Sendable (_ request: HoldRequest, _ pickup: Library) async throws -> String
}

extension AccountClient: DependencyKey {
    public static var liveValue: AccountClient {
        @Dependency(\.httpClient) var http
        @Dependency(\.sessionManager) var session

        @Sendable func fetchLoans() async throws -> [Loan] {
            try await session.perform {
                try await http.decode(LoansResponseDTO.self, from: .loans).loans.compactMap(Loan.init(dto:))
            }
        }

        return AccountClient(
            patron: {
                try await session.perform {
                    Patron(dto: try await http.decode(AccountResponseDTO.self, from: .account).account)
                }
            },
            loans: fetchLoans,
            holds: {
                try await session.perform {
                    let dtos = try await http.decode(HoldsResponseDTO.self, from: .holds).holds
                    guard let patronID = dtos.first?.id.split(separator: "_").first else { return [] }
                    // Le rang n'existe que dans le HTML ; on s'en passe s'il ne se lit pas.
                    let ranks = (try? HTMLParsers.holdRanks(in: await http.string(for: .holdsPage(patronID: String(patronID))))) ?? []
                    return dtos.enumerated().map { index, dto in
                        Hold(dto: dto, rank: ranks.indices.contains(index) ? ranks[index] : nil)
                    }
                }
            },
            renew: { loanIDs in
                guard let patronID = loanIDs.first?.split(separator: "_").first else { return [] }
                let before = Dictionary(uniqueKeysWithValues: try await fetchLoans().map { ($0.id, $0.dueDate) })
                _ = try await session.perform {
                    try await http.data(for: .renewLoans(patronID: String(patronID), loanIDs: loanIDs))
                }
                let after = Dictionary(uniqueKeysWithValues: try await fetchLoans().map { ($0.id, $0.dueDate) })
                return loanIDs.map { id in
                    if let newDue = after[id], let oldDue = before[id], newDue > oldDue {
                        return .renewed(loanID: id, newDueDate: newDue)
                    }
                    return .refused(loanID: id)
                }
            },
            cancelHold: { holdID in
                _ = try await session.perform { try await http.data(for: .cancelHold(holdID: holdID)) }
            },
            prepareHold: { recordID in
                try await session.perform {
                    let options = try await http.decode(PopupDTO.self, from: .holdOptions(recordID: recordID))
                    let paths = try HTMLParsers.holdPickupPaths(in: options.content)
                    // Le lien « on_record » réserve la notice (premier exemplaire qui revient).
                    guard let path = paths.first(where: { $0.contains("on_record") }) ?? paths.first else {
                        throw HoldError.notHoldable
                    }
                    let form = try await http.decode(PopupDTO.self, from: .pickupForm(path: path))
                    let pickups = try HTMLParsers.pickupOptions(in: form.content)
                    return HoldRequest(
                        recordID: recordID,
                        pickupPath: path,
                        pickupLibraries: pickups.compactMap { Library(rawValue: $0.code) },
                        defaultPickup: pickups.first(where: \.isSelected).flatMap { Library(rawValue: $0.code) }
                    )
                }
            },
            placeHold: { request, pickup in
                try await session.perform {
                    let popup = try await http.decode(
                        PopupDTO.self,
                        from: .submitPickup(path: request.pickupPath, pickupLibraryCode: pickup.code)
                    )
                    let message = popup.content
                        .replacingOccurrences(of: "<br>", with: "\n")
                        .replacing(/<[^>]+>/, with: "")
                    guard message.localizedCaseInsensitiveContains("enregistrée") else {
                        throw HoldError.refused(message: message)
                    }
                    return message
                }
            }
        )
    }

    public static let previewValue = AccountClient(
        patron: { SampleData.patron },
        loans: { SampleData.loans },
        holds: { SampleData.holds },
        renew: { ids in ids.map { .renewed(loanID: $0, newDueDate: Date().addingTimeInterval(21 * 86_400)) } },
        cancelHold: { _ in },
        prepareHold: { recordID in
            HoldRequest(recordID: recordID, pickupPath: "preview", pickupLibraries: Library.allCases, defaultPickup: .pulpNord)
        },
        placeHold: { _, pickup in "Votre réservation est enregistrée.\nRetrait à \(pickup.shortName)." }
    )

    public static let testValue = AccountClient()
}

extension DependencyValues {
    public var accountClient: AccountClient {
        get { self[AccountClient.self] }
        set { self[AccountClient.self] = newValue }
    }
}
