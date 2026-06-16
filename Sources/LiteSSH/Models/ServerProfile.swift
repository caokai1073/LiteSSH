import Foundation

/// 登录认证方式
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password = "password"
    case privateKey = "privateKey"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return L10n.s("密码", "Password")
        case .privateKey: return L10n.s("SSH 密钥", "SSH Key")
        }
    }
}

/// 一个已保存的服务器连接配置。
/// 密码 / 密钥口令（passphrase）不会存在这个结构体里，而是单独存在 macOS 钥匙串（Keychain）中，
/// 通过 `id` 关联，避免明文密码被写进 JSON 配置文件。
struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMethod: AuthMethod = .password
    /// 私钥文件路径，例如 ~/.ssh/id_ed25519。仅在 authMethod == .privateKey 时使用。
    var privateKeyPath: String = ""
    /// 上次连接成功使用过的初始远程目录（可选，留空则使用登录后的家目录）。
    var remoteStartPath: String = ""

    var isValid: Bool {
        !name.trimmed.isEmpty && !host.trimmed.isEmpty && !username.trimmed.isEmpty &&
        (authMethod == .password || !privateKeyPath.trimmed.isEmpty)
    }

    var subtitle: String {
        "\(username)@\(host):\(port)"
    }

    static func newDraft() -> ServerProfile {
        var profile = ServerProfile()
        profile.privateKeyPath = ("~/.ssh/id_ed25519" as NSString).expandingTildeInPath
        return profile
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
