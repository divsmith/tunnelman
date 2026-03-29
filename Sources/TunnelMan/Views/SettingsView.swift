import SwiftUI
import ServiceManagement
import TunnelManServer

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("shellPath") private var shellPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()

            Divider()

            // Tunnel mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Tunnel Mode").font(.headline)
                Picker("Mode", selection: $sessionManager.tunnelMode) {
                    ForEach(TunnelMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                tunnelHelpText
            }

            Divider()

            // Prerequisites
            VStack(alignment: .leading, spacing: 6) {
                Text("Prerequisites").font(.headline)
                prerequisiteRow("devtunnel", brew: "brew install --cask devtunnel", note: "Run 'devtunnel user login' once")
                prerequisiteRow("cloudflared", brew: "brew install cloudflared", note: "No login required for quick tunnels")
            }

            Divider()

            // Launch at login
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    setLaunchAtLogin(enabled)
                }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: 420)
    }

    @ViewBuilder
    private var tunnelHelpText: some View {
        switch sessionManager.tunnelMode {
        case .local:
            Text("Accessible only on your local WiFi network. No external tools required. Token auth protects access.")
                .font(.caption).foregroundColor(.secondary)
        case .devtunnel:
            Text("Microsoft DevTunnel: requires devtunnel CLI + one-time login. Only your Microsoft/GitHub account can access the tunnel.")
                .font(.caption).foregroundColor(.secondary)
        case .cloudflare:
            Text("Cloudflare quick tunnel: accessible from anywhere. No account required. Session token is the authentication layer.")
                .font(.caption).foregroundColor(.orange)
        }
    }

    private func prerequisiteRow(_ name: String, brew: String, note: String) -> some View {
        let installed = findExecutable(name) != nil
        return HStack(spacing: 8) {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(installed ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(.caption, design: .monospaced))
                if !installed {
                    Text(brew)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(note).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if !installed {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(brew, forType: .string)
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can manage via System Settings > General > Login Items
            }
        }
    }
}
