import Foundation
import SwiftUI

enum SurfaceKind: String, CaseIterable, Codable {
    case terminal
    case tmux
    case port
    case claudeCode
    case browserTab

    var icon: String {
        switch self {
        case .terminal:   return "terminal"
        case .tmux:       return "rectangle.split.3x1"
        case .port:       return "network"
        case .claudeCode: return "brain.head.profile"
        case .browserTab: return "globe"
        }
    }

    var label: String {
        switch self {
        case .terminal:   return "Terminal"
        case .tmux:       return "Tmux"
        case .port:       return "Port"
        case .claudeCode: return "Claude Code"
        case .browserTab: return "Browser"
        }
    }

    var color: Color {
        switch self {
        case .terminal:   return Color(red: 0.30, green: 0.72, blue: 0.50)
        case .tmux:       return Color(red: 0.85, green: 0.72, blue: 0.30)
        case .port:       return Color(red: 0.92, green: 0.55, blue: 0.25)
        case .claudeCode: return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .browserTab: return Color(red: 0.40, green: 0.62, blue: 0.90)
        }
    }
}

struct Surface: Identifiable {
    let id: String
    let kind: SurfaceKind
    let label: String
    let detail: String
    var projectID: UUID?
    let pid: Int?
    let path: String?
}
