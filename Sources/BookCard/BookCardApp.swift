import SwiftUI
import AppKit

@main struct BookCardApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .frame(minWidth: 850, minHeight: 580)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1080, height: 740)
    }
}
enum LibraryTab: Hashable { case books, notes }
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab: LibraryTab = .books
    @State private var confirmDelete = false
    var body: some View {
        Group {
            if !store.hasKey && store.cache.books.isEmpty { KeyView(initial: true) }
            else {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Picker("导航", selection: $tab) {
                            Text("我读过的书").tag(LibraryTab.books)
                            Text("我的笔记").tag(LibraryTab.notes)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
                        Spacer(minLength: 12)
                        SyncStatusView(tab: tab).frame(maxWidth: 360, alignment: .trailing)
                        Menu {
                            Button("更换 Key") { store.showKey = true }
                            Button("移除 Key（保留离线数据）") { store.removeKey() }.disabled(!store.hasKey)
                            Button("清除所有本地数据…", role: .destructive) { confirmDelete = true }
                        } label: { Label("设置", systemImage: "gearshape").labelStyle(.iconOnly) }
                            .menuStyle(.borderlessButton).fixedSize().disabled(store.busy)
                    }.padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
                    Divider()
                    // Keep both pages mounted so switching tabs preserves their local state.
                    ZStack {
                        ReadingBooksView().opacity(tab == .books ? 1 : 0)
                            .allowsHitTesting(tab == .books).disabled(tab != .books).accessibilityHidden(tab != .books)
                        AllNotesView().opacity(tab == .notes ? 1 : 0)
                            .allowsHitTesting(tab == .notes).disabled(tab != .notes).accessibilityHidden(tab != .notes)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $store.showKey) { KeyView(initial: false) }
        .confirmationDialog("清除所有本地阅读数据？", isPresented: $confirmDelete) {
            Button("清除本地数据", role: .destructive) { store.deleteData() }
        } message: { Text("将删除本机缓存，保留钥匙串中的 Key。不会删除微信读书中的任何内容。") }
        .task(id: tab) {
            do {
                while store.busy { try await Task.sleep(nanoseconds: 100_000_000) }
                try Task.checkCancellation()
                if store.hasKey && (tab == .notes ? store.cache.notesSynced == nil : store.cache.readingSynced == nil) {
                    await store.refresh(notes: tab == .notes)
                }
            } catch { }
        }
    }
}
struct SyncStatusView: View {
    @EnvironmentObject var store: AppStore
    let tab: LibraryTab
    @State private var showError = false
    var syncDate: Date? { tab == .notes ? store.cache.notesSynced : store.cache.readingSynced }
    var body: some View {
        HStack(spacing: 10) {
            if store.busy {
                ProgressView().controlSize(.small)
                Text(store.status).lineLimit(1).truncationMode(.middle).help(store.status)
            } else if !store.hasKey {
                Text("离线模式").foregroundStyle(.secondary)
                Button("输入 Key") { store.showKey = true }
            } else if let date = syncDate {
                Text("已同步 · \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary).lineLimit(1)
                    .help("本页最近完整同步：\(date.formatted(date: .abbreviated, time: .shortened))")
            } else { Text("尚未完成同步").foregroundStyle(.secondary).lineLimit(1) }
            if let error = store.error {
                Button { showError = true } label: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }.buttonStyle(.plain).accessibilityLabel("查看同步错误").help("查看同步错误")
                    .popover(isPresented: $showError) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("同步异常").font(.headline)
                            ScrollView { Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 220)
                            HStack { Spacer(); Button("关闭提示") { store.error = nil; showError = false } }
                        }.padding(20).frame(width: 380)
                    }
            }
        }.font(.caption)
    }
}
struct ReadingBooksView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @AppStorage("readingBookSort") private var storedSort = BookSort.progressDescending.rawValue
    var sort: BookSort { BookSort.restored(storedSort) }
    var sortSelection: Binding<BookSort> {
        Binding(get: { sort }, set: { storedSort = $0.rawValue })
    }
    var books: [Book] {
        store.cache.sortedBooks(by: sort).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("我读过的书").font(.largeTitle.bold())
                Text("\(store.cache.books.filter { !$0.official }.count) 本 · \(store.cache.finishedBooks.count) 本已读完").foregroundStyle(.secondary)
                Spacer()
                TextField("搜索书名或作者", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            HStack {
                Text("展示书架和笔记本中的全部书籍，包含未读、在读和已读完。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("排序", selection: sortSelection) { ForEach(BookSort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 260)
            }
            if books.isEmpty {
                ContentUnavailableView(store.busy ? "正在读取书籍…" : "暂无匹配的书籍", systemImage: "book.closed", description: Text("首次进入会自动同步，也可以尝试其他搜索词。"))
            } else {
                List(books) { book in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "book.closed.fill").font(.title).foregroundStyle(.tint).frame(width: 36)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title).font(.headline).textSelection(.enabled)
                            if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary) }
                            if let progress = store.cache.reading?[book.id] {
                                HStack {
                                    if let duration = durationLabel(progress) { Text(duration) }
                                    if let time = progress.finishedAt, time > 0 { Text("读完于 \(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted))") }
                                    if let time = progress.updatedAt, time > 0 { Text("最近阅读 \(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted))") }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let progress = store.cache.reading?[book.id] {
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("\(progress.percent == 100 ? "已读完" : progress.percent == 0 ? "未读" : "在读") · \(progress.percent)%")
                                    .foregroundStyle(progress.percent == 100 ? Color.green : Color.primary)
                                ProgressView(value: Double(progress.percent), total: 100).frame(width: 120)
                            }.font(.callout)
                        } else { Text("进度待获取").foregroundStyle(.secondary) }
                    }.padding(.vertical, 12)
                }.listStyle(.inset)
            }
        }.padding(24)
    }
}
struct AllNotesView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var selected: String?
    var sources: [Book] {
        store.cache.books.filter {
            (($0.highlights ?? 0) + ($0.thoughts ?? 0) > 0 || !(store.cache.details[$0.id]?.notes.isEmpty ?? true)) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section("书籍") { ForEach(sources.filter { !$0.official }) { sourceRow($0) } }
                Section("公众号") { ForEach(sources.filter(\.official)) { sourceRow($0) } }
            }
            .searchable(text: $search, prompt: "搜索书籍或公众号")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .safeAreaInset(edge: .bottom) {
                Text("\(sources.count) 个笔记来源 · \(store.cache.allNotes.count) 条已缓存笔记").font(.caption).foregroundStyle(.secondary).padding(12)
            }
        } detail: {
            if let book = store.cache.books.first(where: { $0.id == selected }) {
                SourceNotesView(book: book).id(book.id)
            } else {
                ContentUnavailableView("选择笔记来源", systemImage: "books.vertical", description: Text("左侧列出做过笔记的书籍和公众号。选择后查看章节或文章中的划线与想法。"))
            }
        }
    }
    private func sourceRow(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title).font(.headline)
            Text("\(book.highlights ?? 0) 条划线 · \(book.thoughts ?? 0) 条想法").font(.caption).foregroundStyle(.secondary)
            if store.cache.details[book.id] == nil { Text("等待同步").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 6).tag(book.id)
    }
}
struct SourceNotesView: View {
    @EnvironmentObject var store: AppStore
    let book: Book
    @State private var kind = "全部"
    @State private var search = ""
    var notes: [Note] { store.cache.details[book.id]?.notes ?? [] }
    var groups: [NoteGroup] {
        groupedNotes(notes.filter {
            (kind == "全部" || $0.kind == kind) &&
            (search.isEmpty || $0.quote.localizedCaseInsensitiveContains(search) || ($0.thought ?? "").localizedCaseInsensitiveContains(search) || $0.chapter.localizedCaseInsensitiveContains(search))
        }, official: book.official)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(book.title).font(.largeTitle.bold()).textSelection(.enabled)
            Text("\(notes.filter { $0.kind == "划线" }.count) 条划线 · \(notes.filter { $0.kind == "想法" }.count) 条想法").foregroundStyle(.secondary)
            HStack {
                Picker("类型", selection: $kind) { ForEach(["全部", "划线", "想法"], id: \.self) { Text($0) } }.frame(width: 160)
                TextField("搜索笔记或\(book.official ? "文章" : "章节")", text: $search).textFieldStyle(.roundedBorder)
            }
            if store.cache.details[book.id] == nil {
                ContentUnavailableView(store.busy ? "正在同步，请稍候…" : "尚未同步该来源", systemImage: "arrow.clockwise", description: Text("当前尚无该来源的缓存笔记。"))
            } else if groups.isEmpty {
                ContentUnavailableView("暂无匹配笔记", systemImage: "quote.bubble", description: Text("试试其他关键词或笔记类型。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.title).font(.title3.bold()).textSelection(.enabled)
                                    Text("\(group.notes.count) 条").font(.caption).foregroundStyle(.secondary)
                                }.padding(.top, 12)
                                ForEach(group.notes) { note in NoteRow(entry: NoteEntry(book: book, note: note)) }
                            }
                        }
                    }
                }
            }
            if let date = store.cache.details[book.id]?.synced {
                Text("本来源同步于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24)
    }
}
struct NoteRow: View {
    let entry: NoteEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.note.kind).font(.caption.bold()).foregroundStyle(.tint)
                Text(entry.book.title).font(.headline)
                Spacer()
                if let timestamp = entry.note.created { Text(Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
            }
            if !entry.note.chapter.isEmpty { Text(entry.note.chapter).font(.caption).foregroundStyle(.secondary) }
            if !entry.note.quote.isEmpty { Text(entry.note.quote).lineSpacing(5).textSelection(.enabled) }
            if let thought = entry.note.thought { Text(thought).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct KeyView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    let initial: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "book.closed.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text(initial ? "欢迎使用 BookCard" : "连接微信读书").font(.largeTitle.bold())
            Text("输入微信读书 Skill 的 API Key，即可查看你的阅读进度、划线和想法。").foregroundStyle(.secondary)
            Link("打开微信读书官方 Key 页面 ↗", destination: URL(string: "https://weread.qq.com/r/weread-skills")!)
            SecureField("粘贴 wrk- 开头的 Key", text: $key).textFieldStyle(.roundedBorder).onSubmit { connect() }.disabled(store.busy)
            Text("Key 仅存储在本机钥匙串中。阅读数据保存在本机，不上传到开发者服务器。更换 Key 将使用独立缓存。").font(.caption).foregroundStyle(.secondary)
            if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                if !initial { Button("取消") { dismiss() }.disabled(store.busy) }
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button(store.busy ? "连接中…" : "连接并读取数据") { connect() }
                    .buttonStyle(.borderedProminent).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
            }
        }.padding(40).frame(width: 500)
    }
    private func connect() {
        Task {
            if await store.connect(key) {
                key = ""; dismiss(); store.showKey = false
                await store.refresh()
            }
        }
    }
}
