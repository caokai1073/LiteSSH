<div align="center">

<img src="assets/icon.png" width="140" alt="LiteSSH icon">

# LiteSSH

**Native macOS SSH client — terminal, file browser & cross-server transfer in one window**

[Download](#download) · [Features](#features) · [Quick Start](#quick-start) · [Architecture](#architecture) · [Build DMG](#build-dmg)

**English** · [中文](README.zh.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Español](README.es.md) · [한국어](README.ko.md)

</div>

---

## Download

[**→ Download Latest Release**](https://github.com/YOUR_USERNAME/LiteSSH/releases/latest)

Requires macOS 13 Ventura or later. Open the `.dmg` and drag **LiteSSH** to Applications.

---

## Features

| | |
|---|---|
| **Full terminal** | SwiftTerm-powered, full ANSI/VT100 — htop, nvtop, vim all work |
| **File browser** | Sidebar drill-in navigation with address bar, up-level button, new folder |
| **Upload / Download** | Drag local files to upload; right-click or drag remote items to download — files and **folders** both supported |
| **Cross-server transfer** | Check multiple files/folders → right-click → transfer to another server with live progress |
| **PEM / private key auth** | Password, private key, and AWS `.pem` — passphrase auto-supplied from Keychain |
| **One-time credential entry** | Enter password or passphrase once when adding a server; never prompted again |
| **Bilingual UI** | Interface language follows the system locale (Chinese / English) |
| **Dark / Light mode** | Terminal colours adapt to system appearance automatically |

---

## Quick Start

This is a pure **Swift Package** — no `.xcodeproj` needed.

```
1. Open Package.swift in Xcode
2. Wait for dependency resolution  (SwiftTerm — requires github.com access)
3. Select the "LiteSSH" scheme → ▶ Run
4. Click "+" to add a server — fill in host, port, username, and credentials once
```

---

## Architecture

LiteSSH does not implement SSH itself. It delegates to the system's built-in OpenSSH (`/usr/bin/ssh`, `/usr/bin/sftp`).

**Connection reuse.** The first connection becomes a ControlMaster; all subsequent file operations share the same ControlPath socket — no re-authentication.

**Credential security.** Passwords and passphrases are stored in the macOS Keychain. At runtime, `AskPassHelper` provides a temporary `SSH_ASKPASS` script so the ssh/sftp subprocess retrieves the secret from an environment variable — it never appears in process arguments.

**File transfer.** Uses `sftp -b <batchfile>` (not scp) to avoid path-parsing issues with spaces. Recursive directory transfer uses `get -r` / `put -r`. Cross-server transfer pipes through a local temp directory.

**Pipe safety.** Both stdout and stderr pipes are drained concurrently via `readabilityHandler` during process execution, preventing the 64 KB pipe-buffer deadlock that would otherwise affect large directory listings or recursive transfers.

---

## Project Structure

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # Server config model
│   └── RemoteFile.swift             # Remote file entry
├── Services/
│   ├── SSHConnection.swift          # Core connection + ControlMaster management
│   ├── ProcessRunner.swift          # Subprocess wrapper (concurrent pipe reads)
│   ├── ProfileStore.swift           # Config persistence
│   ├── KeychainHelper.swift         # Keychain read/write
│   └── AskPassHelper.swift          # SSH_ASKPASS non-interactive credential supply
├── ViewModels/
│   ├── SessionStore.swift           # Profile → SSHConnection map
│   └── FileBrowserStore.swift       # File browser state (path + back stack)
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # Sidebar: server list + file browser column
│   │   └── ServerEditView.swift     # Add / edit server form
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # Cross-server transfer UI
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(Chinese, English)
└── LiteSSHApp.swift                 # @main entry point + AppDelegate
```

---

## Build DMG

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

Outputs `LiteSSH-1.0.dmg` and `LiteSSH.app` in the project root. The script builds a release binary, generates the app icon, signs ad-hoc, and packages with an Applications symlink. For distribution to other machines, replace the ad-hoc sign step with a Developer ID certificate.

---

## Dependencies

| Dependency | Version | Role |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | Terminal emulator |
| macOS OpenSSH | Built-in | SSH / SFTP protocol |
| macOS Keychain | Built-in | Secure credential storage |

**Requirements:** macOS 13 Ventura or later · Xcode 15+ (development only)

---

## License

Apache 2.0
