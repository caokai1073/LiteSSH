import SwiftUI

/// 跨服务器文件传输面板。
///
/// 流程：
///   1. 顶部 Picker 选择目标服务器（自动建立连接）。
///   2. 中间文件浏览区选定目标目录（点击目录钻入，点「↑」上一级）。
///   3. 底部显示目标路径，点「传输」逐文件下载到本机临时目录再上传到目标服务器。
///
/// 目前只支持普通文件，不支持目录（sftp get 不递归）。
struct CrossTransferSheet: View {
    let sourceFiles: [RemoteFile]
    let sourceConnection: SSHConnection

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var selectedProfileID: UUID?
    @State private var destStore: FileBrowserStore?
    /// 从 DestFileBrowserView 通过 Binding 回传的当前路径。
    @State private var destPath: String = ""
    @State private var isTransferring = false
    @State private var progressText = ""
    @State private var transferredBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var transferError: String?
    @State private var showDoneAlert = false

    // 排除自己，只列其他服务器
    private var destProfiles: [ServerProfile] {
        profileStore.profiles.filter { $0.id != sourceConnection.profile.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            serverPicker
            Divider()
            Group {
                if let store = destStore {
                    // 独立 View struct + @ObservedObject 确保 store 变化时重绘。
                    // currentPath binding 把当前路径回传给父视图，驱动 footer 和 canTransfer。
                    DestFileBrowserView(store: store, currentPath: $destPath)
                } else {
                    emptyPrompt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 500, height: 540)
        .alert(L10n.s("传输失败", "Transfer Failed"),
               isPresented: Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })) {
            Button("OK") { transferError = nil }
        } message: {
            Text(transferError ?? "")
        }
        .alert(L10n.s("传输完成", "Transfer Complete"), isPresented: $showDoneAlert) {
            Button(L10n.s("好", "OK")) { dismiss() }
        } message: {
            Text(L10n.s(
                "\(sourceFiles.count) 个文件已成功传输到目标服务器。",
                "\(sourceFiles.count) file(s) transferred successfully."
            ))
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.s("传输到另一台服务器", "Transfer to Another Server"))
                    .font(.headline)
                Text(L10n.s(
                    "\(sourceFiles.count) 个文件，来自「\(sourceConnection.profile.name.isEmpty ? sourceConnection.profile.host : sourceConnection.profile.name)」",
                    "\(sourceFiles.count) file(s) from \"\(sourceConnection.profile.name.isEmpty ? sourceConnection.profile.host : sourceConnection.profile.name)\""
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var serverPicker: some View {
        HStack {
            Text(L10n.s("目标服务器", "Destination"))
                .font(.subheadline)
            Spacer()
            if destProfiles.isEmpty {
                Text(L10n.s("没有其他服务器", "No other servers"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: $selectedProfileID) {
                    Text(L10n.s("选择服务器…", "Select a server…")).tag(Optional<UUID>.none)
                    ForEach(destProfiles) { p in
                        Text(p.name.isEmpty ? p.host : p.name).tag(Optional(p.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .onChange(of: selectedProfileID) { newID in
                    switchDestination(to: newID)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyPrompt: some View {
        if destProfiles.isEmpty {
            Text(L10n.s("请先在左侧添加其他服务器", "Add another server in the sidebar first"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(L10n.s("请选择目标服务器", "Select a destination server above"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if isTransferring {
                if totalBytes > 0 {
                    // 有可计量的文件字节时，显示确定进度条 + 字节数。
                    ProgressView(value: Double(transferredBytes), total: Double(totalBytes))
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 16)
                    HStack(spacing: 8) {
                        Text(progressText)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("\(formatBytes(transferredBytes)) / \(formatBytes(totalBytes))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                } else {
                    // 全部是目录（无法预知字节数）时，显示不定进度条 + 阶段文字。
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 16)
                    Text(progressText)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 8) {
                if !isTransferring, !destPath.isEmpty {
                    Image(systemName: "arrow.down.to.line")
                        .foregroundStyle(.secondary)
                    Text(destPath)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(L10n.s("取消", "Cancel")) { dismiss() }
                    .disabled(isTransferring)
                Button(L10n.s("传输", "Transfer")) { startTransfer() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canTransfer)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var canTransfer: Bool {
        !isTransferring && !sourceFiles.isEmpty && !destPath.isEmpty
    }

    // MARK: - Logic

    private func switchDestination(to profileID: UUID?) {
        destStore = nil
        destPath = ""
        guard let id = profileID,
              let profile = destProfiles.first(where: { $0.id == id }) else { return }
        let conn = sessionStore.connection(for: profile)
        let store = FileBrowserStore(connection: conn)
        store.isLoading = true
        destStore = store
        Task { await store.start() }
    }

    private func startTransfer() {
        guard let store = destStore, !destPath.isEmpty else { return }
        isTransferring = true
        let destPath = self.destPath
        let destConn = store.connection
        let srcConn = sourceConnection
        let files = sourceFiles
        // 目录的 size 是 inode 大小（4 KB 左右），无意义；只累加普通文件的字节数。
        let total = files.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
        totalBytes = total
        transferredBytes = 0

        Task {
            var doneBytes: Int64 = 0
            var failures: [String] = []

            for (index, file) in files.enumerated() {
                // tempDir/filename 结构保证 sftp 和 Finder 看到的名称都是 file.name。
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let tempURL = tempDir.appendingPathComponent(file.name)

                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                    if file.isDirectory {
                        // ── 目录：用 sftp get/put -r，无字节进度，只显示阶段文字 ──────────
                        await MainActor.run {
                            progressText = L10n.s(
                                "下载文件夹 \(index + 1)/\(files.count)：\(file.name)",
                                "Downloading folder \(index + 1)/\(files.count): \(file.name)"
                            )
                        }
                        try await srcConn.download(remotePath: file.fullPath, to: tempURL, recursive: true)

                        await MainActor.run {
                            progressText = L10n.s(
                                "上传文件夹 \(index + 1)/\(files.count)：\(file.name)",
                                "Uploading folder \(index + 1)/\(files.count): \(file.name)"
                            )
                        }
                        try await destConn.upload(localURL: tempURL, to: destPath, recursive: true)

                    } else {
                        // ── 文件：轮询临时文件大小，显示字节进度 ──────────────────────────
                        await MainActor.run {
                            progressText = L10n.s(
                                "下载中 \(index + 1)/\(files.count)：\(file.name)",
                                "Downloading \(index + 1)/\(files.count): \(file.name)"
                            )
                        }
                        let pollTask = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                if Task.isCancelled { break }
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
                                   let sz = attrs[.size] as? Int64 {
                                    await MainActor.run { transferredBytes = doneBytes + sz }
                                }
                            }
                        }
                        try await srcConn.download(remotePath: file.fullPath, to: tempURL)
                        pollTask.cancel()

                        await MainActor.run {
                            transferredBytes = doneBytes + file.size
                            progressText = L10n.s(
                                "上传中 \(index + 1)/\(files.count)：\(file.name)",
                                "Uploading \(index + 1)/\(files.count): \(file.name)"
                            )
                        }
                        try await destConn.upload(localURL: tempURL, to: destPath)
                        doneBytes += file.size
                        await MainActor.run { transferredBytes = doneBytes }
                    }

                } catch {
                    failures.append("\(file.name): \(error.localizedDescription)")
                    if !file.isDirectory {
                        doneBytes += file.size      // 失败文件也计入，避免进度条卡住
                        await MainActor.run { transferredBytes = doneBytes }
                    }
                }
                try? FileManager.default.removeItem(at: tempDir)
            }

            await store.refresh()

            await MainActor.run {
                isTransferring = false
                if failures.isEmpty {
                    showDoneAlert = true
                } else {
                    transferError = failures.joined(separator: "\n")
                }
            }
        }
    }
}

// MARK: - 目标文件浏览器（独立 View struct，确保 @ObservedObject 正确订阅）

/// 目标服务器的文件浏览器。必须是独立 View struct 而不是方法，
/// 这样 @ObservedObject 才能订阅 store 的 @Published 属性，
/// 保证点击目录、上一级等操作后视图能够正确重绘。
private struct DestFileBrowserView: View {
    @ObservedObject var store: FileBrowserStore
    /// 每次 store.path 变化就写回父视图，让父视图的 canTransfer 和 footer 能实时更新。
    @Binding var currentPath: String

    var body: some View {
        VStack(spacing: 0) {
            // 迷你导航栏
            HStack(spacing: 8) {
                Button {
                    Task { await store.goUp() }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoUp || store.isLoading)
                .help(L10n.s("上一级", "Parent Directory"))

                Text(store.path.isEmpty ? "…" : store.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if store.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onChange(of: store.path) { newPath in
                currentPath = newPath   // 路径变化时同步回父视图
            }
            .onAppear {
                currentPath = store.path    // 初次显示时同步一次
            }

            Divider()

            // 文件列表（只能点目录进入，文件行置灰）
            if store.isLoading && store.entries.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let err = store.error, store.entries.isEmpty {
                Spacer()
                Text(err)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
                Spacer()
            } else if store.entries.isEmpty {
                Spacer()
                Text(L10n.s("空文件夹", "Empty Folder"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(store.entries) { file in
                        HStack(spacing: 8) {
                            Image(systemName: file.isDirectory ? "folder.fill" : file.systemIconName)
                                .foregroundStyle(file.isDirectory ? Color.yellow : Color.secondary.opacity(0.4))
                                .frame(width: 18)
                            Text(file.name)
                                .foregroundStyle(file.isDirectory ? Color.primary : Color.secondary.opacity(0.6))
                            Spacer()
                            if file.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard file.isDirectory else { return }
                            Task { await store.enter(file) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
