import SwiftUI
import AppKit

/// 添加/编辑一个服务器配置。
///
/// 密码 / 私钥口令在这里输入一次，存进 macOS 钥匙串（KeychainHelper，用 profile.id 关联，
/// 绝不写进 JSON 配置文件）。以后连接时通过 SSH_ASKPASS 机制自动喂给 ssh/sftp，
/// 不需要每次在终端里手动输入。
struct ServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileStore: ProfileStore

    @State private var profile: ServerProfile
    @State private var secret: String
    let isNew: Bool

    init(initialProfile: ServerProfile, isNew: Bool) {
        _profile = State(initialValue: initialProfile)
        _secret = State(initialValue: KeychainHelper.read(account: initialProfile.id.uuidString) ?? "")
        self.isNew = isNew
    }

    /// 密码登录必须填密码；私钥登录的口令是可选的（很多私钥没有设口令）。
    private var canSave: Bool {
        profile.isValid && (profile.authMethod == .privateKey || !secret.trimmed.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.s("基本信息", "Basic Info")) {
                    TextField(L10n.s("名称", "Name"), text: $profile.name, prompt: Text(L10n.s("例如：我的服务器", "e.g. My Server")))
                    TextField(L10n.s("主机地址", "Host"), text: $profile.host, prompt: Text(L10n.s("example.com 或 IP", "example.com or IP")))
                    TextField(L10n.s("端口", "Port"), value: $profile.port, formatter: NumberFormatter())
                    TextField(L10n.s("用户名", "Username"), text: $profile.username)
                }

                Section(L10n.s("认证方式", "Authentication")) {
                    Picker(L10n.s("方式", "Method"), selection: $profile.authMethod) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if profile.authMethod == .privateKey {
                        HStack {
                            TextField(
                                L10n.s("私钥或 PEM 文件路径", "Private key or PEM file path"),
                                text: $profile.privateKeyPath,
                                prompt: Text(L10n.s("~/.ssh/id_ed25519 或 key.pem", "~/.ssh/id_ed25519 or key.pem"))
                            )
                            Button(L10n.s("选择…", "Choose…")) { pickPrivateKeyFile() }
                        }
                        SecureField(L10n.s("私钥口令（没有就留空）", "Key passphrase (leave blank if none)"), text: $secret)
                        Text(L10n.s("支持 OpenSSH 格式私钥及 PEM 文件（如 AWS .pem）。口令会保存到 macOS 钥匙串，连接时自动填入。", "Supports OpenSSH private keys and PEM files (e.g. AWS .pem). The passphrase is saved to the macOS Keychain and filled in automatically."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField(L10n.s("密码", "Password"), text: $secret)
                        Text(L10n.s("密码会保存到 macOS 钥匙串，连接时自动填入，不用每次手动输入。", "The password is saved to the macOS Keychain and filled in automatically when connecting — no need to type it every time."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L10n.s("可选", "Optional")) {
                    TextField(L10n.s("默认打开的远程目录", "Default remote directory"), text: $profile.remoteStartPath, prompt: Text(L10n.s("留空 = 登录后的家目录", "Leave blank for home directory after login")))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L10n.s("取消", "Cancel")) { dismiss() }
                Button(isNew ? L10n.s("添加", "Add") : L10n.s("保存", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 460, height: 480)
    }

    private func save() {
        if isNew {
            profileStore.add(profile)
        } else {
            profileStore.update(profile)
        }
        let trimmedSecret = secret.trimmed
        if trimmedSecret.isEmpty {
            KeychainHelper.delete(account: profile.id.uuidString)
        } else {
            KeychainHelper.save(account: profile.id.uuidString, secret: trimmedSecret)
        }
        dismiss()
    }

    private func pickPrivateKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.message = L10n.s("选择私钥或 PEM 文件", "Select a private key or PEM file")
        // 如果已经填了路径就从那个目录开始，否则优先 ~/.ssh，再退到家目录。
        let home = FileManager.default.homeDirectoryForCurrentUser
        let existing = profile.privateKeyPath.trimmed
        if !existing.isEmpty {
            let existingURL = URL(fileURLWithPath: (existing as NSString).expandingTildeInPath)
            panel.directoryURL = existingURL.deletingLastPathComponent()
        } else {
            let sshDir = home.appendingPathComponent(".ssh")
            panel.directoryURL = FileManager.default.fileExists(atPath: sshDir.path) ? sshDir : home
        }
        if panel.runModal() == .OK, let url = panel.url {
            profile.privateKeyPath = url.path
        }
    }
}
