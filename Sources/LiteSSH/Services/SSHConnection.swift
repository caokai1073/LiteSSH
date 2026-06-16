import Foundation
import Combine

enum SSHConnectionError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}

/// 一个服务器的连接状态 + 操作入口。
///
/// 核心思路：不直接实现 SSH 协议，而是复用 macOS 自带的 OpenSSH 客户端（/usr/bin/ssh /usr/bin/sftp），
/// 通过 ControlMaster/ControlPath 连接复用功能：
///   1. 建立连接时跑一个 ssh 子进程（终端视图里看到的那个，或者后台建立的 master），
///      带上 ControlPath，认证一次。
///   2. 文件列表 / 上传 / 下载 / 打开终端等后续操作，都带上同一个 ControlPath 去跑 ssh / sftp，
///      OpenSSH 会自动复用第 1 步已经认证过的连接，完全不会再认证一次。
///
/// 密码 / 私钥口令在「添加服务器」时输入一次，存进 macOS 钥匙串（KeychainHelper），
/// 之后每次连接通过 SSH_ASKPASS 机制（见 AskPassHelper）自动喂给 ssh/sftp，不需要人在终端里手动输入。
/// host key 确认则用 StrictHostKeyChecking=accept-new 自动放行新主机指纹。
@MainActor
final class SSHConnection: ObservableObject, Identifiable {

    let id: UUID
    let profile: ServerProfile

    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var lastError: String?

    /// 文件树的根目录：优先用配置里的"默认打开的远程目录"，否则用登录后的家目录。
    /// 只有连接建立后才会有值——终端连接（beginMonitoringConnection）或后台连接（connect）
    /// 任意一种途径建立成功都会解析它，侧边栏文件树据此知道从哪个路径开始列目录。
    @Published private(set) var rootPath: String?
    @Published var isTransferring = false

    let controlPath: String

    private var connectMonitorTask: Task<Void, Never>?

    init(profile: ServerProfile) {
        self.profile = profile
        self.id = profile.id
        self.controlPath = SSHConnection.makeControlPath(for: profile.id)
    }

    private static func makeControlPath(for id: UUID) -> String {
        // ControlPath 长度有上限（约 100 字符左右，取决于系统），用短一点的临时目录 + uuid 前 8 位即可。
        // 用 FileManager 的现代 API 而非 NSTemporaryDirectory()，避免触发 FSFindFolder 的系统警告。
        let shortID = id.uuidString.prefix(8)
        let tmpDir = FileManager.default.temporaryDirectory.path
        return tmpDir + "/litessh-\(shortID).sock"
    }

    // MARK: - 公共参数拼装

    private var controlOptions: [String] {
        [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=10m",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10"
        ]
    }

    private var keyOptions: [String] {
        guard profile.authMethod == .privateKey else { return [] }
        let path = profile.privateKeyPath.trimmed
        guard !path.isEmpty else { return [] }
        return ["-i", (path as NSString).expandingTildeInPath]
    }

    private var userHost: String { "\(profile.username)@\(profile.host)" }

    /// 如果 Keychain 里存了这台服务器的密码/私钥口令，就生成带 SSH_ASKPASS 的环境变量，
    /// 让 ssh/sftp 自动取值而不弹交互提示；没存（比如免密钥登录）则返回 nil，用默认环境即可。
    private var authEnvironment: [String: String]? {
        guard let secret = KeychainHelper.read(account: profile.id.uuidString), !secret.isEmpty else {
            return nil
        }
        return AskPassHelper.environment(secret: secret)
    }

    private func sshArguments(extra: [String]) -> [String] {
        controlOptions + ["-p", String(profile.port)] + keyOptions + [userHost] + extra
    }

    private func sftpArguments(batchFilePath: String) -> [String] {
        controlOptions + ["-P", String(profile.port)] + keyOptions + ["-b", batchFilePath, userHost]
    }

