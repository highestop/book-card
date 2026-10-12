import SwiftUI
import AppKit
import BookCardCore

enum LibraryPage: Hashable { case home, shelf, book(String) }

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: LibraryPage = .home
    @State private var shelfState = ShelfState()
    @State private var showKey = false
    @State private var confirmDelete = false
    init(initialPage: LibraryPage = .home, initialShelf: ShelfState = ShelfState()) {
        _page = State(initialValue: initialPage); _shelfState = State(initialValue: initialShelf)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Paper.line).frame(height: 1)
            Group {
                if !store.hasKey && store.cache.books.isEmpty { KeyView(initial: true) }
                else {
                    switch page {
                    case .home: HomeView(openShelf: { navigate(.shelf) }, openBook: { navigate(.book($0)) })
                    case .shelf: BookshelfView(openBook: { navigate(.book($0)) }, state: $shelfState)
                    case .book(let id):
                        if let book = store.cache.books.first(where: { $0.id == id }) {
                            BookNotesView(book: book, back: { navigate(.shelf) }).id(id)
                        } else { BookshelfView(openBook: { navigate(.book($0)) }, state: $shelfState) }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
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
    private var header: some View {
        HStack(spacing: 24) {
            HStack(spacing: 9) {
                Image(systemName: "bookmark.fill").font(.system(size: 21)).foregroundStyle(Paper.green)
                Text("BookCard").font(.system(size: 20, weight: .semibold, design: .serif))
            }.padding(.trailing, 24)
            navButton("最近书签", icon: "rectangle.stack", destination: .home, active: page == .home)
            navButton("全部书签", icon: "books.vertical", destination: .shelf, active: page != .home)
            Spacer(minLength: 8)
            SyncStatusView()
            Menu {
                Button("立即同步") { Task { await store.refresh() } }.disabled(!store.hasKey || store.busy)
                Button("完整校验所有笔记") { Task { await store.refresh(force: true) } }.disabled(!store.hasKey || store.busy)
                Divider()
                Button(store.hasKey ? "更换微信读书 Key" : "连接微信读书") { showKey = true }
                Button("移除 Key，保留离线数据") { store.removeKey() }.disabled(!store.hasKey)
                Button("清除所有本地数据…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 17)).padding(8) }
                .menuStyle(.borderlessButton).fixedSize().disabled(store.busy).help("连接与缓存设置")
        }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 18)
    }
    private func navButton(_ title: String, icon: String, destination: LibraryPage, active: Bool) -> some View {
        Button { navigate(destination) } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Paper.green : Paper.secondary)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { if active { Capsule().fill(Paper.green).frame(height: 2).offset(y: 8) } }
        }.buttonStyle(.plain)
    }
}

struct SyncStatusView: View {
    @EnvironmentObject var store: AppStore
    @State private var showError = false
    var body: some View {
        HStack(spacing: 7) {
            if store.busy {
                ProgressView().controlSize(.mini)
                Text(store.status).lineLimit(1).truncationMode(.middle).frame(maxWidth: 210).help(store.status)
            } else if let error = store.error {
                Button { showError.toggle() } label: {
                    Label("同步未完成", systemImage: "exclamationmark.circle").foregroundStyle(Paper.rust)
                }.buttonStyle(.plain)
                    .popover(isPresented: $showError) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("已缓存的笔记仍可阅读").font(.headline)
                            ScrollView { Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
                            Button("重试同步") { showError = false; Task { await store.refresh() } }.disabled(!store.hasKey)
                        }.padding(24).frame(width: 350)
                    }
            } else {
                Circle().fill(store.hasKey ? Paper.green : Paper.secondary).frame(width: 5, height: 5)
                Text(store.hasKey ? (store.cache.notesSynced == nil ? "等待同步" : "已同步到本机") : "离线书架")
                    .help(store.cache.notesSynced.map { "最近同步：" + readingDate($0) } ?? "连接后自动同步读书笔记")
            }
        }.font(.system(size: 11)).foregroundStyle(Paper.secondary)
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
            Text("划线与想法，汇成你的私人书架。\n每次打开，接着读最近留下的那一页。")
                .font(.system(size: 14)).lineSpacing(6).foregroundStyle(Paper.secondary)
            Link("获取微信读书官方 Key ↗", destination: URL(string: "https://weread.qq.com/r/weread-skills")!)
            SecureField("粘贴 wrk- 开头的 Key", text: $key).textFieldStyle(.roundedBorder)
                .onSubmit { connect() }.disabled(store.busy)
            Text("Key 安全保存在本机钥匙串，笔记缓存到本地，离线也能阅读。更换 Key 会切换到独立书架。")
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
