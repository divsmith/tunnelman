# TunnelMan — Project Guidelines

macOS menu-bar app (Swift 5.9+, macOS 13+) that exposes a full PTY-backed terminal via a local HTTP+WebSocket server, optionally relayed through a tunnel CLI (cloudflared or devtunnel), and presented as a QR code.

## Build & Test

```bash
# Build release .app bundle
make                             # outputs output/TunnelMan.app

# Development run (no .app bundle)
make debug
swift run

# Tests (Swift Testing framework — not XCTest)
make test
```

> Tests import `@testable import TunnelManServer` and `TunnelManCore`. Some integration tests start a real PTY and NW listener — avoid running in sandboxed CI environments.

## CI

`.github/workflows/build.yml` runs on every push to `main`. It builds `TunnelMan.app` via `make build` and uploads it as a GitHub Actions artifact named `TunnelMan-{sha}` (retained 90 days). Tests are excluded from CI due to the PTY/NW integration test limitation above — uncomment the test step in the workflow to opt in.

## Architecture

Four Swift package targets, strictly layered:

| Target | Role | Depends on |
|--------|------|------------|
| `TunnelManHelper` | C shim — `openpty` / `fork` via `pty_spawn.c` | (none) |
| `TunnelManCore` | Pure logic — URL parsing, token extraction, WebSocket frame codecs | Foundation, CryptoKit |
| `TunnelManServer` | PTY, HTTP/WebSocket server, tunnel providers, `SessionManager` | Helper + Core |
| `TunnelMan` | SwiftUI app layer, menu bar, popover/settings views | Server |

`TunnelManCore` and `TunnelManServer` have **no AppKit/SwiftUI dependency** — keep it that way so they remain unit-testable.

### Data flow

```
PTYManager (GCD DispatchSource) → onData closure
  → LocalHTTPServer.broadcast() → WebSocketConnection.send()  →  browser xterm.js
Browser keyboard → WebSocketConnection.processFrame() → PTYManager.write() / .resize()
```

`SessionManager` is the single `@MainActor` coordinator: it starts the PTY, server, and tunnel provider in sequence inside a `Task {}`, then subscribes to `TunnelProvider.urlPublisher` / `errorPublisher` (Combine `AnyPublisher`) to drive `@Published` state consumed by SwiftUI views.

**Startup order matters:** PTY → server (blocks on `DispatchSemaphore` until `.ready`) → tunnel provider.

## Conventions

- **No custom `actor` types, no `async/await` chains beyond the single `Task {}` in `SessionManager`** — use GCD (`DispatchSource`, `DispatchQueue`) and Combine for async work.
- **Callbacks, not delegation** — `PTYManager.onData`, `WebSocketConnection.onClose`, `HTTPConnection.onWebSocketUpgrade` are injected closures. Always use `[weak self]` in escaping closures.
- **`os.Logger`** with subsystem `"tunnelman"` and a per-file category — use it in server files.
- **Access control** — `public` only for cross-module APIs; `private(set)` for externally-readable state; everything else `private`.
- **Error handling** — `throws` for synchronous startup failures; Combine publishers for streaming/async errors. No `Result<>` types.
- **Tests** use Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest.

## Key Gotchas

1. **WebSocket is hand-rolled** — `NWProtocolWebSocket` can't be configured per-connection at listener creation, so RFC 6455 framing (SHA-1 handshake via `CryptoKit.Insecure.SHA1`, 3-variant length encoding, 4-byte XOR unmask) is implemented manually in `WebSocketConnection.swift`.

2. **Split WebSocket frames are dropped** — `processFrame` silently discards frames that span two NW receive callbacks. This is intentional simplification; don't assume message reassembly exists.

3. **Semaphore ordering** — in `LocalHTTPServer`, set `stateUpdateHandler` *before* calling `listener.start()`. Reversing the order risks missing the `.ready` event.

4. **DevTunnel exit code 3** = not authenticated. Text heuristics (`"not logged in"`, `"user login"`) are a secondary fallback. `SessionManager` transitions to `.needsDevTunnelLogin` when it receives the sentinel string `"DEVTUNNEL_NOT_LOGGED_IN"` from the provider.

5. **PTY environment** — `TERM=xterm-256color` and `COLORTERM=truecolor` are forced in `pty_spawn.c` for xterm.js compatibility. Don't remove them.

6. **`requiresExternalAuth` redirect** — in DevTunnel mode, unknown HTTP paths redirect to `/terminal?token=…` (not 404) so OAuth callbacks from Microsoft/GitHub don't strand the user.

7. **`LocalProvider` interface selection** — prefers `en*` over `utun*` (VPN), skips `169.254.*` link-local. Logic lives in `LocalProvider.swift`.

## Documentation

Always update `README.md` and `.github/copilot-instructions.md` when making changes that affect build steps, architecture, conventions, project structure, or user-facing behaviour. Keep them consistent with the code.

## Resource Bundle

`terminal.html` (xterm.js frontend) is a SwiftPM processed resource in `TunnelManServer/Resources/`. The `build` target in the `Makefile` copies the generated `.bundle` to the `.app` root so `Bundle.module` resolves it correctly at runtime. If you add new resources, place them under `Sources/TunnelManServer/Resources/` and declare them in `Package.swift` as `.process("Resources")`.
