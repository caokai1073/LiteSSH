import SwiftUI
import AppKit
import SwiftTerm

/// 把 SwiftTerm 的终端 NSView 接入 SwiftUI。真正的创建/缓存逻辑在 TerminalViewRegistry 里，
/// 这样切换侧边栏选中项时不会重复 spawn ssh 进程。
struct TerminalContainerView: NSViewRepresentable {
    @ObservedObject var connection: SSHConnection
    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = TerminalViewRegistry.shared.terminalView(for: connection)
        applyColors(to: view, dark: colorScheme == .dark)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // 系统外观切换时同步更新终端配色。
        applyColors(to: nsView, dark: colorScheme == .dark)
    }

    private func applyColors(to view: LocalProcessTerminalView, dark: Bool) {
        if dark {
            // 深色：纯黑偏灰，避免刺眼；前景用柔和白。
            view.nativeBackgroundColor = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
            view.nativeForegroundColor = NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.90, alpha: 1)
        } else {
            // 浅色：米白底，深灰字。
            view.nativeBackgroundColor = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
            view.nativeForegroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
    }
}
