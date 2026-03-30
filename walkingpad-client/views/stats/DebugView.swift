import SwiftUI

enum DebugTab: String, CaseIterable {
    case rawData = "Raw Data"
    case bleConsole = "BLE Console"
    case storage = "Storage"
    case notion = "Notion"
}

/// Debug panel showing raw workout JSON, live BLE log, storage info, and Notion config.
struct DebugView: View {
    let workouts: [WorkoutSaveData]
    @ObservedObject var walkingPadService: WalkingPadService
    @ObservedObject var notionService: NotionService
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
            case .notion:
                notionTab
            }
        }
    }

    // MARK: - Notion Tab

    @State private var notionApiKey: String = ""
    @State private var notionDatabaseId: String = "333deabd-9164-80f2-9adf-c79a07bf14d1"
    @State private var notionTestResult: String? = nil
    @State private var notionTesting: Bool = false

    private var notionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Image(systemName: notionService.isConfigured ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(notionService.isConfigured ? .green : .secondary)
                    Text(notionService.isConfigured ? "Connected" : "Not configured")
                        .font(.callout.weight(.medium))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                // API Key
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    SecureField("ntn_...", text: $notionApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                }

                // Database ID
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database ID")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("Database ID", text: $notionDatabaseId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                }

                // Buttons
                HStack(spacing: 8) {
                    Button("Save") {
                        guard !notionApiKey.isEmpty, !notionDatabaseId.isEmpty else { return }
                        notionService.saveConfig(apiKey: notionApiKey, databaseId: notionDatabaseId)
                        notionApiKey = ""
                    }
                    .disabled(notionApiKey.isEmpty || notionDatabaseId.isEmpty)

                    Button("Test") {
                        notionTesting = true
                        notionTestResult = nil
                        Task {
                            let success = await notionService.testConnection()
                            await MainActor.run {
                                notionTestResult = success ? "Connection successful" : "Connection failed"
                                notionTesting = false
                            }
                        }
                    }
                    .disabled(!notionService.isConfigured && notionApiKey.isEmpty)

                    if notionService.isConfigured {
                        Button("Clear") {
                            notionService.clearConfig()
                            notionTestResult = nil
                        }
                        .foregroundStyle(.red)
                    }

                    Spacer()

                    if notionTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.caption)

                // Test result
                if let result = notionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("successful") ? .green : .red)
                }
            }
            .padding(12)
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
                Text("Sessions")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                    let duration = Int(s.endTime.timeIntervalSince(s.startTime))
                    let minutes = duration / 60
                    let seconds = duration % 60
                    let distKm = Double(s.distance) / 1000.0

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("#\(i + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            Text(s.startTime, format: .dateTime.hour().minute().second())
                            Text("→")
                                .foregroundStyle(.tertiary)
                            Text(s.endTime, format: .dateTime.hour().minute().second())
                            Spacer()
                            Text("\(minutes)m \(seconds)s")
                                .foregroundStyle(.primary)
                        }
                        HStack(spacing: 16) {
                            HStack(spacing: 3) {
                                Text("Steps:")
                                    .foregroundStyle(.tertiary)
                                Text("\(s.steps)")
                            }
                            HStack(spacing: 3) {
                                Text("Dist:")
                                    .foregroundStyle(.tertiary)
                                Text(distKm >= 0.1 ? String(format: "%.2f km", distKm) : "\(s.distance) m")
                            }
                            if duration > 0 {
                                HStack(spacing: 3) {
                                    Text("Avg:")
                                        .foregroundStyle(.tertiary)
                                    let avgSpeed = (distKm / (Double(duration) / 3600.0))
                                    Text(String(format: "%.1f km/h", avgSpeed))
                                }
                            }
                        }
                        .padding(.leading, 26)
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }
            } else {
                Text("No session data (recorded before session tracking)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
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
