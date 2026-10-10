import SwiftUI
import BookCardCore

private enum PadDestination: Hashable {
    case reading, notes, source(String)
    var showsNotes: Bool { self != .reading }
}

struct iPadLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showKey: Bool
    @State private var destination: PadDestination? = .reading
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section {
                    NavigationLink(value: PadDestination.reading) { Label("我读过的书", systemImage: "book.closed") }
                    NavigationLink(value: PadDestination.notes) { Label("我的笔记", systemImage: "quote.bubble") }
                }
                Section("书籍笔记") {
                    ForEach(store.cache.noteSources(search: search).filter { !$0.official }) { book in
                        NavigationLink(value: PadDestination.source(book.id)) { MobileSourceRow(book: book) }
                    }
                }
                Section("公众号笔记") {
                    ForEach(store.cache.noteSources(search: search).filter(\.official)) { book in
                        NavigationLink(value: PadDestination.source(book.id)) { MobileSourceRow(book: book) }
                    }
                }
            }
            .navigationTitle("BookCard")
            .searchable(text: $search, prompt: "搜索笔记来源")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            Group {
                switch destination {
                case .reading:
                    iPadReadingView()
                case .notes:
                    List(store.cache.noteSources()) { book in
                        Button { destination = .source(book.id) } label: { MobileSourceRow(book: book) }
                            .foregroundStyle(.primary)
                    }
                    .navigationTitle("我的笔记")
                    .overlay {
                        if store.cache.noteSources().isEmpty {
                            ContentUnavailableView("暂无笔记来源", systemImage: "quote.bubble")
                                .allowsHitTesting(false)
                        }
                    }
                case .source(let id):
                    if let book = store.cache.books.first(where: { $0.id == id }) {
                        MobileSourceNotesView(book: book).id(id)
                    } else {
                        ContentUnavailableView("选择笔记来源", systemImage: "books.vertical")
                    }
                case nil:
                    ContentUnavailableView("选择书籍或笔记", systemImage: "books.vertical")
                }
            }
            .mobileControls(notes: destination?.showsNotes ?? false, showKey: $showKey)
            .task(id: destination?.showsNotes) {
                await store.ensureSynced(notes: destination?.showsNotes ?? false)
            }
        }
    }
}

struct iPadReadingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @AppStorage("readingBookSort") private var storedSort = BookSort.progressDescending.rawValue
    private var books: [Book] { store.cache.readingBooks(search: search, sort: .restored(storedSort)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("\(store.cache.bookCount) 本 · \(store.cache.finishedBooks.count) 本已读完")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("排序", selection: $storedSort) {
                        ForEach(BookSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.menu)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .top)], spacing: 20) {
                    ForEach(books) { book in
                        MobileBookCard(book: book, progress: store.cache.reading?[book.id])
                            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if books.isEmpty {
                    ContentUnavailableView(store.busy ? "正在读取书籍…" : "暂无匹配的书籍", systemImage: "book.closed")
                }
            }.padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我读过的书")
        .searchable(text: $search, prompt: "搜索书名或作者")
    }
}
