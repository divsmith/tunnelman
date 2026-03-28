# MacTunnel

A macOS menu bar app that gives you a **secure, full terminal session accessible from your phone** — no configuration servers, no open firewall ports, no insecure exposure.

Click the menu bar icon → get a QR code → scan from your phone → type in a full shell right in your browser.

![Menu bar icon showing terminal symbol with popover containing QR code](docs/screenshot-placeholder.png)

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Your Mac (MacTunnel.app)                                   │
│                                                             │
│  PTY (zsh/bash)  ←→  WebSocket Server  ←→  Tunnel CLI      │
│                            ↓                    ↓           │
│                      terminal.html        Tunnel URL        │
│                      (xterm.js)           in QR code        │
└─────────────────────────────────────────────────────────────┘
                                 ↕  TLS via tunnel infra
                          ┌─────────────┐
                          │ Your Phone  │
                          │  Browser    │
                          │  xterm.js   │
                          └─────────────┘
```

1. MacTunnel spawns your shell (`$SHELL`) in a **PTY** (pseudo-terminal)
2. A local HTTP + WebSocket server streams PTY I/O to an **xterm.js** frontend
3. A tunnel CLI (`devtunnel` or `cloudflared`) provides an **authenticated HTTPS relay** — no inbound firewall ports opened
4. A **QR code** encodes the tunnel URL plus a **cryptographic session token** — scan it and you're in

---

## Security Model

MacTunnel uses **layered security** and never exposes your Mac insecurely to the internet:

| Layer | What it does |
|---|---|
| **Tunnel auth** | DevTunnel: only your Microsoft/GitHub account can connect. Cloudflare: session token is the auth gate. Local: LAN-only, no external exposure. |
| **Session token** | A random 32-char hex UUID is generated per session and embedded in the QR code URL. The WebSocket server rejects connections with an invalid or missing token with `401`. |
| **TLS** | All traffic is encrypted in transit by the tunnel infrastructure (Microsoft or Cloudflare). No self-signed certificates needed. |
| **No open ports** | Tunnel CLIs create outbound-only connections. Your Mac's firewall is not touched. |

---

## Requirements

### System

- **macOS 13 Ventura** or later (arm64 or x86_64)
- **Xcode 15** or later (for building) — or just the **Swift toolchain** (no Xcode GUI required)

### Swift toolchain (if not using Xcode)

Download from [swift.org/download](https://www.swift.org/download/) and ensure `swift` is in your `PATH`:

```bash
swift --version
# Apple Swift version 6.x ...
```

### Tunnel CLIs (optional — only needed for remote access)

**Microsoft DevTunnel** (recommended — account-authenticated):
```bash
brew install --cask devtunnel
devtunnel user login          # one-time login with Microsoft or GitHub account
```

**Cloudflare Tunnel** (no account required for quick tunnels):
```bash
brew install cloudflared
```

> **Local Network mode** requires no external tools at all — it works on your LAN immediately.

---

## Building

### With `swift build` (no Xcode GUI)

```bash
git clone <repo-url>
cd mactunnel
swift build -c release
```

The binary is at `.build/release/MacTunnel`.

### With Xcode

```bash
open Package.swift          # opens the project in Xcode
```

Then **Product → Run** (`⌘R`), or **Product → Archive** to build a distributable `.app`.

> **Note:** For distributing outside the Mac App Store you'll need to set your Apple Developer signing identity in Xcode and notarize the app. The app uses `openpty` and `fork` (via a C helper), which are not permitted in the Mac App Store sandbox.

---

## Running

### From the command line

```bash
swift run
# or, after building:
.build/release/MacTunnel
```

The app will appear in your menu bar as a **terminal icon (⌥)**. It intentionally hides from the Dock.

### Usage

1. **Click** the menu bar icon to open the popover
2. **Choose a tunnel mode** from the bottom-left menu:
   - `Local Network` — works on the same WiFi, no external tools needed
   - `Microsoft DevTunnel` — accessible from anywhere, requires `devtunnel user login`
   - `Cloudflare Tunnel` — accessible from anywhere, no account needed
3. **Click "Start Session"**
4. **Scan the QR code** with your phone, or click "Copy URL" and paste it in a browser
5. A full interactive terminal opens in your phone's browser — type freely, run any CLI tool
6. **Click "Stop Session"** when done — the tunnel tears down, the session token is invalidated

### Settings

Click the **gear icon** (⚙) in the popover to open Settings:

| Setting | Description |
|---|---|
| Default tunnel mode | Persisted across launches |
| devtunnel status | Shows ✅ if installed, ❌ with install command if not |
| cloudflared status | Same |
| Launch at login | Registers with macOS Login Items (macOS 13+) |

---

## Tunnel Modes In Depth

### Local Network

- **No external tools required**
- Detects your Mac's LAN IP (e.g. `192.168.1.42`) and serves on a random port
- URL: `http://192.168.1.42:PORT/terminal?token=TOKEN`
- Works only when your phone is on the **same WiFi network**
- Session token provides authentication
- For Tailscale users: this mode works across Tailscale too

