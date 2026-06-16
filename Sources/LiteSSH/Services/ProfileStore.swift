import Foundation
import Combine

/// 负责服务器配置列表的增删改 + 落盘持久化（JSON 文件，存放在
/// ~/Library/Application Support/LiteSSH/profiles.json）。
/// 密码/密钥口令不在这里，见 KeychainHelper。
@MainActor
final class ProfileStore: ObservableObject {

    @Published private(set) var profiles: [ServerProfile] = []

    private let fileURL: URL

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiteSSH", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.fileURL = supportDir.appendingPathComponent("profiles.json")
        load()
    }

    func add(_ profile: ServerProfile) {
        profiles.append(profile)
        persist()
    }

    func update(_ profile: ServerProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persist()
    }

    func delete(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainHelper.delete(account: profile.id.uuidString)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.litessh.encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static let litessh: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
