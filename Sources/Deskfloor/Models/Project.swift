import Foundation
import SwiftUI

enum Status: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case handoff
    case archived
    case idea

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .handoff: "Handoff"
        case .archived: "Archived"
        case .idea: "Idea"
        }
    }

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

enum Perspective: String, Codable, CaseIterable, Identifiable {
    case infrastructure
    case legal
    case ml
    case creative
    case ops
    case personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .infrastructure: "Infrastructure"
        case .legal: "Legal"
        case .ml: "ML"
        case .creative: "Creative"
        case .ops: "Ops"
        case .personal: "Personal"
        }
    }

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

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var repo: String?
    var localPath: String?
    var description: String
    var why: String
    var status: Status
    var perspective: Perspective
    var tags: [String]
    var startDate: Date?
    var lastActivity: Date?
    var commitCount: Int
    var encumbrances: [Encumbrance]
    var connections: [String]
    var progressNotes: [ProgressNote]
    var handoffReady: Bool
    var handoffNotes: String
    var lastCommitMessage: String?
    var lastCommitAuthor: String?
    var gitBranch: String?
    var dirtyFiles: Int?
    var projectType: String?

    static func blank() -> Project {
        Project(
            name: "",
            repo: nil,
            localPath: nil,
            description: "",
            why: "",
            status: .idea,
            perspective: .personal,
            tags: [],
            startDate: Date(),
            lastActivity: Date(),
            commitCount: 0,
            encumbrances: [],
            connections: [],
            progressNotes: [],
            handoffReady: false,
            handoffNotes: "",
            lastCommitMessage: nil,
            lastCommitAuthor: nil,
            gitBranch: nil,
            dirtyFiles: nil,
            projectType: nil
        )
    }
}