### Microsoft DevTunnel

- Requires `devtunnel` CLI and a one-time `devtunnel user login`
- Creates a **private** tunnel — only the authenticated account can connect (not a guessable public URL)
- URL: `https://UNIQUE-ID.devtunnels.ms/terminal?token=TOKEN`
- Free tier available; see [Microsoft DevTunnel docs](https://aka.ms/devtunnels/doc)

### Cloudflare Tunnel

- Requires `cloudflared` CLI; no Cloudflare account needed for **quick tunnels**
- Creates a random `*.trycloudflare.com` URL that's publicly reachable via HTTPS
- **Auth is the session token** (embedded in the QR code) — without it the terminal page returns `401`
- For stronger auth: set up a [named Cloudflare Tunnel with Access policies](https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/) (email OTP, GitHub OAuth, etc.)
- URL: `https://random-words.trycloudflare.com/terminal?token=TOKEN`

---

## Project Structure

```
mactunnel/
├── Package.swift                        # Swift Package manifest (macOS 13+)
├── Sources/
│   ├── MacTunnelHelper/                 # C helper (fork/exec into PTY)
│   │   ├── include/pty_spawn.h
│   │   └── pty_spawn.c
│   └── MacTunnel/                       # Swift app
│       ├── MacTunnelApp.swift           # @main entry point, AppDelegate
│       ├── StatusBarController.swift    # NSStatusItem + popover management
│       ├── SessionManager.swift         # Central coordinator (ObservableObject)
│       ├── Views/
│       │   ├── PopoverView.swift        # Popover UI: status, QR, controls
│       │   ├── QRCodeView.swift         # CoreImage QR code generation
│       │   └── SettingsView.swift       # Settings sheet
│       ├── Terminal/
│       │   └── PTYManager.swift         # openpty + pty_spawn_shell + I/O relay
│       ├── Server/
│       │   ├── LocalHTTPServer.swift    # NWListener HTTP server
│       │   ├── HTTPConnection.swift     # Per-connection HTTP handler + routing
│       │   └── WebSocketConnection.swift # RFC 6455 WebSocket, PTY relay, token auth
│       ├── Tunnel/
│       │   ├── TunnelProvider.swift     # Protocol definition
│       │   ├── LocalProvider.swift      # LAN IP provider
│       │   ├── DevTunnelProvider.swift  # devtunnel subprocess + URL parsing
│       │   ├── CloudflaredProvider.swift # cloudflared subprocess + URL parsing
│       │   └── ExecutableFinder.swift   # PATH search utility
│       └── Resources/
│           └── terminal.html           # xterm.js frontend (bundled into app)
```

---

## Architecture Notes

**No third-party Swift dependencies.** The entire app uses only Apple frameworks:

| Need | Solution |
|---|---|
| PTY spawning | POSIX `openpty()` + C `fork()`/`execve()` shim |
| HTTP server | `Network.framework` `NWListener` |
| WebSocket | Manual RFC 6455 framing (no external lib) |
| QR code | `CoreImage` `CIQRCodeGenerator` |
| Crypto | `CryptoKit` `Insecure.SHA1` (WebSocket handshake only) |
| Terminal UI | [xterm.js](https://xtermjs.org/) loaded from CDN in `terminal.html` |

**Why a C helper?** Swift marks `fork()` as unavailable (it conflicts with Swift's concurrency runtime). A thin C file (`pty_spawn.c`) calls `fork()` + `setsid()` + `TIOCSCTTY` + `execve()` to properly set up the PTY child process.

---

## Troubleshooting

**The terminal shows nothing after connecting**
- Make sure you scanned the QR code from the popover (not an old screenshot)
- Each session generates a fresh token — reconnect after stopping/starting

**`devtunnel` mode shows "exited with status 1"**
- Run `devtunnel user login` in Terminal first
- Check `devtunnel` is in your PATH: `which devtunnel`

**`cloudflared` mode shows no URL**
- It can take 10–20 seconds for the trycloudflare.com URL to appear
- Check `cloudflared` is in your PATH: `which cloudflared`

**App won't launch at login**
- Go to **System Settings → General → Login Items** and verify MacTunnel is listed
- You may need to grant permission the first time

**"Unauthorized" when opening the URL manually**
- The token is part of the URL (the `?token=...` query param). Copy the full URL from the popover, don't truncate it.

---

## Acknowledgements

Inspired by:
- [cli-tunnel](https://github.com/tamirdresher/cli-tunnel) — the original Node.js PTY-over-DevTunnel concept
- [itwillsync](https://github.com/shrijayan/itwillsync) — local-network terminal sync
- [Simon Willison's vibe coding SwiftUI post](https://simonwillison.net/2026/Mar/27/vibe-coding-swiftui/) — proof that SwiftUI apps can be built fast and well

---

## License

MIT
