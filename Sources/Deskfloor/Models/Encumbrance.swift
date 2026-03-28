import Foundation
import SwiftUI

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

    var dotColor: Color {
        switch self {
        case .credentials: Color(red: 0.9, green: 0.3, blue: 0.3)
        case .intellectualProperty: Color(red: 0.85, green: 0.75, blue: 0.3)
        case .thirdPartyCode: Color(red: 0.4, green: 0.6, blue: 0.9)
        case .privateData: Color(red: 0.8, green: 0.4, blue: 0.7)
        case .dependency: Color(red: 0.5, green: 0.5, blue: 0.5)
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
