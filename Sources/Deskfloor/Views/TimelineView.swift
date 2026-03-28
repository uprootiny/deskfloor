import SwiftUI

struct ProjectTimelineView: View {
    let filteredProjects: [Project]
    @Binding var selectedProject: Project?
    // showDetail removed

    private let rowHeight: CGFloat = 32
    private let labelWidth: CGFloat = 160

    var body: some View {
        let sorted = filteredProjects
            .filter { $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        if sorted.isEmpty {
            VStack {
                Spacer()
                Text("No projects with start dates")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let (earliest, latest) = dateRange(sorted)
            let totalDays = max(Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 1, 1)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    // Month headers
                    timelineHeader(earliest: earliest, totalDays: totalDays)

                    ForEach(sorted) { project in
                        timelineRow(project: project, earliest: earliest, totalDays: totalDays)
                    }
                }
                .padding()
            }
        }
    }

    private func timelineHeader(earliest: Date, totalDays: Int) -> some View {
        let pixelsPerDay: CGFloat = 4
        let totalWidth = CGFloat(totalDays) * pixelsPerDay

        return HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth, height: 20)

            ZStack(alignment: .leading) {
                Color.clear.frame(width: totalWidth, height: 20)

                let months = generateMonths(from: earliest, totalDays: totalDays)
                ForEach(months, id: \.offset) { month in
                    Text(month.label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .offset(x: CGFloat(month.offset) * pixelsPerDay)
                }
            }
        }
    }

    private func timelineRow(project: Project, earliest: Date, totalDays: Int) -> some View {
        let cal = Calendar.current
        let pixelsPerDay: CGFloat = 4
        let totalWidth = CGFloat(totalDays) * pixelsPerDay

        let startDay = cal.dateComponents([.day], from: earliest, to: project.startDate ?? earliest).day ?? 0
        let endDay: Int
        if let last = project.lastActivity {
            endDay = max(cal.dateComponents([.day], from: earliest, to: last).day ?? startDay, startDay + 1)
        } else {
            endDay = startDay + 1
        }

        let barStart = CGFloat(startDay) * pixelsPerDay
        let barWidth = max(CGFloat(endDay - startDay) * pixelsPerDay, 4)

        return HStack(spacing: 0) {
            // Label
            HStack(spacing: 4) {
                Circle()
                    .fill(project.perspective.color)
                    .frame(width: 6, height: 6)
                Text(project.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: labelWidth, alignment: .leading)

            // Bar area
            ZStack(alignment: .leading) {
                Color.clear.frame(width: totalWidth, height: rowHeight)

                RoundedRectangle(cornerRadius: 3)
                    .fill(project.status.color.opacity(0.4))
                    .frame(width: barWidth, height: 12)
                    .offset(x: barStart)

                // Progress note dots
                ForEach(project.progressNotes) { note in
                    let noteDay = cal.dateComponents([.day], from: earliest, to: note.date).day ?? 0
                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .offset(x: CGFloat(noteDay) * pixelsPerDay)
                        .help(note.note)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProject = project
            // sheet shows automatically
        }
    }

    private func dateRange(_ projects: [Project]) -> (Date, Date) {
        let dates = projects.compactMap(\.startDate) + projects.compactMap(\.lastActivity)
        let earliest = dates.min() ?? Date()
        let latest = dates.max() ?? Date()
        let cal = Calendar.current
        let paddedEarliest = cal.date(byAdding: .day, value: -7, to: earliest) ?? earliest
        let paddedLatest = cal.date(byAdding: .day, value: 14, to: latest) ?? latest
        return (paddedEarliest, paddedLatest)
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
