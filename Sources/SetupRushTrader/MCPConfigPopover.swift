import SwiftUI

extension MCPConnectionStatus {
    var color: Color {
        switch self {
        case .disabled: return Theme.textSecondary
        case .connecting: return Theme.warn
        case .live: return Theme.bull
        case .failed: return Theme.bear
        }
    }

    var label: String {
        switch self {
        case .disabled: return "MCP disabled — Demo Mode"
        case .connecting: return "MCP connecting…"
        case .live: return "MCP connected"
        case .failed(let reason): return "MCP failed: \(reason) — Demo Mode"
        }
    }
}

// Spec §5 "Add MCP Server" onboarding, minimal scope. A sheet rather than a popover: a
// popover anchored inside a horizontally-scrolling header had focus/editing quirks on
// macOS, which is exactly the "can't edit the fields" problem. A sheet is its own modal
// window with no such ambiguity. Edits are a local draft, written back to the real config
// only on Save — Cancel discards them, matching the app's existing explicit-confirm pattern.
struct MCPConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MCPConfig
    let enabled: Bool
    let status: MCPConnectionStatus
    var onSave: (MCPConfig) -> Void
    var onToggle: (Bool) -> Void

    init(config: MCPConfig, enabled: Bool, status: MCPConnectionStatus, onSave: @escaping (MCPConfig) -> Void, onToggle: @escaping (Bool) -> Void) {
        _draft = State(initialValue: config)
        self.enabled = enabled
        self.status = status
        self.onSave = onSave
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP CONNECTION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Toggle("Enable MCP", isOn: Binding(get: { enabled }, set: onToggle))
                .toggleStyle(.switch)
                .tint(Theme.accent)

            field("Host", $draft.host)
            field("Port", $draft.port)
            field("Path", $draft.path)
            Toggle("Use TLS (https)", isOn: $draft.useTLS)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            field("Auth token (optional)", $draft.authToken)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 6) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }

            Text("Real trading data stays on the mock gateway regardless of connection status — the server's actual tool contract isn't confirmed yet. See BACKLOG.md.")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300, height: 420)
        .background(Theme.bgElevated)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}
