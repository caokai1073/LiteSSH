import Foundation

/// 极简的中英文双语辅助：界面文案跟随系统语言显示中文或英文。
///
/// 故意不用 Localizable.strings / .xcstrings + Bundle.module 那套机制——SwiftPM 给带
/// resources 的 target 打包出来的是独立的 "ModuleName_TargetName.bundle"，只能通过自动生成的
/// Bundle.module 访问，并不会合并进 Bundle.main；而 Text/Button 等很多 SwiftUI 初始化方法接受
/// LocalizedStringKey 时是直接查 Bundle.main，没有暴露 bundle: 参数可以在调用点改查哪个 bundle。
/// 即使是用 Xcode "Package as App" 方式运行可执行 target，也不能保证两者是同一个 bundle，
/// 一旦不一致，Text(...) 就会直接显示 key 本身而不是翻译，且这个风险在没有编译器的情况下
/// 无法跑一次真实验证。所以这里换成完全自包含、零资源文件依赖、纯靠代码审查就能确认正确性的写法。
///
/// 代码注释保持中文不受影响（开发说明，不会出现在界面上）；只有用户在界面上会看到的文案
/// （按钮、标签、提示、报错信息等）才需要用 L10n.s(中文, English) 包一层。
enum L10n {
    /// 系统首选语言是否是中文（zh、zh-Hans、zh-Hant、zh-CN、zh-TW 等各种变体都算）。
    /// 只在第一次访问时计算一次，运行期间系统语言不会变，不需要每次都重新判断。
    static let isChinese: Bool = {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    }()

    /// 按系统语言返回对应文案：中文系统返回 zh，其它都返回 en。
    static func s(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
