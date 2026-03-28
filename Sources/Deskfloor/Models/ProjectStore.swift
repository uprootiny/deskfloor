import Foundation
import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case name, lastActivity, startDate, commitCount, status
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .lastActivity: "Recent"
        case .startDate: "Started"
        case .commitCount: "Commits"
        case .status: "Status"
        }
    }
}

@Observable
final class ProjectStore {
    var projects: [Project] = []
    var sortOrder: SortOrder = .lastActivity

    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".deskfloor", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("projects.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([Project].self, from: data)
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }

    func addProject(_ project: Project) {
        projects.append(project)
        save()
    }

    func updateProject(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            save()
        }
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func moveProject(id: UUID, toStatus status: Status) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].status = status
            projects[idx].lastActivity = Date()
            save()
        }
    }

    func moveProject(id: UUID, toPerspective perspective: Perspective) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].perspective = perspective
            projects[idx].lastActivity = Date()
            save()
        }
    }

    func projectsForStatus(_ status: Status) -> [Project] {
        projects.filter { $0.status == status }
    }

    func projectsForPerspective(_ perspective: Perspective) -> [Project] {
        projects.filter { $0.perspective == perspective }
    }

    func filtered(
        searchText: String,
        perspectives: Set<Perspective>,
        statuses: Set<Status>,
        encumbranceKinds: Set<EncumbranceKind>,
        handoffOnly: Bool,
        encumberedOnly: Bool
    ) -> [Project] {
        projects.filter { project in
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let match = project.name.lowercased().contains(query)
                    || project.description.lowercased().contains(query)
                    || project.why.lowercased().contains(query)
                    || (project.repo?.lowercased().contains(query) ?? false)
                    || project.tags.contains(where: { $0.lowercased().contains(query) })
                    || project.handoffNotes.lowercased().contains(query)
                if !match { return false }
            }
            if !perspectives.isEmpty && !perspectives.contains(project.perspective) {
                return false
            }
            if !statuses.isEmpty && !statuses.contains(project.status) {
                return false
            }
            if !encumbranceKinds.isEmpty {
                let projectKinds = Set(project.encumbrances.map(\.kind))
                if projectKinds.isDisjoint(with: encumbranceKinds) { return false }
            }
            if handoffOnly && !project.handoffReady { return false }
            if encumberedOnly && project.encumbrances.isEmpty { return false }
            return true
        }
        .sorted { a, b in
            switch sortOrder {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .lastActivity:
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            case .startDate:
                return (a.startDate ?? .distantPast) > (b.startDate ?? .distantPast)
            case .commitCount:
                return a.commitCount > b.commitCount
            case .status:
                return a.status.rawValue < b.status.rawValue
            }
        }
    }
}
