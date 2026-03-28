import SwiftUI

enum DebugTab: String, CaseIterable {
    case rawData = "Raw Data"
    case bleConsole = "BLE Console"
    case storage = "Storage"
}

/// Debug panel showing raw workout JSON, live BLE log, and storage info.
struct DebugView: View {
    let workouts: [WorkoutSaveData]
    @ObservedObject var walkingPadService: WalkingPadService
    @State private var selectedTab: DebugTab = .rawData

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(DebugTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            switch selectedTab {
            case .rawData:
                rawDataTab
            case .bleConsole:
                bleConsoleTab
            case .storage:
                storageTab
            }
        }
    }

    // MARK: - Raw Data Tab

    private var rawDataTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(workouts.reversed().enumerated()), id: \.offset) { _, workout in
                    workoutCard(workout)
                }

                if workouts.isEmpty {
                    Text("No workout data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                }
            }
            .padding(12)
        }
    }

    private func workoutCard(_ w: WorkoutSaveData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(w.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                .font(.caption.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                GridRow {
                    label("Steps")
                    value("\(w.steps)")
                    label("Distance")
                    value("\(w.distance) m")
                }
                GridRow {
                    label("Time")
                    value("\(w.walkingSeconds)s")
                    label("Sessions")
                    value("\(w.sessions?.count ?? 0)")
                }
            }

            if let sessions = w.sessions, !sessions.isEmpty {
                Divider().opacity(0.3)
                ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 8) {
                        Text("#\(i + 1)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(s.startTime, format: .dateTime.hour().minute())
                        Text("→")
                            .foregroundStyle(.tertiary)
                        Text(s.endTime, format: .dateTime.hour().minute())
                        Spacer()
                        Text("\(s.steps) steps")
                        Text("\(s.distance) m")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
    }

    // MARK: - BLE Console Tab

    private var bleConsoleTab: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(walkingPadService.debugLog) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.time))
                                    .foregroundStyle(.tertiary)
                                Text(entry.message)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: walkingPadService.debugLog.count) { _, _ in
                    if let last = walkingPadService.debugLog.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("\(walkingPadService.debugLog.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    walkingPadService.debugLog.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        let storageInfo = computeStorageInfo()

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                storageRow(
                    icon: "doc.text",
                    title: "workouts.json",
                    detail: storageInfo.workoutsSize,
                    subtitle: "\(workouts.count) entries, \(workouts.flatMap { $0.sessions ?? [] }.count) sessions"
                )

                storageRow(
                    icon: "gearshape",
                    title: "MQTT Config",
                    detail: storageInfo.mqttSize,
                    subtitle: storageInfo.mqttExists ? "Configured" : "Not configured"
                )

                Divider().opacity(0.3)

                storageRow(
                    icon: "folder",
                    title: "App Container",
                    detail: storageInfo.containerSize,
                    subtitle: storageInfo.containerPath
                )

                storageRow(
                    icon: "key",
                    title: "Keychain",
                    detail: "—",
                    subtitle: "accessToken, refreshToken (if logged in)"
                )

                storageRow(
                    icon: "slider.horizontal.3",
                    title: "UserDefaults",
                    detail: "—",
                    subtitle: "expiryDate"
                )
            }
            .padding(12)
        }
    }

    private func storageRow(icon: String, title: String, detail: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(detail)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func computeStorageInfo() -> StorageInfo {
        let fs = FileSystem()
        let containerURL = FileManager.default.urls(for: .autosavedInformationDirectory, in: .userDomainMask).first

        let workoutsSize = fileSize(fs, filename: "workouts.json")
        let mqttData = fs.load(filename: ".walkingpad-client-mqtt.json")
        let mqttSize = mqttData != nil ? formatBytes(mqttData!.count) : "—"

        var containerSize = "—"
        var containerPath = "~/Library/Containers/klassm.walkingpad-client/"
        if let url = containerURL {
            containerPath = url.path
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                var total: Int64 = 0
                while let fileURL = enumerator.nextObject() as? URL {
                    let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                    total += Int64(attrs?.fileSize ?? 0)
                }
                containerSize = formatBytes(Int(total))
            }
        }

        return StorageInfo(
            workoutsSize: workoutsSize,
            mqttSize: mqttSize,
            mqttExists: mqttData != nil,
            containerSize: containerSize,
            containerPath: containerPath
        )
    }

    private func fileSize(_ fs: FileSystem, filename: String) -> String {
        if let data = fs.load(filename: filename) {
            return formatBytes(data.count)
        }
        return "—"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }
}

private struct StorageInfo {
    let workoutsSize: String
    let mqttSize: String
    let mqttExists: Bool
    let containerSize: String
    let containerPath: String
}
