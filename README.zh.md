<div align="center">

<img src="assets/icon.png" width="140" alt="LiteSSH 图标">

# LiteSSH

**原生 macOS SSH 客户端 — 终端、文件浏览与跨服务器传输集于一窗**

[下载](#下载) · [功能特性](#功能特性) · [快速开始](#快速开始) · [架构设计](#架构设计) · [打包 DMG](#打包-dmg)

[English](README.md) · **中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Español](README.es.md) · [한국어](README.ko.md)

</div>

---

## 下载

[**→ 下载最新版本**](https://github.com/YOUR_USERNAME/LiteSSH/releases/latest)

需要 macOS 13 Ventura 或更高版本。打开 `.dmg`，将 **LiteSSH** 拖入应用程序文件夹即可。

---

## 功能特性

| | |
|---|---|
| **真实终端** | SwiftTerm 驱动，完整 ANSI/VT100 支持，htop、nvtop、vim 正常运行 |
| **文件浏览** | 侧边栏钻入式导航，含地址栏、上一级按钮、新建文件夹 |
| **上传 / 下载** | 拖拽本地文件上传；右键或拖拽远端条目下载——**文件和目录**均支持 |
| **跨服务器传输** | 勾选多个文件/目录 → 右键 → 传输到另一台服务器，实时显示字节进度 |
| **PEM / 私钥认证** | 支持密码、私钥和 AWS `.pem` 文件，口令通过 Keychain 自动供应 |
| **凭据只填一次** | 添加服务器时输入密码或口令，之后连接、浏览、传输全程无需再次输入 |
| **双语界面** | 界面文案跟随系统语言自动切换中文 / 英文 |
| **深色 / 浅色模式** | 终端颜色随系统外观自动切换 |

---

## 快速开始

这是一个纯 **Swift Package**，无需 `.xcodeproj`。

```
1. 用 Xcode 打开 Package.swift
2. 等待依赖解析（SwiftTerm，需访问 github.com）
3. Scheme 选 "LiteSSH" → ▶ Run
4. 点「+」添加服务器——填写主机、端口、用户名和认证信息，只填一次
```

---

## 架构设计

LiteSSH 不自己实现 SSH 协议，而是直接调用 macOS 自带的 OpenSSH（`/usr/bin/ssh`、`/usr/bin/sftp`）。

**连接复用。** 首次连接成为 ControlMaster；后续所有文件操作共享同一个 ControlPath socket，无需再次认证。

**凭据安全。** 密码和口令存储于 macOS 钥匙串。连接时，`AskPassHelper` 生成临时 `SSH_ASKPASS` 脚本，让 ssh/sftp 子进程通过环境变量非交互地取得密码——密码本身不会出现在进程参数里。

**文件传输。** 使用 `sftp -b <batchfile>`（而非 scp），避免含空格路径的解析歧义。目录递归传输用 `get -r` / `put -r`。跨服务器传输通过本地临时目录中转。

**管道安全。** 两条管道（stdout/stderr）在进程运行期间通过 `readabilityHandler` 并发读取，防止 64 KB 管道缓冲区写满导致的死锁——目录递归列表或大批量传输时尤其重要。

---

## 目录结构

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # 服务器配置模型
│   └── RemoteFile.swift             # 远程文件条目
├── Services/
│   ├── SSHConnection.swift          # 连接核心 + ControlMaster 管理
│   ├── ProcessRunner.swift          # 子进程封装（并发管道读取）
│   ├── ProfileStore.swift           # 配置持久化
│   ├── KeychainHelper.swift         # 钥匙串读写
│   └── AskPassHelper.swift          # SSH_ASKPASS 非交互供密
├── ViewModels/
│   ├── SessionStore.swift           # Profile → SSHConnection 映射
│   └── FileBrowserStore.swift       # 文件浏览状态（路径 + 返回栈）
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # 侧边栏：服务器列表 + 文件浏览列
│   │   └── ServerEditView.swift     # 添加 / 编辑服务器表单
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # 跨服务器传输面板
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(中文, English)
└── LiteSSHApp.swift                 # @main 入口 + AppDelegate
```

---

## 打包 DMG

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

在项目根目录输出 `LiteSSH-1.0.dmg` 和 `LiteSSH.app`。脚本会编译 release 二进制、生成应用图标、ad-hoc 签名，并打包含 Applications 快捷方式的 DMG。如需分发给其他人，将 ad-hoc 签名替换为 Developer ID 证书签名。

---

## 依赖

| 依赖 | 版本 | 用途 |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | 终端模拟器 |
| macOS OpenSSH | 系统内置 | SSH / SFTP 协议实现 |
| macOS Keychain | 系统内置 | 凭据安全存储 |

**系统要求：** macOS 13 Ventura 或更高 · Xcode 15+（仅开发时需要）

---

## 许可

Apache 2.0
