import Foundation

enum EncumbranceKind: String, Codable, CaseIterable, Identifiable {
    case thirdPartyCode
    case credentials
    case privateData
    case intellectualProperty
    case dependency

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirdPartyCode: "3rd Party Code"
        case .credentials: "Credentials"
        case .privateData: "Private Data"
        case .intellectualProperty: "IP"
        case .dependency: "Dependency"
        }
    }
}

struct Encumbrance: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: EncumbranceKind
    var description: String
}

struct ProgressNote: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var note: String
}
