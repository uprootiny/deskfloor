import SwiftUI

// MARK: - Skein View (Cmd+5) — Temporal topology of conversation threads

struct SkeinView: View {
    @State var skein: SkeinStore
    @State var store: ProjectStore
    @State private var selectedThreadID: UUID?
    @State private var selectedTurnID: UUID?
    @State private var zoomScale: CGFloat = 1.0     // pixels per hour
    @State private var scrollOffset: CGFloat = 0
    @State private var filterText = ""
    @State private var filterSource: Thread.Source?
    @State private var filterStatus: SessionStatus?
    @State private var showImportOptions = false

    private let barHeight: CGFloat = 24
    private let subagentBarHeight: CGFloat = 8
    private let groupGap: CGFloat = 12
    private let barGap: CGFloat = 3
    private let leftMargin: CGFloat = 100
    private let rulerHeight: CGFloat = 32

    private var filteredThreads: [Thread] {
        skein.threads.filter { thread in
            if let source = filterSource, thread.source != source { return false }
            if let status = filterStatus, thread.status != status { return false }
            if !filterText.isEmpty {
                let query = filterText.lowercased()
                let match = thread.title.lowercased().contains(query)
                    || thread.topics.contains { $0.lowercased().contains(query) }
                    || thread.tags.contains { $0.lowercased().contains(query) }
                if !match { return false }
            }
            return true
        }
    }

    private var threadsBySource: [(Thread.Source, [Thread])] {
        let grouped = Dictionary(grouping: filteredThreads, by: \.source)
        let order: [Thread.Source] = [.claudeCode, .claudeWeb, .chatGPT, .agentSlack, .manual]
        return order.compactMap { source in
            guard let threads = grouped[source], !threads.isEmpty else { return nil }
            return (source, threads.sorted { $0.createdAt < $1.createdAt })
        }
    }

