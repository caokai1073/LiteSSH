import SwiftUI

/// 一行文件/目录的展示：按要求只显示图标 + 名称，不显示大小、修改时间。
/// 目录额外显示一个右箭头，提示「点击可以进入」。
struct RemoteFileRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.systemIconName)
                .foregroundStyle(file.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(file.name)
                .lineLimit(1)

            Spacer(minLength: 8)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
