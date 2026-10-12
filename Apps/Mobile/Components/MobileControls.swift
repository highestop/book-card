import SwiftUI
import BookCardCore

private struct MobileControls: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @Binding var showKey: Bool
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Menu {
                    Text(store.busy ? store.status : (store.hasKey ? store.cache.notesSynced.map { "最近同步：" + readingDate($0) } ?? "等待同步" : "离线书签"))
                    if store.error != nil { Button("查看同步错误") { showError = true } }
                    Divider()
                    Button("立即同步") { Task { await store.refresh() } }.disabled(!store.hasKey || store.busy)
                    Button("完整校验所有笔记") { Task { await store.refresh(force: true) } }.disabled(!store.hasKey || store.busy)
                    Divider()
                    Button(store.hasKey ? "更换 Key" : "输入 Key") { showKey = true }.disabled(store.busy)
                    if store.hasKey {
                        Button("移除 Key（保留离线数据）") { store.removeKey() }.disabled(store.busy)
                    }
                    Button("清除所有本地数据…", role: .destructive) { confirmDelete = true }.disabled(store.busy)
                } label: {
                    HStack(spacing: 6) {
                        if store.busy { ProgressView().controlSize(.small) }
                        Image(systemName: "slider.horizontal.3")
                            .overlay(alignment: .topTrailing) {
                                if store.error != nil { Circle().fill(MobilePaper.rust).frame(width: 6, height: 6).offset(x: 3, y: -3) }
                            }
                    }.frame(minWidth: 44, minHeight: 44)
                        .background(MobilePaper.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel("连接与缓存设置")
                    .padding(.trailing, 16).padding(.top, 8)
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
    func mobileControls(showKey: Binding<Bool>) -> some View {
        modifier(MobileControls(showKey: showKey))
    }
}
