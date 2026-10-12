import SwiftUI
import AppKit
import BookCardCore

enum LibraryPage: Hashable { case home, bookmarks, book(String) }

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: LibraryPage = .home
    @State private var bookmarksState = BookmarksState()
    @State private var showKey = false
    @State private var confirmDelete = false
    init(initialPage: LibraryPage = .home, initialBookmarks: BookmarksState = BookmarksState()) {
        _page = State(initialValue: initialPage); _bookmarksState = State(initialValue: initialBookmarks)
    }
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if !store.hasKey && store.cache.books.isEmpty { KeyView(initial: true) }
                else {
                    switch page {
                    case .home: HomeView(openBookmarks: { navigate(.bookmarks) }, openBook: { navigate(.book($0)) })
                    case .bookmarks: AllBookmarksView(openBook: { navigate(.book($0)) }, backHome: { navigate(.home) }, state: $bookmarksState)
                    case .book(let id):
                        if let book = store.cache.books.first(where: { $0.id == id }) {
                            BookNotesView(book: book, back: { navigate(.bookmarks) }).id(id)
                        } else { AllBookmarksView(openBook: { navigate(.book($0)) }, backHome: { navigate(.home) }, state: $bookmarksState) }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        }
        .overlay(alignment: .topTrailing) {
            LibraryMenu(showKey: $showKey, confirmDelete: $confirmDelete).padding(.trailing, 24).padding(.top, 14)
        }
        .background(Paper.background).foregroundStyle(Paper.ink).tint(Paper.green)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showKey) { KeyView(initial: false) }
        .confirmationDialog("清除所有本地读书笔记？", isPresented: $confirmDelete) {
            Button("清除本地数据", role: .destructive) { store.deleteData(); navigate(.home) }
        } message: { Text("删除本机所有账号的缓存，保留 Key。微信读书中的内容不受影响，下次同步会重新下载。") }
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfNeeded() } }
        }
        .onChange(of: store.cache.books.isEmpty) { _, empty in if empty { page = .home } }
    }
    private func navigate(_ destination: LibraryPage) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { page = destination }
    }
}

struct LibraryMenu: View {
    @EnvironmentObject var store: AppStore
    @Binding var showKey: Bool
    @Binding var confirmDelete: Bool
    @State private var showError = false
    private var summary: String {
        if store.busy { return store.status }
        if store.error != nil { return "同步未完成" }
        if !store.hasKey { return "离线书签" }
        return store.cache.notesSynced.map { "最近同步：" + readingDate($0) } ?? "等待同步"
    }
    var body: some View {
        Menu {
            Text(summary)
            if store.error != nil { Button("查看同步错误") { showError = true } }
            Divider()
            Button("立即同步") { Task { await store.refresh() } }.disabled(!store.hasKey || store.busy)
            Button("完整校验所有笔记") { Task { await store.refresh(force: true) } }.disabled(!store.hasKey || store.busy)
            Divider()
            Button(store.hasKey ? "更换微信读书 Key" : "连接微信读书") { showKey = true }.disabled(store.busy)
            Button("移除 Key，保留离线数据") { store.removeKey() }.disabled(!store.hasKey || store.busy)
            Button("清除所有本地数据…", role: .destructive) { confirmDelete = true }.disabled(store.busy)
        } label: {
            HStack(spacing: 8) {
                if store.busy { ProgressView().controlSize(.mini) }
                Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                    .overlay(alignment: .topTrailing) {
                        if store.error != nil { Circle().fill(Paper.rust).frame(width: 6, height: 6).offset(x: 3, y: -3) }
                    }
            }.padding(10).background(Paper.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("连接与缓存设置 · " + summary).accessibilityLabel("连接与缓存设置").accessibilityValue(summary)
            .popover(isPresented: $showError) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("已缓存的笔记仍可阅读").font(.headline)
                    ScrollView { Text(store.error ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
                    Button("重试同步") { showError = false; Task { await store.refresh() } }.disabled(!store.hasKey || store.busy)
                }.padding(24).frame(width: 350)
            }
    }
}

struct KeyView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    let initial: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Ribbon().fill(Paper.green).frame(width: 40, height: 58)
            Text(initial ? "把读过的片刻，\n留成一张书签。" : "连接你的微信读书")
                .font(.system(size: 30, weight: .medium, design: .serif)).lineSpacing(8)
            Text("划线与想法，汇成你的私人书签集。\n每次打开，接着读最近留下的那一页。")
                .font(.system(size: 14)).lineSpacing(6).foregroundStyle(Paper.secondary)
            Link("获取微信读书官方 Key ↗", destination: URL(string: "https://weread.qq.com/r/weread-skills")!)
            SecureField("粘贴 wrk- 开头的 Key", text: $key).textFieldStyle(.roundedBorder)
                .onSubmit { connect() }.disabled(store.busy)
            Text("Key 安全保存在本机钥匙串，笔记缓存到本地，离线也能阅读。更换 Key 会切换到独立笔记缓存。")
                .font(.caption).foregroundStyle(Paper.secondary)
            if let error = store.error { Text(error).foregroundStyle(Paper.rust).font(.callout).textSelection(.enabled) }
            HStack {
                if !initial { Button("取消") { dismiss() }.disabled(store.busy) }
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button(store.busy ? "正在连接…" : "连接并同步书签") { connect() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
            }
        }.padding(44).frame(width: 510).background(Paper.background).foregroundStyle(Paper.ink).tint(Paper.green)
    }
    private func connect() {
        Task {
            if await store.connect(key) {
                key = ""; dismiss()
                await store.refresh()
            }
        }
    }
}
