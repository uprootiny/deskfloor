import SwiftUI

// Color properties extracted from model types so models don't need SwiftUI.

extension Status {
    var color: Color {
        switch self {
        case .active: Color(red: 0.3, green: 0.7, blue: 0.5)
        case .paused: Color(red: 0.85, green: 0.75, blue: 0.3)
        case .handoff: Color(red: 0.4, green: 0.6, blue: 0.9)
        case .archived: Color(red: 0.5, green: 0.5, blue: 0.5)
        case .idea: Color(red: 0.7, green: 0.5, blue: 0.8)
        }
    }
}

extension Perspective {
    var color: Color {
        switch self {
        case .infrastructure: Color(red: 0.3, green: 0.7, blue: 0.5)
        case .legal: Color(red: 0.85, green: 0.75, blue: 0.3)
        case .ml: Color(red: 0.3, green: 0.7, blue: 0.7)
        case .creative: Color(red: 0.7, green: 0.5, blue: 0.8)
        case .ops: Color(red: 0.4, green: 0.6, blue: 0.9)
        case .personal: Color(red: 0.6, green: 0.55, blue: 0.5)
        }
    }
}

extension EncumbranceKind {
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

extension SurfaceKind {
    var color: Color {
        switch self {
        case .terminal:   Color(red: 0.30, green: 0.72, blue: 0.50)
        case .tmux:       Color(red: 0.85, green: 0.72, blue: 0.30)
        case .port:       Color(red: 0.92, green: 0.55, blue: 0.25)
        case .claudeCode: Color(red: 0.55, green: 0.45, blue: 0.85)
        case .browserTab: Color(red: 0.40, green: 0.62, blue: 0.90)
        }
    }
}

extension AttentionItem.Severity {
    var color: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .live: .green
        case .completed: .blue
        case .paused: .yellow
        case .abandoned: .orange
        case .crashed: .red
        case .hypothetical: .purple
        case .archived: .gray
        }
    }
}

extension ThreadColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .amber: Color(red: 0.85, green: 0.75, blue: 0.3)
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
