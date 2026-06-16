import Foundation

/// 一台服务器「进入文件夹浏览」时的状态：不是树，就是当前目录 + 一个上一级路径的栈。
///
/// 点击侧边栏某台服务器行最右边的文件夹图标，就调 `start()`，从根目录开始平铺显示这一层的
/// 文件/文件夹（按名称排序，只看名称）；点列表里的某个目录行调 `enter(_:)` 深入一层；点顶部
/// 「返回」由 ServerListView 直接调 `onExit()` 退出浏览模式换回服务器列表（不再逐级回退）；
/// 「上一级」用 `goUp()` 跳到文件系统意义上的父目录。
///
/// `goBack()`/`parentStack` 是早期「逐级回退」设计留下的浏览历史栈，现在「返回」按钮已经改成
/// 直接退出，不再调用它们，但保留着没删——万一以后想恢复逐级回退体验，浏览历史已经现成可用。
@MainActor
final class FileBrowserStore: ObservableObject {
    @Published var path: String = ""
    @Published var entries: [RemoteFile] = []
    @Published var isLoading = false
    @Published var error: String?

    let connection: SSHConnection
    private var parentStack: [String] = []

    init(connection: SSHConnection) {
        self.connection = connection
    }

    /// 每次进入浏览模式都调一次：清空返回栈，重新从根目录加载（如果还没连接会先自己连）。
    func start() async {
        parentStack = []
        isLoading = true
        defer { isLoading = false }
        if !connection.isConnected {
            await connection.connect()
        }
        guard connection.isConnected, let root = connection.rootPath else {
            error = connection.lastError ?? L10n.s("未连接，请检查服务器设置", "Not connected — check your server settings")
            path = ""
            entries = []
            return
        }
        error = nil
        path = root
        await load(directory: root)
    }

    func refresh() async {
        guard !path.isEmpty else { return }
        await load(directory: path)
    }

    func enter(_ file: RemoteFile) async {
        guard file.isDirectory else { return }
        parentStack.append(path)
        path = file.fullPath
        await load(directory: path)
    }

    /// 返回上一级；已经在根目录时返回 `false`，表示没有上一级了，该退出浏览模式了。
    @discardableResult
    func goBack() async -> Bool {
        guard let previous = parentStack.popLast() else { return false }
        path = previous
        await load(directory: path)
        return true
    }

    /// 当前路径是否还有「上一级目录」可去——到文件系统根 `/` 就到头了。
    var canGoUp: Bool {
        guard !path.isEmpty else { return false }
        return path != "/"
    }

    /// 跳到当前目录的上一级（文件系统意义上的父目录，不是浏览历史）。
    /// 跳之前先试着加载父目录，加载成功才真正切换 path / 入栈——避免半失败状态。
    func goUp() async {
        guard !path.isEmpty, let parent = Self.parentPath(of: path) else { return }
        await goToPath(parent)
    }

    /// 地址栏直接跳转：把输入的路径当成目标目录尝试加载，成功了才提交（path 改变 + 当前
    /// 目录压入返回栈），失败则保持原地并通过 `error` 提示，不破坏现有显示和返回栈。
    func goToPath(_ rawPath: String) async {
        let target = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target != path else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let newEntries = try await connection.listDirectory(at: target)
            parentStack.append(path)
            path = target
            entries = newEntries
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func parentPath(of path: String) -> String? {
        guard path != "/" else { return nil }
        var trimmed = path
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "/" }
        let parent = String(trimmed[..<lastSlash])
        return parent.isEmpty ? "/" : parent
    }

    func createFolder(named name: String) async {
        guard !path.isEmpty else { return }
        do {
            try await connection.createDirectory(at: path, named: name)
            await load(directory: path)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ file: RemoteFile) async {
        do {
            try await connection.delete(path: file.fullPath)
            await load(directory: path)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 上传到当前目录（侧边栏整体拖放区域用）。本地目录自动递归上传。
    func upload(localURL: URL) async {
        guard !path.isEmpty else { return }
        do {
            let isDir = (try? localURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try await connection.upload(localURL: localURL, to: path, recursive: isDir)
            await load(directory: path)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 上传到指定目录——拖到列表里某个子目录行上时用，目标不一定是当前目录。本地目录自动递归上传。
    func upload(localURL: URL, to directory: String) async {
        do {
            let isDir = (try? localURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try await connection.upload(localURL: localURL, to: directory, recursive: isDir)
            if directory == path {
                await load(directory: path)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 远程目录自动用 `get -r` 递归下载。
    func download(_ file: RemoteFile, to localURL: URL) async throws {
        try await connection.download(remotePath: file.fullPath, to: localURL, recursive: file.isDirectory)
    }

    private func load(directory: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await connection.listDirectory(at: directory)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