    /// 给终端视图用：带 -tt 的交互式 ssh 子进程参数（如果还没有 master 连接，这个进程本身就会成为 master）。
    /// environment 是 "KEY=VALUE" 字符串数组，给 SwiftTerm 的 startProcess 用。
    /// 始终显式传入环境并确保 TERM=xterm-256color，否则从 App Bundle 启动时 TERM 可能未设置，
    /// 导致远端 ssh 会话也没有 TERM，ncurses 程序（htop/nvtop 等）无法正常渲染。
    func terminalLaunchArguments() -> (executable: String, args: [String], environment: [String]?) {
        let args = controlOptions + ["-tt", "-p", String(profile.port)] + keyOptions + [userHost]
        var env = authEnvironment ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        let envArray = env.map { "\($0.key)=\($0.value)" }
        return ("/usr/bin/ssh", args, envArray)
    }

    // MARK: - 连接生命周期

    /// 终端子进程已经 spawn 之后调用：轮询 ControlMaster 是否就绪，就绪后加载初始目录。
    func beginMonitoringConnection() {
        connectMonitorTask?.cancel()
        isConnecting = true
        lastError = nil
        // 把所有状态变更都放进一个属于这个 @MainActor 类自己的 async 方法里（monitorUntilConnected），
        // 而不是直接写在 Task{} 闭包里——这样不管闭包本身的隔离推断结果如何，
        // 方法体本身一定在 MainActor 上执行，行为是确定的。
        connectMonitorTask = Task { [weak self] in
            await self?.monitorUntilConnected()
        }
    }

    private func monitorUntilConnected() async {
        for _ in 0..<24 { // 最多等待约 12 秒
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await checkAlive() {
                isConnected = true
                isConnecting = false
                await resolveRootPathIfNeeded()
                return
            }
        }
        if !Task.isCancelled, !isConnected {
            isConnecting = false
            lastError = L10n.s("连接超时，请检查地址/端口/账号信息，或确认终端里是否需要手动确认提示", "Connection timed out — check the address/port/account info, or see if the terminal needs manual confirmation")
        }
    }

    /// 不打开终端、纯后台建立 ControlMaster 连接——给侧边栏文件树用：用户展开某台服务器的
    /// 文件树时，如果还没连接过，就调这个方法，不需要先打开终端。
    /// 用 `-N -f`：ssh 认证成功后自己 fork 到后台保持连接（成为 ControlMaster），不执行任何
    /// 远程命令、不占用终端；父进程认证完就退出，配合 ProcessRunner 的等待退出语义正好契合。
    func connect() async {
        guard !isConnected, !isConnecting else { return }
        isConnecting = true
        lastError = nil
        let args = controlOptions + ["-N", "-f", "-p", String(profile.port)] + keyOptions + [userHost]
        do {
            let result = try await ProcessRunner.run(
                executable: "/usr/bin/ssh",
                arguments: args,
                environment: authEnvironment,
                timeout: 15
            )
            guard result.succeeded else {
                isConnecting = false
                lastError = result.stderr.trimmed.isEmpty ? L10n.s("连接失败（exit \(result.exitCode)）", "Connection failed (exit \(result.exitCode))") : result.stderr.trimmed
                return
            }
            isConnected = true
            isConnecting = false
            await resolveRootPathIfNeeded()
        } catch {
            isConnecting = false
            lastError = error.localizedDescription
        }
    }

    private func resolveRootPathIfNeeded() async {
        guard rootPath == nil else { return }
        let configured = profile.remoteStartPath.trimmed
        if !configured.isEmpty {
            rootPath = configured
            return
        }
        let home = try? await runRemote("pwd").trimmed
        rootPath = (home?.isEmpty == false) ? home : "/"
    }

    func checkAlive() async -> Bool {
        let args = controlOptions + ["-O", "check", "-p", String(profile.port), userHost]
        guard let result = try? await ProcessRunner.run(executable: "/usr/bin/ssh", arguments: args, environment: authEnvironment) else {
            return false
        }
        return result.succeeded
    }

    /// 终端子进程退出时调用（用户输入 exit，或者认证失败进程直接退出等）。
    func markProcessTerminated() {
        connectMonitorTask?.cancel()
        isConnecting = false
        isConnected = false
        rootPath = nil
    }

