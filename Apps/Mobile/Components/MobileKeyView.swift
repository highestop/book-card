import SwiftUI
import BookCardCore

struct MobileKeyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    let initial: Bool
    let onConnected: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "book.closed.fill").font(.system(size: 48)).foregroundStyle(.tint)
                    Text(initial ? "欢迎使用 BookCard" : "连接微信读书").font(.largeTitle.bold())
                    Text("输入微信读书 Skill 的 API Key，即可查看你的阅读进度、划线和想法。")
                        .foregroundStyle(.secondary)
                    Link("打开微信读书官方 Key 页面 ↗", destination: URL(string: "https://weread.qq.com/r/weread-skills")!)
                    SecureField("粘贴 wrk- 开头的 Key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit { connect() }.disabled(store.busy)
                    Text("Key 仅存储在本机钥匙串中。阅读数据保存在本机，不上传到开发者服务器。更换 Key 将使用独立缓存。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = store.error { Text(error).foregroundStyle(.red) }
                    Button { connect() } label: {
                        HStack {
                            if store.busy { ProgressView().tint(.white) }
                            Text(store.busy ? "连接中…" : "连接并读取数据")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                }
                .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }
            .toolbar {
                if !initial {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.disabled(store.busy)
                    }
                }
            }
        }
    }

    private func connect() {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !store.busy else { return }
        Task {
            if await store.connect(key) {
                key = ""; onConnected(); dismiss()
                await store.refresh()
            }
        }
    }
}
