import SwiftUI
import BookCardCore

private struct MobileControls: ViewModifier {
    @EnvironmentObject private var store: AppStore
    let notes: Bool
    @Binding var showKey: Bool
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(store.hasKey ? "更换 Key" : "输入 Key") { showKey = true }
                        if store.hasKey {
                            Button("移除 Key（保留离线数据）") { store.removeKey() }
                        }
                        Button("清除所有本地数据…", role: .destructive) { confirmDelete = true }
                    } label: { Label("设置", systemImage: "gearshape") }
                        .disabled(store.busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    if store.busy {
                        ProgressView().controlSize(.small)
                        Text(store.status).lineLimit(1)
                    } else if !store.hasKey {
                        Text("离线模式")
                    } else if let date = notes ? store.cache.notesSynced : store.cache.readingSynced {
                        Text("已同步 · \(date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("尚未完成同步")
                    }
                    Spacer(minLength: 0)
                    if store.error != nil {
                        Button { showError = true } label: {
                            Label("查看同步错误", systemImage: "exclamationmark.circle.fill").labelStyle(.iconOnly)
                        }.tint(.red)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
            }
            .confirmationDialog("清除所有本地阅读数据？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("清除本地数据", role: .destructive) { store.deleteData() }
            } message: {
                Text("将删除本机缓存，保留钥匙串中的 Key。不会删除微信读书中的任何内容。")
            }
            .alert("同步异常", isPresented: $showError) {
                Button("关闭提示") { store.dismissError() }
            } message: { Text(store.error ?? "") }
    }
}

extension View {
    func mobileControls(notes: Bool, showKey: Binding<Bool>) -> some View {
        modifier(MobileControls(notes: notes, showKey: showKey))
    }
}
