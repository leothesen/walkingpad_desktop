import SwiftUI

/// Isolated view for the activity log tab.
/// Keeps ActivityLog observation separate from DebugView to prevent
/// layout thrashing when the debug panel is toggled.
struct ActivityLogTabView: View {
    @ObservedObject private var activityLog = ActivityLog.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(activityLog.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                logIcon(entry.type)
                                    .frame(width: 12)
                                Text(Self.timeFormatter.string(from: entry.time))
                                    .foregroundStyle(.tertiary)
                                Text(entry.message)
                                    .foregroundStyle(logColor(entry.type))
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: activityLog.entries.count) { _, _ in
                    if let last = activityLog.entries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(activityLog.entries.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    activityLog.entries.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func logIcon(_ type: ActivityLogEntry.LogType) -> some View {
        switch type {
        case .info:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle").foregroundStyle(.red)
        case .progress:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        }
    }

    private func logColor(_ type: ActivityLogEntry.LogType) -> Color {
        switch type {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        case .progress: return .blue
        }
    }
}
