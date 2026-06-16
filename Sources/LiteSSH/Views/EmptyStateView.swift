import SwiftUI

struct EmptyStateView: View {
    let onAddServer: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(L10n.s("选择左侧的服务器，或添加一个新的", "Select a server on the left, or add a new one"))
                .font(.title3)
                .foregroundStyle(.secondary)
            Button(L10n.s("添加服务器", "Add Server"), action: onAddServer)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
