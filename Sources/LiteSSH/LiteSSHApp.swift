import SwiftUI
import AppKit

@main
struct LiteSSHApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(sessionStore)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.s("新建服务器…", "New Server…")) {
                    NotificationCenter.default.post(name: .liteSSHNewProfile, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let liteSSHNewProfile = Notification.Name("liteSSHNewProfile")
}

/// 通过 Xcode 直接运行 Swift Package（没有正式 .app 包）时，窗口有时不会被系统判定为
/// "前台活跃应用"，导致虽然窗口看着在最前面，键盘输入却还停留在 Xcode 上、文本框点了也打不进字。
/// 这里强制把自己设成常规前台 App 并激活，修复这种"看得见、打不进"的输入框问题。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // 放进 DispatchQueue.main.async：如果在 applicationDidFinishLaunching 里同步调用 activate，
        // 有时会强行把 SwiftUI 还没提交完的首次视图更新一起冲刷掉，从而触发
        // "Publishing changes from within view updates" 警告。延后一个 run loop tick 再激活即可。
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
