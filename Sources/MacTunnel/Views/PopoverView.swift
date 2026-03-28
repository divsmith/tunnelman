import SwiftUI

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
            Text("MacTunnel")
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
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(copied ? .green : .accentColor)
            }
        }
        .frame(maxWidth: .infinity)
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
        Menu {
            ForEach(TunnelMode.allCases) { mode in
                Button {
                    if case .idle = sessionManager.tunnelState {
                        sessionManager.tunnelMode = mode
                    }
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if sessionManager.tunnelMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(sessionManager.tunnelState != .idle)
            }
        } label: {
            Label(sessionManager.tunnelMode.rawValue, systemImage: "network")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var sessionButton: some View {
        switch sessionManager.tunnelState {
        case .idle, .error:
            Button("Start Session") {
                sessionManager.startSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .starting:
            Button("Cancel") {
                sessionManager.stopSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .connected:
            Button("Stop Session") {
                sessionManager.stopSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }
}
