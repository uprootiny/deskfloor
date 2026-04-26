import Foundation

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

    // CI status — transient, populated by DataBus polling, not persisted
    var ciStatus: CIBadge?

    enum CIBadge: String, Codable {
        case green, red, yellow, pending, none
    }

    // Deployment — nil means not configured
    var deployHost: String?       // fleet host name, e.g. "hyle"
    var deployPath: String?       // remote path, e.g. "/opt/myapp"
    var deployCommand: String?    // e.g. "docker compose up -d"
    var deployURL: String?        // live URL, e.g. "https://myapp.example.com"
    var restartCommand: String?   // e.g. "systemctl restart myapp"; falls back to deployCommand
    var stopCommand: String?      // e.g. "docker compose down"
    var logPaths: [String]?       // explicit log paths to tail; falls back to *.log + journalctl
    var lastDeployAt: Date?       // set by the Deploy button; surfaces in status row

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
            projectType: nil,
            deployHost: nil,
            deployPath: nil,
            deployCommand: nil,
            deployURL: nil,
            restartCommand: nil,
            stopCommand: nil,
            logPaths: nil,
            lastDeployAt: nil
        )
    }
}