    private var timeRange: (start: Date, end: Date) {
        let allDates = skein.threads.flatMap { [$0.createdAt, $0.updatedAt] }
        let start = allDates.min() ?? Date()
        let end = allDates.max() ?? Date()
        let cal = Calendar.current
        return (
            cal.date(byAdding: .day, value: -1, to: start) ?? start,
            cal.date(byAdding: .day, value: 1, to: end) ?? end
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.2)

            if skein.threads.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Ruler + lanes
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                lanesCanvas(size: geo.size)
                            }
                        }

                        // Detail strip
                        if let thread = selectedThread {
                            Divider().background(Color.white.opacity(0.08))
                            detailStrip(thread: thread)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))

            TextField("Filter threads...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            Picker("Source", selection: Binding(
                get: { filterSource },
                set: { filterSource = $0 }
            )) {
                Text("All Sources").tag(nil as Thread.Source?)
                ForEach(Thread.Source.allCases, id: \.self) { source in
                    Text(source.label).tag(source as Thread.Source?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Status", selection: Binding(
                get: { filterStatus },
                set: { filterStatus = $0 }
            )) {
                Text("All Status").tag(nil as SessionStatus?)
                ForEach(SessionStatus.allCases) { status in
                    Label(status.label, systemImage: status.icon).tag(status as SessionStatus?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            Text("\(filteredThreads.count) of \(skein.threads.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("Import") { showImportOptions = true }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .popover(isPresented: $showImportOptions) { importPopover }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // MARK: - Lanes Canvas

    private func lanesCanvas(size: CGSize) -> some View {
        let range = timeRange
        let totalHours = range.end.timeIntervalSince(range.start) / 3600
        let pixelsPerHour = max(size.width - leftMargin, 400) / CGFloat(totalHours)
        let totalWidth = leftMargin + CGFloat(totalHours) * pixelsPerHour

        var yOffset: CGFloat = rulerHeight
        var allRows: [(Thread, CGFloat, CGFloat)] = [] // thread, y, height

        for (source, threads) in threadsBySource {
            let h = source == .claudeCode ? barHeight : (source == .agentSlack ? 10 : 18)
            for thread in threads {
                allRows.append((thread, yOffset, h))
                yOffset += h + barGap
            }
            yOffset += groupGap
        }

        let totalHeight = max(yOffset + 20, size.height * 0.6)

        return Canvas { context, canvasSize in
            let cal = Calendar.current

            // Background
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)),
                         with: .color(Color(red: 0.06, green: 0.06, blue: 0.08)))

            // Ruler background
            context.fill(
                Path(CGRect(x: 0, y: 0, width: canvasSize.width, height: rulerHeight)),
                with: .color(Color(red: 0.08, green: 0.08, blue: 0.10))
            )

            // Date labels on ruler
            var dateMarker = cal.startOfDay(for: range.start)
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "MMM d"
            while dateMarker < range.end {
                let hoursFromStart = dateMarker.timeIntervalSince(range.start) / 3600
                let x = leftMargin + CGFloat(hoursFromStart) * pixelsPerHour

                // Tick
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: rulerHeight - 6)); p.addLine(to: CGPoint(x: x, y: rulerHeight)) },
                    with: .color(.white.opacity(0.15)), lineWidth: 1
                )

                // Label
                let text = Text(dateFmt.string(from: dateMarker))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                context.draw(text, at: CGPoint(x: x + 4, y: rulerHeight / 2), anchor: .leading)

                dateMarker = cal.date(byAdding: .day, value: 1, to: dateMarker) ?? dateMarker.addingTimeInterval(86400)
            }

            // Today marker
            let nowHours = Date().timeIntervalSince(range.start) / 3600
            let nowX = leftMargin + CGFloat(nowHours) * pixelsPerHour
            if nowX > leftMargin && nowX < canvasSize.width {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: nowX, y: 0)); p.addLine(to: CGPoint(x: nowX, y: canvasSize.height)) },
                    with: .color(.red.opacity(0.3)), lineWidth: 1
                )
                let nowLabel = Text("now").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.5))
                context.draw(nowLabel, at: CGPoint(x: nowX + 3, y: 8), anchor: .leading)
            }

            // Source group labels
            var groupY = rulerHeight
            for (source, threads) in threadsBySource {
                let label = Text(source.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
                context.draw(label, at: CGPoint(x: 8, y: groupY + 10), anchor: .leading)

                let h = source == .claudeCode ? barHeight : (source == .agentSlack ? 10 : 18)
                groupY += CGFloat(threads.count) * (h + barGap) + groupGap
            }

            // Thread bars
            for (thread, y, h) in allRows {
                let startHours = thread.createdAt.timeIntervalSince(range.start) / 3600
                let endHours = thread.updatedAt.timeIntervalSince(range.start) / 3600
                let x = leftMargin + CGFloat(startHours) * pixelsPerHour
                let w = max(CGFloat(endHours - startHours) * pixelsPerHour, 4)

                let barRect = CGRect(x: x, y: y, width: w, height: h)
                let barPath = Path(roundedRect: barRect, cornerRadius: 4)

                // Color by source
                let baseColor = thread.color?.swiftUIColor ?? sourceColor(thread.source)

                // Opacity by status
                let opacity: Double
                switch thread.status {
                case .live: opacity = 1.0
                case .completed: opacity = 0.8
                case .paused: opacity = 0.5
                case .abandoned: opacity = 0.3
                case .crashed: opacity = 0.6
                case .hypothetical: opacity = 0.4
                case .archived: opacity = 0.25
                }

                context.fill(barPath, with: .color(baseColor.opacity(opacity)))

                // Selected highlight
                if thread.id == selectedThreadID {
                    context.stroke(barPath, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
                }

                // Abandoned = dashed border
                if thread.status == .abandoned {
                    context.stroke(barPath, with: .color(baseColor.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Turn ticks (only if bar is wide enough)
                if w > 20 {
                    for turn in thread.turns {
                        guard let ts = turn.timestamp else { continue }
                        let turnHours = ts.timeIntervalSince(range.start) / 3600
                        let tickX = leftMargin + CGFloat(turnHours) * pixelsPerHour
                        guard tickX >= x && tickX <= x + w else { continue }

                        let tickColor: Color
                        let tickH: CGFloat
                        if turn.isBreakthrough {
                            tickColor = .green.opacity(0.8)
                            tickH = h
                        } else if turn.isDeadEnd {
                            tickColor = .red.opacity(0.6)
                            tickH = h * 0.7
                        } else if turn.isBookmarked {
                            tickColor = Color(red: 0.9, green: 0.75, blue: 0.2).opacity(0.7)
                            tickH = h
                        } else {
                            tickColor = .white.opacity(0.12)
                            tickH = h * 0.5
                        }

                        context.fill(
                            Path(CGRect(x: tickX, y: y + (h - tickH) / 2, width: 1, height: tickH)),
                            with: .color(tickColor)
                        )
                    }
                }

                // Title label (if bar is wide enough)
                if w > 80 {
                    let title = Text(thread.title.prefix(Int(w / 6)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    context.draw(title, at: CGPoint(x: x + 6, y: y + h / 2), anchor: .leading)
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .onTapGesture { location in
            // Hit-test thread bars
            for (thread, y, h) in allRows {
                let range = self.timeRange
                let totalHours = range.end.timeIntervalSince(range.start) / 3600
                let pph = max((size.width - leftMargin), 400) / CGFloat(totalHours)
                let startH = thread.createdAt.timeIntervalSince(range.start) / 3600
                let endH = thread.updatedAt.timeIntervalSince(range.start) / 3600
                let x = leftMargin + CGFloat(startH) * pph
                let w = max(CGFloat(endH - startH) * pph, 4)

                let rect = CGRect(x: x, y: y, width: w, height: h)
                if rect.contains(location) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedThreadID = (selectedThreadID == thread.id) ? nil : thread.id
                    }
                    return
                }
            }
            withAnimation { selectedThreadID = nil }
        }
    }

    // MARK: - Detail Strip

    private func detailStrip(thread: Thread) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: thread.status.icon)
                    .foregroundStyle(thread.status.color)
                    .font(.system(size: 12))

                Text(thread.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(thread.source.label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(sourceColor(thread.source).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text(thread.createdAt, style: .date)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))

                // Status picker
                Picker("", selection: Binding(
                    get: { thread.status },
                    set: { skein.setThreadStatus(thread.id, $0) }
                )) {
                    ForEach(SessionStatus.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            HStack(spacing: 16) {
                statBadge("\(thread.turns.count) turns", icon: "bubble.left.and.bubble.right")
                statBadge("\(thread.toolLoopCount) tools", icon: "wrench")
                statBadge("\(thread.artifactCount) artifacts", icon: "doc.text")

                if !thread.topics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(thread.topics.prefix(5), id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 9, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    private func statBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(.white.opacity(0.35))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))

            Text("No conversation threads")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Text("Import from Claude Code, ChatGPT, or Claude.ai to see your conversation timeline.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Import Claude Code Conversations") {
                importClaudeCode()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.35, green: 0.65, blue: 0.95).opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import

    private var importPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: importClaudeCode) {
                Label("Import Claude Code (local)", systemImage: "terminal")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: {}) {
                Label("Import ChatGPT (conversations.json)", systemImage: "doc")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(true) // TODO: file picker

            Button(action: {}) {
                Label("Import Claude.ai (data export)", systemImage: "doc")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(true) // TODO: file picker
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    private func importClaudeCode() {
        showImportOptions = false
        Task {
            let threads = ClaudeCodeImporter.importAll()
            let existingIDs = Set(skein.threads.map(\.id))
            let newThreads = threads.filter { !existingIDs.contains($0.id) }
            for thread in newThreads {
                skein.addThread(thread)
            }
            NSLog("[SkeinView] Imported \(newThreads.count) new threads (\(threads.count) total found)")
        }
    }

    // MARK: - Helpers

    private func sourceColor(_ source: Thread.Source) -> Color {
        switch source {
        case .claudeCode: Color(red: 0.35, green: 0.65, blue: 0.95)
        case .claudeWeb: Color(red: 0.85, green: 0.55, blue: 0.25)
        case .chatGPT: Color(red: 0.4, green: 0.8, blue: 0.5)
        case .agentSlack: Color(red: 0.6, green: 0.5, blue: 0.8)
        case .codex: Color(red: 0.5, green: 0.7, blue: 0.5)
        case .manual: .white.opacity(0.5)
        }
    }

    private var selectedThread: Thread? {
        guard let id = selectedThreadID else { return nil }
        return skein.threads.first { $0.id == id }
    }
}