    func disconnect() async {
        connectMonitorTask?.cancel()
        let args = controlOptions + ["-O", "exit", "-p", String(profile.port), userHost]
        _ = try? await ProcessRunner.run(executable: "/usr/bin/ssh", arguments: args, environment: authEnvironment)
        isConnected = false
        isConnecting = false
        rootPath = nil
    }

    // MARK: - 远程命令 / 文件浏览

    private func runRemote(_ remoteCommand: String) async throws -> String {
        let args = sshArguments(extra: [remoteCommand])
        let result = try await ProcessRunner.run(executable: "/usr/bin/ssh", arguments: args, environment: authEnvironment)
        guard result.succeeded else {
            let message = result.stderr.trimmed.isEmpty ? L10n.s("命令执行失败（exit \(result.exitCode)）", "Command failed (exit \(result.exitCode))") : result.stderr.trimmed
            throw SSHConnectionError.commandFailed(message)
        }
        return result.stdout
    }

    /// 列出某个路径下的一级条目，给侧边栏文件树用——树里每个目录节点展开时都会带着
    /// 自己的 fullPath 调一次这个方法，不再有"当前目录"的全局概念。
    func listDirectory(at path: String) async throws -> [RemoteFile] {
        let quoted = ProcessRunner.shellQuote(path)
        let cmd = "find \(quoted) -mindepth 1 -maxdepth 1 -printf '%f\\t%y\\t%s\\t%T@\\n' 2>/dev/null"
        let output = try await runRemote(cmd)
        var parsed = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { RemoteFile.parse(line: String($0), parentPath: path) }
        parsed.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return parsed
    }

    func createDirectory(at parentPath: String, named name: String) async throws {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }
        let newPath = parentPath.hasSuffix("/") ? parentPath + trimmedName : parentPath + "/" + trimmedName
        _ = try await runRemote("mkdir -p \(ProcessRunner.shellQuote(newPath))")
    }

    func delete(path: String) async throws {
        _ = try await runRemote("rm -rf \(ProcessRunner.shellQuote(path))")
    }

    // MARK: - 上传 / 下载（走 sftp batch 模式，避免 scp 对带空格路径的处理歧义）

    /// `recursive: true` 时用 `put -r`，支持整个目录递归上传。
    func upload(localURL: URL, to remoteDirectory: String, recursive: Bool = false) async throws {
        isTransferring = true
        defer { isTransferring = false }
        let remoteName = localURL.lastPathComponent
        let remotePath = remoteDirectory.hasSuffix("/") ? remoteDirectory + remoteName : remoteDirectory + "/" + remoteName
        let flag = recursive ? "-r " : ""
        try await runSFTPBatch("put \(flag)\(sftpQuote(localURL.path)) \(sftpQuote(remotePath))")
    }

    /// `recursive: true` 时用 `get -r`，支持整个目录递归下载。
    /// `localURL` 应指向目标路径（不需要预先存在）；sftp 会自动创建目录。
    func download(remotePath: String, to localURL: URL, recursive: Bool = false) async throws {
        isTransferring = true
        defer { isTransferring = false }
        let flag = recursive ? "-r " : ""
        try await runSFTPBatch("get \(flag)\(sftpQuote(remotePath)) \(sftpQuote(localURL.path))")
    }

    private func sftpQuote(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func runSFTPBatch(_ command: String) async throws {
        let batchFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".litessh-batch")
        try command.write(to: batchFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: batchFile) }

        let args = sftpArguments(batchFilePath: batchFile.path)
        let result = try await ProcessRunner.run(executable: "/usr/bin/sftp", arguments: args, environment: authEnvironment)
        guard result.succeeded else {
            let message = result.stderr.trimmed.isEmpty ? result.stdout.trimmed : result.stderr.trimmed
            throw SSHConnectionError.commandFailed(message.isEmpty ? L10n.s("传输失败（exit \(result.exitCode)）", "Transfer failed (exit \(result.exitCode))") : message)
        }
    }
}
