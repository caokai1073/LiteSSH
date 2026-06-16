import Foundation
import AppKit
import SwiftTerm

// ⚠️ 这个文件直接对接 SwiftTerm 库。如果 Xcode 编译报错在这里，大概率是 SwiftTerm
// 随版本更新调整了 LocalProcessTerminalView / LocalProcessTerminalViewDelegate 的方法签名
// 或 startProcess 的参数名。把报错贴给我，或对照
// https://github.com/migueldeicaza/SwiftTerm 仓库里的示例 App（TerminalApp 目标）改一下
// 这一个文件即可，其余文件不受影响。

/// SwiftUI 在用户来回切换侧边栏选中项时，会反复创建/销毁 NSViewRepresentable，
/// 但我们不希望每次切换都重新 spawn 一个新的 ssh 进程（那样旧的终端状态/连接就丢了）。
/// 这里用一个简单的全局缓存：每个连接（profile id）只创建一次真正的终端 NSView + ssh 进程，
/// 之后无论 SwiftUI 怎么重建包装视图，都拿回同一个实例。
@MainActor
final class TerminalViewRegistry {
    static let shared = TerminalViewRegistry()

    private var views: [UUID: LocalProcessTerminalView] = [:]
    private var coordinators: [UUID: TerminalProcessCoordinator] = [:]

    private init() {}

    func terminalView(for connection: SSHConnection) -> LocalProcessTerminalView {
        if let existing = views[connection.id] {
            return existing
        }

        // 用一个合理的默认尺寸初始化，避免 frame: .zero 时 pty 以 0×0 协商给远端，
        // 导致 htop/nvtop 等 ncurses 程序启动时拿到空尺寸、渲染出错。
        // SwiftUI 布局完成后会触发 sizeChanged → pty 再次 resize → 远端收到 window-change。
        let defaultFrame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let view = LocalProcessTerminalView(frame: defaultFrame)
        let coordinator = TerminalProcessCoordinator(connection: connection)
        view.processDelegate = coordinator
        coordinators[connection.id] = coordinator

        let (executable, args, environment) = connection.terminalLaunchArguments()
        view.startProcess(executable: executable, args: args, environment: environment)
        connection.beginMonitoringConnection()

        views[connection.id] = view
        return view
    }

    /// 用户主动点击"断开连接"时调用：丢弃缓存的终端视图，下次连接会重新 spawn 一个全新的 ssh 进程。
    func discardView(for profileID: UUID) {
        views.removeValue(forKey: profileID)
        coordinators.removeValue(forKey: profileID)
    }
}

/// 接收 SwiftTerm 关于本地子进程（这里是 ssh）生命周期事件的回调。
final class TerminalProcessCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    let connection: SSHConnection

    init(connection: SSHConnection) {
        self.connection = connection
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            connection.markProcessTerminated()
        }
    }
}
