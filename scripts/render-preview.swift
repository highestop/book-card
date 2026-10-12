import SwiftUI
import BookCardCore
import AppKit

// Synthetic content only. This renderer never loads the Keychain or account cache.
@main struct PreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1791772200)
        let titles = ["把生活读成一本书", "山间来信", "留白的艺术", "城市漫游手记", "慢慢生长", "纸上旅行", "日常观察", "一间自己的书房"]
        var books: [Book] = []
        var details: [String: BookDetail] = [:]
        for (index, title) in titles.enumerated() {
            let book = Book(id: index == 3 ? "MP_WXS_preview" : "preview-\(index)", title: title,
                            author: "BookCard 示例文集", highlights: 2, thoughts: 1, recent: 100 - index)
            books.append(book)
            let notes = [
                Note(id: "thought:1", kind: "想法", quote: index % 3 == 0 ? "阅读的意义，也许就是在别人的文字里，\n慢慢认出自己的生活。" : (index % 3 == 1 ? "慢慢读，也慢慢生活。" : "在文字与生活之间，留一点空白。\n\n有时一句话，就足够让人走很远。"), thought: index % 3 == 0 ? "不必急着读完。值得停留的句子，\n可以陪我们走很长的一段路。" : nil, chapter: index == 3 ? "周末来信：在城市中找到一处安静的角落" : "第一章 · 在文字里停留", created: now.timeIntervalSince1970 - Double(index * 1000), sectionID: "1", sectionOrder: 1),
                Note(id: "highlight:2", kind: "划线", quote: "午后的阳光从窗沿移到书页上。一切都很安静，只有翻页的声音提醒我，时间还在往前走。", chapter: "第二章 · 午后的书房", created: now.timeIntervalSince1970 - 10000 - Double(index * 1000), sectionID: "2", sectionOrder: 2),
                Note(id: "highlight:3", kind: "划线", quote: "[图片]", chapter: "第二章 · 午后的书房", created: nil, sectionID: "2", sectionOrder: 2)
            ]
            details[book.id] = BookDetail(notes: notes, synced: now, stamp: NotebookStamp(book))
        }
        let cache = Cache(books: books, details: details, notesSynced: now)
        let store = AppStore(preview: cache)
        let pages: [(String, LibraryPage, CGFloat, CGFloat)] = [
            ("home", .home, 1180, 840), ("cards", .bookmarks, 1180, 940),
            ("book", .book(books[0].id), 1180, 940), ("home-small", .home, 860, 640)
        ]
        for (name, page, width, height) in pages {
            try render(ContentView(initialPage: page).environmentObject(store), name: name, width: width, height: height)
        }
        try render(ContentView(initialPage: .bookmarks).environmentObject(store), name: "cards-small", width: 860, height: 940)
        try render(ContentView(initialPage: .bookmarks, initialBookmarks: BookmarksState(query: "不存在的文字")).environmentObject(store), name: "no-results", width: 860, height: 640)
        let empty = AppStore(preview: Cache())
        try render(ContentView().environmentObject(empty), name: "welcome", width: 1000, height: 800)
        let longNote = Note(id: "long", kind: "想法", quote: String(repeating: "一段值得停下来的文字。\n", count: 25), thought: "长笔记应当可以完整展开，保留每一段原文。", chapter: "很长的一章", created: now.timeIntervalSince1970)
        try render(BookmarkCard(entry: NoteEntry(book: books[0], note: longNote), featured: true).padding(30).background(Paper.background), name: "long-card", width: 640, height: 1800)
        print("Rendered 8 synthetic previews in build/previews")
    }
    @MainActor static func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
        let root = view.frame(width: width, height: height).environment(\.locale, Locale(identifier: "zh_CN"))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.displayIfNeeded()
        guard let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw NSError(domain: "Preview", code: 1) }
        hosting.cacheDisplay(in: hosting.bounds, to: image)
        window.orderOut(nil)
        let url = URL(fileURLWithPath: "build/previews/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.representation(using: .png, properties: [:])!.write(to: url)
    }
}
