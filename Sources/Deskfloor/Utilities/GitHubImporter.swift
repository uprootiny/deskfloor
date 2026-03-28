import Foundation

struct GitHubRepo: Decodable {
    let name: String
    let nameWithOwner: String
    let description: String?
    let createdAt: String?
    let updatedAt: String?
    let pushedAt: String?
    let isArchived: Bool
    let isFork: Bool
    let primaryLanguage: GitHubLanguage?

    struct GitHubLanguage: Decodable {
        let name: String
    }
}

enum GitHubImporter {
    static func importRepos(owner: String?) async throws -> [Project] {
        let process = Process()

        // Find gh — check common nix/homebrew/system paths
        let ghPaths = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nix-profile/bin/gh",
            "/nix/var/nix/profiles/default/bin/gh",
            "/usr/local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/bin/gh",
        ]
        let ghPath = ghPaths.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/env"

        if ghPath.hasSuffix("/env") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var args = ["gh", "repo", "list"]
            if let owner = owner { args.append(owner) }
            args += ["--json", "name,nameWithOwner,description,createdAt,updatedAt,pushedAt,isArchived,isFork,primaryLanguage", "--limit", "200"]
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: ghPath)
            var args = ["repo", "list"]
            if let owner = owner { args.append(owner) }
            args += ["--json", "name,nameWithOwner,description,createdAt,updatedAt,pushedAt,isArchived,isFork,primaryLanguage", "--limit", "200"]
            process.arguments = args
        }

        // Ensure PATH includes nix
        var env = ProcessInfo.processInfo.environment
        let nixBin = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nix-profile/bin"
        env["PATH"] = "\(nixBin):/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw ImportError.ghCommandFailed
        }

        let decoder = JSONDecoder()
        let repos = try decoder.decode([GitHubRepo].self, from: data)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String?) -> Date? {
            guard let s = s else { return nil }
            return isoFormatter.date(from: s) ?? isoFallback.date(from: s)
        }

        return repos.map { repo in
            let pushedDate = parseDate(repo.pushedAt)
            let daysSincePush = pushedDate.map { -$0.timeIntervalSinceNow / 86400 } ?? 999
            let status: Status
            if repo.isArchived {
                status = .archived
            } else if daysSincePush > 180 {
                status = .archived
            } else if daysSincePush > 90 {
                status = .paused
            } else {
                status = .active
            }
            let perspective = guessPerspective(name: repo.name, language: repo.primaryLanguage?.name, description: repo.description)

            var encumbrances: [Encumbrance] = []
            if repo.isFork {
                encumbrances.append(Encumbrance(kind: .thirdPartyCode, description: "Forked repository"))
            }

            return Project(
                name: repo.name,
                repo: repo.nameWithOwner,
                description: repo.description ?? "",
                why: "",
                status: status,
                perspective: perspective,
                tags: [repo.primaryLanguage?.name].compactMap { $0 },
                startDate: parseDate(repo.createdAt),
                lastActivity: parseDate(repo.pushedAt) ?? parseDate(repo.updatedAt),
                commitCount: 0,
                encumbrances: encumbrances,
                connections: [],
                progressNotes: [],
                handoffReady: false,
                handoffNotes: ""
            )
        }
    }

    private static func guessPerspective(name: String, language: String?, description: String?) -> Perspective {
        let n = name.lowercased()
        let d = (description ?? "").lowercased()
        let lang = (language ?? "").lowercased()

        // Infrastructure: servers, deploy, config, nix, docker
        if n.contains("infra") || n.contains("nix") || n.contains("docker") || n.contains("deploy")
            || n.contains("server") || n.contains("config") || n.contains("desk")
            || d.contains("infrastructure") || d.contains("server manifest")
            || d.contains("terraform") || d.contains("k8s") {
            return .infrastructure
        }
        // Legal: explicit legal/compliance
        if n.contains("legal") || d.contains("legal") || d.contains("compliance") {
            return .legal
        }
        // ML: only strong ML signals, not just "data" or "python"
        if n.contains("numerai") || n.contains("forecast") || n.contains("finml")
            || n.contains("pythia") || n.contains("ml-") || n.contains("-ml")
            || d.contains("machine learning") || d.contains("neural") || d.contains("training")
            || d.contains("model") && d.contains("pipeline") {
            return .ml
        }
        // Creative: art, music, visual, gallery
        if n.contains("art") || n.contains("music") || n.contains("gallery") || n.contains("synth")
            || n.contains("creative") || n.contains("design") || n.contains("visual")
            || n.contains("dissemblage") || n.contains("ceramic") || n.contains("bloom")
            || d.contains("art") || d.contains("creative") || d.contains("visualization") {
            return .creative
        }
        // Ops: monitoring, CI, agents, bots, orchestration
        if n.contains("ops") || n.contains("monitor") || n.contains("agent")
            || n.contains("orchestra") || n.contains("sentinel") || n.contains("bot")
            || n.contains("coggy") || n.contains("flux") || n.contains("grafana")
            || d.contains("monitoring") || d.contains("pipeline") || d.contains("scraping") {
            return .ops
        }
        return .personal
    }

    enum ImportError: Error, LocalizedError {
        case ghCommandFailed

        var errorDescription: String? {
            switch self {
            case .ghCommandFailed: "gh command failed. Make sure gh CLI is installed and authenticated."
            }
        }
    }
}
