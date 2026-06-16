import Foundation

/// 生成一个极简的 SSH_ASKPASS 脚本：原样打印环境变量里的密文。
/// 配合 SSH_ASKPASS_REQUIRE=force（OpenSSH 8.4+ 支持，macOS 自带的 ssh 已满足）让 ssh/sftp
/// 在需要密码或私钥口令时自动从这个脚本取值，而不是在终端里弹交互式提示——
/// 这样密码只需要在「添加服务器」时输入一次、存进 Keychain，以后都不用再手动输入。
///
/// 脚本本身不包含密码：密码通过环境变量临时传给子进程，脚本只是原样转发。
enum AskPassHelper {
    private static let secretEnvKey = "LITESSH_ASKPASS_SECRET"

    /// 脚本路径只生成一次，所有连接共用同一个脚本。
    private static let scriptPath: String = {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("litessh-askpass.sh").path
        let script = "#!/bin/sh\nprintf '%s' \"$\(secretEnvKey)\"\n"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }()

    /// 在当前进程环境基础上叠加 askpass 相关变量，传给 Process.environment 使用。
    static func environment(secret: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = scriptPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env[secretEnvKey] = secret
        return env
    }
}
