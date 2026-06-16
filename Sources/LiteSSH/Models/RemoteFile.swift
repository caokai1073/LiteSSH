import Foundation

/// 远程文件/目录条目，来自对 `find <path> -maxdepth 1 -printf '%f\t%y\t%s\t%T@\n'` 输出的解析。
struct RemoteFile: Identifiable, Hashable {
    var id: String { fullPath }
    var name: String
    var fullPath: String
    var isDirectory: Bool
    var isSymlink: Bool
    var size: Int64
    var modifiedAt: Date?

    var sizeDisplay: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var dateDisplay: String {
        guard let modifiedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: modifiedAt)
    }

    var systemIconName: String {
        if isDirectory { return "folder.fill" }
        if isSymlink { return "arrow.triangle.branch" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "bmp": return "photo"
        case "zip", "tar", "gz", "bz2", "7z", "xz": return "doc.zipper"
        case "txt", "md", "log": return "doc.text"
        case "json", "yml", "yaml", "xml", "toml": return "curlybraces"
        case "sh", "py", "js", "ts", "go", "rs", "c", "cpp", "swift", "rb", "java":
            return "chevron.left.forwardslash.chevron.right"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    /// 解析一行 `find -printf` 输出。返回 nil 表示这一行格式不对，应跳过。
    static func parse(line: String, parentPath: String) -> RemoteFile? {
        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let name = String(parts[0])
        guard !name.isEmpty else { return nil }
        let typeChar = parts[1]
        let sizeStr = String(parts[2])
        let timeStr = String(parts[3])

        let isDir = typeChar == "d"
        let isLink = typeChar == "l"
        let size = Int64(sizeStr) ?? 0
        var date: Date? = nil
        if let epoch = Double(timeStr) {
            date = Date(timeIntervalSince1970: epoch)
        }

        let trimmedParent = parentPath.hasSuffix("/") ? String(parentPath.dropLast()) : parentPath
        let fullPath = trimmedParent.isEmpty ? "/\(name)" : "\(trimmedParent)/\(name)"

        return RemoteFile(
            name: name,
            fullPath: fullPath,
            isDirectory: isDir,
            isSymlink: isLink,
            size: size,
            modifiedAt: date
        )
    }
}
