import SwiftUI
import BookCardCore

struct iPhoneLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showKey: Bool
    @AppStorage("mobileLibraryTab") private var tab = "books"

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                iPhoneReadingView()
                    .mobileControls(notes: false, showKey: $showKey)
            }
            .task { await store.ensureSynced() }
            .tabItem { Label("我读过的书", systemImage: "book.closed") }
            .tag("books")

            NavigationStack {
                iPhoneSourcesView()
                    .mobileControls(notes: true, showKey: $showKey)
            }
            .task { await store.ensureSynced(notes: true) }
            .tabItem { Label("我的笔记", systemImage: "quote.bubble") }
            .tag("notes")
        }
    }
}

struct iPhoneReadingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @AppStorage("readingBookSort") private var storedSort = BookSort.progressDescending.rawValue
    private var books: [Book] { store.cache.readingBooks(search: search, sort: .restored(storedSort)) }

    var body: some View {
        List {
            Section {
                Picker("排序", selection: $storedSort) {
                    ForEach(BookSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Text("\(store.cache.bookCount) 本 · \(store.cache.finishedBooks.count) 本已读完")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(books) { book in
                    MobileBookCard(book: book, progress: store.cache.reading?[book.id])
                        .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("我读过的书")
        .searchable(text: $search, prompt: "搜索书名或作者")
        .overlay {
            if books.isEmpty {
                ContentUnavailableView(store.busy ? "正在读取书籍…" : "暂无匹配的书籍", systemImage: "book.closed")
                    .allowsHitTesting(false)
            }
        }
    }
}

struct iPhoneSourcesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    private var sources: [Book] { store.cache.noteSources(search: search) }

    var body: some View {
        List {
            Section("书籍") {
                ForEach(sources.filter { !$0.official }) { book in
                    NavigationLink(value: book) { MobileSourceRow(book: book) }
                }
            }
            Section("公众号") {
                ForEach(sources.filter(\.official)) { book in
                    NavigationLink(value: book) { MobileSourceRow(book: book) }
                }
            }
        }
        .navigationTitle("我的笔记")
        .searchable(text: $search, prompt: "搜索书籍或公众号")
        .navigationDestination(for: Book.self) { book in
            MobileSourceNotesView(book: book)
        }
        .overlay {
            if sources.isEmpty {
                ContentUnavailableView(store.busy ? "正在读取笔记…" : "暂无匹配的笔记来源", systemImage: "quote.bubble")
                    .allowsHitTesting(false)
            }
        }
    }
}
