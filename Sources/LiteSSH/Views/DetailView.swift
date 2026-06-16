import SwiftUI

/// 选中某个服务器后的右侧主区域：就是一个真终端，点击侧边栏即自动连接。
/// 远程文件浏览挪到了侧边栏每台服务器自己的可展开文件树里（见 ServerListView），
/// 不再占用这里的空间。
struct DetailView: View {
    let profile: ServerProfile
    @ObservedObject var connection: SSHConnection
    let onEdit: () -> Void

    @State private var reconnectToken = UUID()

    var body: some View {
        TerminalContainerView(connection: connection)
            .id(reconnectToken)
            .navigationTitle(profile.name.isEmpty ? profile.host : profile.name)
            .toolbar {
                ToolbarItem {
                    Button(L10n.s("编辑", "Edit"), action: onEdit)
                }
                ToolbarItem {
                    if connection.isConnected {
                        Button(L10n.s("断开", "Disconnect")) {
                            Task {
                                await connection.disconnect()
                                TerminalViewRegistry.shared.discardView(for: profile.id)
                            }
                        }
                    } else {
                        Button(L10n.s("重新连接", "Reconnect")) {
                            TerminalViewRegistry.shared.discardView(for: profile.id)
                            reconnectToken = UUID()
                        }
                        .disabled(connection.isConnecting)
                    }
                }
            }
    }
}
