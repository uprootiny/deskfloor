import SwiftUI

struct ProjectTimelineView: View {
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    @State private var hoveredProject: UUID?
    @State private var pixelsPerDay: CGFloat = 3

    private let rowHeight: CGFloat = 28
    private let labelWidth: CGFloat = 180

    var body: some View {
        let sorted = filteredProjects
            .filter { $0.startDate != nil }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }

        if sorted.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.15))
                Text("No projects with date data")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let (earliest, latest) = dateRange(sorted)
            let totalDays = max(Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 1, 1)
            let totalWidth = labelWidth + CGFloat(totalDays) * pixelsPerDay

            VStack(spacing: 0) {
                // Zoom control
                HStack {
                    Text("Zoom")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    Slider(value: $pixelsPerDay, in: 0.5...12, step: 0.5)
                        .frame(width: 100)
                    Text("\(String(format: "%.0f", pixelsPerDay))px/day")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                    Text("\(sorted.count) projects")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Sticky header with months
                        timelineHeader(earliest: earliest, totalDays: totalDays)

                        // Today line + rows
                        ZStack(alignment: .topLeading) {
                            // Today vertical line
                            let todayOffset = Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0
                            if todayOffset >= 0 && todayOffset <= totalDays {
                                Rectangle()
                                    .fill(Color.red.opacity(0.25))
                                    .frame(width: 1)
                                    .offset(x: labelWidth + CGFloat(todayOffset) * pixelsPerDay)
                            }

                            // Rows
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(sorted) { project in
                                    timelineRow(project: project, earliest: earliest, totalDays: totalDays)
                                }
                            }
                        }
                    }
                    .frame(width: totalWidth)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Header

    private func timelineHeader(earliest: Date, totalDays: Int) -> some View {
        let totalWidth = CGFloat(totalDays) * pixelsPerDay

        return HStack(spacing: 0) {
            // Corner
            HStack {
                Text("PROJECT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
            }
            .frame(width: labelWidth)
            .padding(.horizontal, 8)

            ZStack(alignment: .leading) {
                Color.clear.frame(width: totalWidth, height: 24)

                let months = generateMonths(from: earliest, totalDays: totalDays)
                ForEach(months, id: \.offset) { month in
                    VStack(spacing: 0) {
                        Text(month.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 1, height: 8)
                    }
                    .offset(x: CGFloat(month.offset) * pixelsPerDay)
                }

                // Today label
                let todayOffset = Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0
                if todayOffset >= 0 && todayOffset <= totalDays {
                    Text("today")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.5))
                        .offset(x: CGFloat(todayOffset) * pixelsPerDay - 10)
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // MARK: - Row

    private func timelineRow(project: Project, earliest: Date, totalDays: Int) -> some View {
        let cal = Calendar.current
        let totalWidth = CGFloat(totalDays) * pixelsPerDay
        let isHovered = hoveredProject == project.id

        let startDay = cal.dateComponents([.day], from: earliest, to: project.startDate ?? earliest).day ?? 0
        let endDay: Int
        if let last = project.lastActivity {
            endDay = max(cal.dateComponents([.day], from: earliest, to: last).day ?? startDay, startDay + 1)
        } else {
            endDay = startDay + 1
        }

        let barStart = CGFloat(startDay) * pixelsPerDay
        let barWidth = max(CGFloat(endDay - startDay) * pixelsPerDay, 6)
        let daysActive = endDay - startDay

        return HStack(spacing: 0) {
            // Label column
            HStack(spacing: 6) {
                Circle()
                    .fill(project.perspective.color)
                    .frame(width: 6, height: 6)

                Text(project.name)
                    .font(.system(size: 10, weight: isHovered ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(isHovered ? 0.9 : 0.6))
                    .lineLimit(1)

                Spacer()

                // Language tag
                if let lang = project.tags.first, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }

                // Status indicator
                Text(project.status.label.prefix(3))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(project.status.color.opacity(0.6))
            }
            .frame(width: labelWidth)
            .padding(.horizontal, 8)

            // Bar area
            ZStack(alignment: .leading) {
                // Row background (alternating)
                Color.white.opacity(isHovered ? 0.03 : 0.0)
                    .frame(width: totalWidth, height: rowHeight)

                // The bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                project.perspective.color.opacity(isHovered ? 0.6 : 0.35),
                                project.status.color.opacity(isHovered ? 0.5 : 0.25)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: isHovered ? 16 : 12)
                    .offset(x: barStart)

                // Duration label on hover
                if isHovered && barWidth > 30 {
                    Text("\(daysActive)d")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .offset(x: barStart + barWidth + 4)
                }

                // Commit count if available
                if project.commitCount > 0 && barWidth > 20 {
                    Text("\(project.commitCount)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(x: barStart + 3, y: 0)
                }
            }
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredProject = hovering ? project.id : nil
            }
        }
        .onTapGesture {
            selectedProject = project
        }
        .contextMenu {
            Button("Run Agent Session") {
                launchAgent(project: project)
            }
            Button("Open in iTerm") {
                if let path = project.localPath {
                    DeskfloorApp.openInITerm("cd \(path)")
                } else {
                    DeskfloorApp.sshJump(host: "hyle")
                }
            }
            if let repo = project.repo {
                Button("Open on GitHub") {
                    if let url = URL(string: "https://github.com/\(repo)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Divider()
            Menu("Set Status") {
                ForEach(Status.allCases) { status in
                    Button(status.label) {
                        // Need store access for this — pass through or use notification
                    }
                }
            }
        }
    }

    private func launchAgent(project: Project) {
        var cmd = ""
        if let path = project.localPath {
            cmd = "cd \(path) && claude"
        } else if let repo = project.repo {
            cmd = "cd ~/Nissan && gh repo clone \(repo) && cd \(project.name) && claude"
        } else {
            cmd = "claude"
        }
        DeskfloorApp.openInITerm(cmd)
    }

    // MARK: - Helpers

    private func dateRange(_ projects: [Project]) -> (Date, Date) {
        let dates = projects.compactMap(\.startDate) + projects.compactMap(\.lastActivity)
        let earliest = dates.min() ?? Date()
        let latest = dates.max() ?? Date()
        let cal = Calendar.current
        return (
            cal.date(byAdding: .day, value: -14, to: earliest) ?? earliest,
            cal.date(byAdding: .day, value: 14, to: latest) ?? latest
        )
    }

    private struct MonthMarker {
        let label: String
        let offset: Int
    }

    private func generateMonths(from earliest: Date, totalDays: Int) -> [MonthMarker] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        var markers: [MonthMarker] = []
        var current = cal.date(from: cal.dateComponents([.year, .month], from: earliest)) ?? earliest

        while true {
            let dayOffset = cal.dateComponents([.day], from: earliest, to: current).day ?? 0
            if dayOffset > totalDays { break }
            if dayOffset >= 0 {
                markers.append(MonthMarker(label: formatter.string(from: current), offset: max(dayOffset, 0)))
            }
            current = cal.date(byAdding: .month, value: 1, to: current) ?? current
        }
        return markers
    }
}
