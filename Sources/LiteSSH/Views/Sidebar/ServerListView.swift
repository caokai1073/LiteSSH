import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// .sheet(item:) 的载体——把要传输的文件和源连接打包成一个 Identifiable 值，
/// 保证 sheet content 在 item 赋值时才求值，不会捕获到初始空数组。
private struct TransferRequest: Identifiable {
    let id = UUID()
    let files: [RemoteFile]
    let connection: SSHConnection
}

/// 侧边栏顶层视图：默认显示服务器列表；点某一行最右边的文件夹图标后，
/// 整个侧边栏切换成那台服务器「当前目录」的平铺文件列表（见 FileBrowserColumn），
/// 点目录行钻进下一层；点顶部「返回」直接退出换回服务器列表；点「上一级」回到文件系统父目录。
struct ServerListView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var editingProfile: ServerProfile?
    @Binding var showingEditor: Bool

    @State private var deletingProfile: ServerProfile?
    @State private var browsingProfile: ServerProfile?

    var body: some View {
        Group {
            if let profile = browsingProfile {
                FileBrowserColumn(
                    profile: profile,
                    store: sessionStore.fileBrowserStore(for: profile),
                    onExit: { browsingProfile = nil }
                )
            } else {
                serverList
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if browsingProfile == nil {
                ToolbarItem {
                    Button {
                        editingProfile = nil
                        showingEditor = true
                    } label: {
                        Label(L10n.s("添加服务器", "Add Server"), systemImage: "plus")
                    }
                    .help(L10n.s("添加服务器", "Add Server"))
                }
            }
        }
        .frame(minWidth: 260)
        .alert(
            L10n.s("确定删除「\(deletingProfile?.name ?? "")」？", "Delete \"\(deletingProfile?.name ?? "")\"?"),
            isPresented: Binding(
                get: { deletingProfile != nil },
                set: { if !$0 { deletingProfile = nil } }
            )
        ) {
            Button(L10n.s("删除", "Delete"), role: .destructive) {
                if let profile = deletingProfile {
                    sessionStore.removeConnection(for: profile.id)
                    profileStore.delete(profile)
                    if sessionStore.selectedProfileID == profile.id {
                        sessionStore.selectedProfileID = nil
                    }
                    if browsingProfile?.id == profile.id {
                        browsingProfile = nil
                    }
                }
                deletingProfile = nil
            }
            Button(L10n.s("取消", "Cancel"), role: .cancel) {
                deletingProfile = nil
            }
        }
    }

    private var navigationTitle: String {
        guard let profile = browsingProfile else { return "LiteSSH" }
        return profile.name.isEmpty ? profile.host : profile.name
    }

    private var serverList: some View {
        List(selection: $sessionStore.selectedProfileID) {
            ForEach(profileStore.profiles) { profile in
                ServerRow(profile: profile, onBrowse: { browsingProfile = profile })
                    .tag(profile.id)
                    .contextMenu {
                        Button(L10n.s("编辑…", "Edit…")) {
                            editingProfile = profile
                            showingEditor = true
                        }
                        Button(L10n.s("浏览文件", "Browse Files")) {
                            browsingProfile = profile
                        }
                        Button(L10n.s("删除", "Delete"), role: .destructive) {
                            deletingProfile = profile
                        }
                    }
            }
            .onMove { source, destination in
                profileStore.move(fromOffsets: source, toOffset: destination)
            }
        }
        .overlay {
            if profileStore.profiles.isEmpty {
                ContentUnavailableViewCompat()
            }
        }
    }
}

/// 服务器列表里的一行：状态点 + 名称/地址，最右边贴边一个文件夹图标按钮，点它进入文件浏览。
/// 这个图标走的是独立的 Button，跟 List 自带的整行选中手势不会打架——点行里其它地方仍然
/// 走 List(selection:) 默认的选中逻辑（驱动右侧终端自动连接），点 Button 只会触发 onBrowse。
private struct ServerRow: View {
    @EnvironmentObject var sessionStore: SessionStore
    let profile: ServerProfile
    let onBrowse: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 用独立的 ConnectionStatusDot 直接订阅 SSHConnection，
            // 保证 isConnected / isConnecting 变化时这一行能立即刷新。
            if let conn = sessionStore.existingConnection(for: profile.id) {
                ConnectionStatusDot(connection: conn)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name.isEmpty ? profile.host : profile.name)
                    .font(.body)
                Text(profile.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onBrowse) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.s("浏览文件", "Browse Files"))
        }
        .padding(.vertical, 2)
    }
}

/// 状态指示点：直接用 @ObservedObject 订阅 SSHConnection，
/// 这样 isConnected / isConnecting 的任何变化都会触发这个 View 重绘，
/// 而不依赖 SessionStore 是否重新发布。
private struct ConnectionStatusDot: View {
    @ObservedObject var connection: SSHConnection

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        if connection.isConnected { return .green }
        if connection.isConnecting { return .orange }
        return .gray.opacity(0.25)
    }
}

