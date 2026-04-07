import Foundation

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
