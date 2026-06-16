import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return L10n.s("无法启动进程：\(reason)", "Failed to launch process: \(reason)")
        }
    }
}

/// 通用的「跑一个本地命令行程序，拿到 stdout/stderr/退出码」封装。
/// 整个 App 里所有 ssh / sftp / scp 调用都通过这里执行。
///
/// stdout 和 stderr 通过 readabilityHandler 并发持续读取，避免两条管道缓冲区（各 64 KB）
/// 同时写满时进程挂死（子进程 write 阻塞 → 我们等不到 terminationHandler → 死锁）。
/// 目录递归传输、远端大文件列表等输出可能轻松超过 64 KB，所以这里必须边跑边读。
enum ProcessRunner {

    @discardableResult
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            // nil 时 Foundation 默认继承当前进程的环境变量，行为和原来一致；
            // 传非 nil（比如带 SSH_ASKPASS 的环境）时才会覆盖。
            if let environment {
                process.environment = environment
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            // 防止 ssh/sftp 在没有 TTY 的情况下还尝试交互式读密码导致挂起。
            process.standardInput = FileHandle.nullDevice

            // 两条管道各自的数据缓冲，以及保护它们的同一把锁。
            var outData = Data()
            var errData = Data()
            let dataLock = NSLock()

            var didResume = false
            let resumeLock = NSLock()
            func resumeOnce(_ result: Result<ProcessResult, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            // 进程运行期间持续从两条管道读取数据，防止缓冲区写满造成死锁。
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                dataLock.lock(); outData.append(chunk); dataLock.unlock()
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                dataLock.lock(); errData.append(chunk); dataLock.unlock()
            }

            process.terminationHandler = { proc in
                // 进程退出后停止 handler，再做一次 drain 把管道里最后残留的字节取完。
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                dataLock.lock()
                outData.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                errData.append(errPipe.fileHandleForReading.readDataToEndOfFile())
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                dataLock.unlock()
                resumeOnce(.success(ProcessResult(stdout: out, stderr: err, exitCode: proc.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                resumeOnce(.failure(ProcessRunnerError.launchFailed(error.localizedDescription)))
                return
            }

            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
        }
    }

    /// 把一段字符串作为 shell 单引号字面量安全转义，用于拼进远程命令字符串里。
    static func shellQuote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