/// 点了某台服务器的文件夹图标后，整个侧边栏换成这个视图：顶部「返回 / 新建文件夹 / 刷新」
/// 加当前路径，下面是当前目录的平铺列表（按名称排序，只显示名称），点目录行钻进下一层。
private struct FileBrowserColumn: View {
    let profile: ServerProfile
    @ObservedObject var store: FileBrowserStore
    let onExit: () -> Void

    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingDelete: RemoteFile?
    @State private var isDropTargeted = false
    @State private var addressBarText = ""
    /// 当前选中的文件 ID（fullPath），只含普通文件，不含目录。
    @State private var selection: Set<String> = []
    /// 非 nil 时弹出传输面板。用 item 而不是 isPresented+单独数组，
    /// 保证 sheet content 在 item 设置时才求值，避免捕获到初始空数组。
    @State private var transferRequest: TransferRequest? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .task {
            await store.start()
        }
        .onChange(of: store.path) { newPath in
            addressBarText = newPath
            selection.removeAll()   // 切换目录时清空选择
        }
        .sheet(item: $transferRequest) { req in
            CrossTransferSheet(
                sourceFiles: req.files,
                sourceConnection: req.connection
            )
            .environmentObject(sessionStore)
            .environmentObject(profileStore)
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !store.path.isEmpty else { return false }
            handleDrop(providers: providers, into: store.path)
            return true
        }
        .alert(L10n.s("新建文件夹", "New Folder"), isPresented: $showingNewFolder) {
            TextField(L10n.s("文件夹名称", "Folder Name"), text: $newFolderName)
            Button(L10n.s("创建", "Create")) {
                let name = newFolderName
                newFolderName = ""
                Task { await store.createFolder(named: name) }
            }
            Button(L10n.s("取消", "Cancel"), role: .cancel) { newFolderName = "" }
        }
        .alert(
            L10n.s("确定删除「\(pendingDelete?.name ?? "")」？此操作不可恢复。", "Delete \"\(pendingDelete?.name ?? "")\"? This cannot be undone."),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(L10n.s("删除", "Delete"), role: .destructive) {
                if let file = pendingDelete {
                    Task { await store.delete(file) }
                }
                pendingDelete = nil
            }
            Button(L10n.s("取消", "Cancel"), role: .cancel) { pendingDelete = nil }
        }
        .alert(
            L10n.s("操作失败", "Operation Failed"),
            isPresented: Binding(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )
        ) {
            Button(L10n.s("好", "OK")) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    onExit()
                } label: {
                    Label(L10n.s("返回", "Back"), systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .help(L10n.s("返回服务器列表", "Back to server list"))

                Spacer()

                if store.isLoading {
                    ProgressView().controlSize(.small)
                }

                // 有文件/目录被选中时，显示「传输」按钮（文件和目录都支持传输）。
                if !selection.isEmpty {
                    Button {
                        let files = store.entries.filter { selection.contains($0.id) }
                        guard !files.isEmpty else { return }
                        transferRequest = TransferRequest(files: files, connection: store.connection)
                    } label: {
                        Label(
                            L10n.s("传输 \(selection.count) 个", "Transfer \(selection.count)"),
                            systemImage: "arrow.triangle.swap"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("传输选中文件到另一台服务器", "Transfer selected files to another server"))
                }

                Button {
                    Task { await store.goUp() }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoUp)
                .help(L10n.s("上一级目录", "Parent Directory"))

                Button {
                    newFolderName = ""
                    showingNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .disabled(store.path.isEmpty)
                .help(L10n.s("新建文件夹", "New Folder"))

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(store.path.isEmpty)
                .help(L10n.s("刷新", "Refresh"))
            }

            Text(profile.name.isEmpty ? profile.host : profile.name)
                .font(.headline)
                .lineLimit(1)

            addressBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// 地址栏：显示并可编辑当前路径，回车或点箭头按钮直接跳转到输入的路径。
    private var addressBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField(L10n.s("输入路径后回车跳转", "Type a path and press Return"), text: $addressBarText)
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .disabled(store.path.isEmpty)
                .onSubmit { navigateToAddressBar() }

            Button {
                navigateToAddressBar()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(store.path.isEmpty || addressBarText.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(L10n.s("跳转到输入的路径", "Go to typed path"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func navigateToAddressBar() {
        let target = addressBarText
        Task { await store.goToPath(target) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.entries.isEmpty && store.error == nil {
            centeredMessage { ProgressView() }
        } else if let error = store.error, store.entries.isEmpty {
            centeredMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        } else if store.entries.isEmpty {
            centeredMessage {
                Text(L10n.s("空文件夹", "Empty Folder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            List {
                ForEach(store.entries) { file in
                    FileBrowserRow(
                        file: file,
                        isSelected: selection.contains(file.id),
                        onEnter: { Task { await store.enter(file) } },
                        onDownload: { downloadWithPanel(file) },
                        onDelete: { pendingDelete = file },
                        onUpload: { providers in handleDrop(providers: providers, into: file.fullPath) },
                        onDownloadDrag: { makeDragItemProvider(for: file) },
                        onToggleSelect: {
                            if selection.contains(file.id) { selection.remove(file.id) }
                            else { selection.insert(file.id) }
                        },
                        onTransfer: {
                            transferRequest = TransferRequest(files: [file], connection: store.connection)
                        }
                    )
                }
            }
            .listStyle(.plain)
        }
    }

    private func centeredMessage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider], into directory: String) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await store.upload(localURL: url, to: directory)
                }
            }
        }
    }

    /// 拖拽下载：文件和目录都支持。
    /// 用 tempParent/filename 结构保证拖到 Finder 后文件名正确（lastPathComponent = file.name）。
    private func makeDragItemProvider(for file: RemoteFile) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = file.name
        let typeID = file.isDirectory ? UTType.folder.identifier : UTType.data.identifier
        provider.registerFileRepresentation(
            forTypeIdentifier: typeID,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let tempParent = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let tempURL = tempParent.appendingPathComponent(file.name)
            try? FileManager.default.createDirectory(at: tempParent, withIntermediateDirectories: true)
            Task {
                do {
                    try await store.download(file, to: tempURL)
                    completion(tempURL, true, nil)
                } catch {
                    completion(nil, false, error)
                    await MainActor.run { store.error = error.localizedDescription }
                }
            }
            return nil
        }
        return provider
    }

    private func downloadWithPanel(_ file: RemoteFile) {
        if file.isDirectory {
            // 目录：让用户选择一个父文件夹，然后把远端目录下载进去。
            let panel = NSOpenPanel()
            panel.message = L10n.s(
                "选择保存「\(file.name)」的位置",
                "Choose where to save the folder \"\(file.name)\""
            )
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = L10n.s("保存到此处", "Save Here")
            guard panel.runModal() == .OK, let parent = panel.url else { return }
            let dest = parent.appendingPathComponent(file.name, isDirectory: true)
            Task {
                do {
                    try await store.download(file, to: dest)
                } catch {
                    await MainActor.run { store.error = error.localizedDescription }
                }
            }
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task {
                do {
                    try await store.download(file, to: url)
                } catch {
                    await MainActor.run { store.error = error.localizedDescription }
                }
            }
        }
    }
}

/// 平铺列表里的一行：展示用 RemoteFileRow（只显示图标+名称），叠加交互——
/// 点目录行钻进去、点文件左侧复选框勾选、右键下载/传输/删除、拖出下载、拖文件进目录上传。
private struct FileBrowserRow: View {
    let file: RemoteFile
    var isSelected: Bool = false
    let onEnter: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onUpload: ([NSItemProvider]) -> Void
    let onDownloadDrag: () -> NSItemProvider
    /// nil 表示该行不可选（目录）。
    var onToggleSelect: (() -> Void)? = nil
    /// nil 表示该行不支持传输（目录）。
    var onTransfer: (() -> Void)? = nil

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // 复选框：只对普通文件显示，hover 时才完全可见（已选中时始终显示）。
            if let toggle = onToggleSelect {
                Button(action: toggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered || isSelected ? 0.6 : 0))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .frame(width: 18)
            } else {
                Color.clear.frame(width: 18)
            }

            RemoteFileRow(file: file)
        }
        .contentShape(Rectangle())
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture {
            if file.isDirectory { onEnter() }
        }
        .contextMenu {
            if file.isDirectory {
                Button(L10n.s("打开", "Open")) { onEnter() }
                Button(L10n.s("下载文件夹到…", "Download Folder to…")) { onDownload() }
                if let transfer = onTransfer {
                    Divider()
                    Button(L10n.s("传输到另一台服务器…", "Transfer to Another Server…")) { transfer() }
                }
            } else {
                Button(L10n.s("下载到…", "Download to…")) { onDownload() }
                if let transfer = onTransfer {
                    Divider()
                    Button(L10n.s("传输到另一台服务器…", "Transfer to Another Server…")) { transfer() }
                }
            }
            Button(L10n.s("删除", "Delete"), role: .destructive) { onDelete() }
        }
        .onDrag(onDownloadDrag)
        .modifier(DropIntoDirectory(isDirectory: file.isDirectory, isTargeted: $isDropTargeted, action: onUpload))
    }
}

/// 只有目录才接受拖放上传；普通文件行不响应 onDrop，避免和列表整体的拖放区域产生歧义。
private struct DropIntoDirectory: ViewModifier {
    let isDirectory: Bool
    @Binding var isTargeted: Bool
    let action: ([NSItemProvider]) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDirectory {
            content.onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                action(providers)
                return true
            }
        } else {
            content
        }
    }
}

/// 兼容写法：避免依赖某个特定 macOS 版本才有的 ContentUnavailableView。
private struct ContentUnavailableViewCompat: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(L10n.s("还没有服务器", "No Servers Yet"))
                .font(.headline)
            Text(L10n.s("点击左上角「+」添加一个", "Click the \"+\" in the top-left to add one"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
