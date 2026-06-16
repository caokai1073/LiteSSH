import Foundation
import Combine

/// 管理「每个服务器配置 -> 一个 SSHConnection」的映射，以及侧边栏当前选中的服务器。
@MainActor
final class SessionStore: ObservableObject {

    @Published var selectedProfileID: UUID?
    @Published private(set) var connections: [UUID: SSHConnection] = [:]
    private var fileBrowserStores: [UUID: FileBrowserStore] = [:]

    init() {}

    func connection(for profile: ServerProfile) -> SSHConnection {
        if let existing = connections[profile.id] {
            return existing
        }
        let conn = SSHConnection(profile: profile)
        connections[profile.id] = conn
        return conn
    }

    func existingConnection(for profileID: UUID) -> SSHConnection? {
        connections[profileID]
    }

    /// 每台服务器一个 FileBrowserStore，给侧边栏「点文件夹图标进入浏览」用，生命周期和连接一一对应。
    func fileBrowserStore(for profile: ServerProfile) -> FileBrowserStore {
        if let existing = fileBrowserStores[profile.id] {
            return existing
        }
        let store = FileBrowserStore(connection: connection(for: profile))
        fileBrowserStores[profile.id] = store
        return store
    }

    func removeConnection(for profileID: UUID) {
        if let conn = connections[profileID] {
            Task { await conn.disconnect() }
        }
        connections.removeValue(forKey: profileID)
        fileBrowserStores.removeValue(forKey: profileID)
    }
}
