import SwiftUI
import BookCardCore

private enum PadDestination: Hashable { case home, shelf, book(String) }
struct iPadLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showKey: Bool
    @State private var destination: PadDestination? = .home
    @State private var search = ""
    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section {
                    NavigationLink(value: PadDestination.home) { Label("最近书签", systemImage: "rectangle.stack") }
                    NavigationLink(value: PadDestination.shelf) { Label("全部书签", systemImage: "books.vertical") }
                }
                Section("书籍与文集") {
                    ForEach(store.cache.noteSources(search: search)) { book in
                        NavigationLink(value: PadDestination.book(book.id)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title).font(.subheadline.weight(.medium))
                                Text(store.cache.details[book.id].map { "\($0.notes.count) 张书签" } ?? "等待同步").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }.navigationTitle("BookCard").searchable(text: $search, prompt: "搜索书籍与公众号")
                .navigationSplitViewColumnWidth(min: 230, ideal: 270)
                .scrollContentBackground(.hidden).background(MobilePaper.background)
        } detail: {
            NavigationStack {
                Group {
                    switch destination {
                    case .home, nil: MobileHomeView()
                    case .shelf: MobileShelfView()
                    case .book(let id):
                        if let book = store.cache.books.first(where: { $0.id == id }) { MobileSourceNotesView(book: book).id(id) }
                        else { MobileShelfView() }
                    }
                }.mobileControls(showKey: $showKey)
            }.id(destination)
        }
    }
}
