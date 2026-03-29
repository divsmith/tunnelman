import SwiftUI
import TunnelManServer

struct PopoverView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showSettings = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
            Divider()
            controls
        }
        .padding(16)
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView(sessionManager: sessionManager)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .foregroundColor(.accentColor)
            Text("TunnelMan")
                .font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch sessionManager.tunnelState {
        case .idle:
            idleView
        case .starting:
            startingView
        case .connected:
            connectedView
        case .error(let msg):
            errorView(msg)
        case .needsDevTunnelLogin:
            devTunnelLoginView
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No active session")
                .foregroundColor(.secondary)
            Text("Start a session to get a QR code\nyou can scan from your phone.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var startingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Starting tunnel…")
                .foregroundColor(.secondary)
            Text("Mode: \(sessionManager.tunnelMode.rawValue)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var connectedView: some View {
        VStack(spacing: 12) {
            if let url = sessionManager.sessionURL {
                QRCodeView(url: url)

                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(sessionManager.tunnelMode.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy URL", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(copied ? .green : .accentColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var devTunnelLoginView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Sign in to DevTunnel")
                .font(.headline)
            Text("You must be logged in before hosting a DevTunnel session.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    sessionManager.loginWithDevTunnel(github: false)
                } label: {
                    Text("Sign in with Microsoft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    sessionManager.loginWithDevTunnel(github: true)
                } label: {
                    Text("Sign in with GitHub")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            modeMenu
            Spacer()
            sessionButton
        }
    }

    private var modeMenu: some View {
        Picker(selection: Binding(
            get: { sessionManager.tunnelMode },
            set: { newMode in
                if case .idle = sessionManager.tunnelState {
                    sessionManager.tunnelMode = newMode
                }
            }
        )) {
            ForEach(TunnelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        } label: {
            Label("Mode", systemImage: "network")
        }
        .pickerStyle(.menu)
        .disabled(sessionManager.tunnelState != .idle)
    }

    @ViewBuilder
    private var sessionButton: some View {
        switch sessionManager.tunnelState {
        case .idle, .error:
            Button("Start Session") {
                sessionManager.startSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        case .starting:
            Button("Cancel") {
                sessionManager.stopSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        case .connected:
            Button("Stop Session") {
                sessionManager.stopSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
        case .needsDevTunnelLogin:
            Button("Cancel") {
                sessionManager.stopSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}
