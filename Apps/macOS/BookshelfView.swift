import SwiftUI
import BookCardCore

enum SourceFilter: String, CaseIterable { case all = "全部来源", books = "书籍", articles = "公众号" }
enum NoteFilter: String, CaseIterable { case all = "全部", highlights = "划线", thoughts = "想法" }

struct ShelfState {
    var query = ""
    var source: SourceFilter = .all
    var kind: NoteFilter = .all
    var cards = false
}

struct BookshelfView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openBook: (String) -> Void
    @Binding var state: ShelfState
    private var filteredEntries: [NoteEntry] {
        store.cache.allNotes.filter { entry in
            includes(entry.book) && (!state.cards || state.kind == .all || entry.note.kind == state.kind.rawValue) && entry.matches(state.query)
        }
    }
    private var books: [Book] {
        let matches = Set(filteredEntries.map(\.book.id))
        return store.cache.noteBooks.filter { book in
            includes(book) && (state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matches.contains(book.id) ||
                NoteEntry(book: book, note: Note(id: "", kind: "", quote: "", chapter: "")).matches(state.query))
        }
    }
    private func includes(_ book: Book) -> Bool { state.source == .all || (state.source == .articles ? book.official : !book.official) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(title: "A LIBRARY OF MOMENTS")
                        Text("全部书签").font(.system(size: 32, weight: .medium, design: .serif))
                        Text("\(store.cache.noteBooks.count) 本书与文集，\(store.cache.allNotes.count) 个值得留住的片刻。")
                            .font(.system(size: 12)).foregroundStyle(Paper.secondary)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        layoutButton("书架", icon: "books.vertical", value: false)
                        layoutButton("卡片", icon: "square.grid.2x2", value: true)
                    }.padding(4).background(Paper.line.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                }
                HStack(spacing: 20) {
                    HStack(spacing: 18) {
                        ForEach(SourceFilter.allCases, id: \.self) { filter in
                            Button { state.source = filter } label: {
                                Text(filter.rawValue).font(.system(size: 12, weight: state.source == filter ? .semibold : .regular))
                                    .foregroundStyle(state.source == filter ? Paper.green : Paper.secondary)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) { if state.source == filter { Capsule().fill(Paper.green).frame(height: 2) } }
                            }.buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                    if state.cards {
                        Picker("笔记类型", selection: $state.kind) { ForEach(NoteFilter.allCases, id: \.self) { Text($0.rawValue) } }
                            .labelsHidden().frame(width: 100)
                    }
                    SearchBox(placeholder: "搜索书名、文章、引用或想法", text: $state.query).frame(maxWidth: 300)
                }
            }.padding(.horizontal, 42).padding(.top, 34).padding(.bottom, 22)
            if state.cards {
                if filteredEntries.isEmpty { empty }
                else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(filteredEntries) { entry in BookmarkCard(entry: entry, openBook: { openBook(entry.book.id) }) }
                        }.padding(.horizontal, 42).padding(.top, 4).padding(.bottom, 40)
                    }
                }
            } else if books.isEmpty { empty }
            else {
                GeometryReader { geometry in
                    let columns = max(1, Int((geometry.size.width - 84) / 225))
                    let rows = (books.count + columns - 1) / columns
                    ScrollView {
                        LazyVStack(spacing: 30) {
                            ForEach(0..<rows, id: \.self) { row in
                                shelfRow(Array(books.dropFirst(row * columns).prefix(columns)), columns: columns)
                            }
                        }.padding(.horizontal, 42).padding(.top, 10).padding(.bottom, 44)
                    }
                }
            }
            HStack {
                Text(state.cards ? "\(filteredEntries.count) 张书签 · 按标记时间排列" : "\(books.count) 本书与文集 · 按最近标记排列")
                Spacer()
                Text("所有片刻，妥善收藏。")
            }.font(.system(size: 10)).foregroundStyle(Paper.secondary).padding(.horizontal, 42).padding(.vertical, 17)
                .overlay(alignment: .top) { Rectangle().fill(Paper.line).frame(height: 1) }
        }
    }
    private var empty: some View {
        EmptyBookmarks(title: store.cache.allNotes.isEmpty ? "书架还在等待第一张书签" : "没有找到相关书签", message: store.cache.allNotes.isEmpty ? "微信读书中的划线和想法会自动收进这里。" : "试试其他关键词、来源或笔记类型。")
    }
    private func layoutButton(_ title: String, icon: String, value: Bool) -> some View {
        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { state.cards = value } } label: {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 8)
                .background(state.cards == value ? Paper.card : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private func shelfRow(_ row: [Book], columns: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 24) {
                ForEach(row) { book in
                    ShelfBook(book: book, count: store.cache.details[book.id]?.notes.count,
                              open: { openBook(book.id) }).frame(maxWidth: .infinity)
                }
                ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: 1) }
            }.padding(.horizontal, 20)
            Rectangle().fill(Color(hex: 0xDED8C9).gradient).frame(height: 8)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.8)).frame(height: 1) }
                .shadow(color: Paper.ink.opacity(0.1), radius: 6, y: 6)
        }
    }
}

struct ShelfBook: View {
    let book: Book
    let count: Int?
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 15) {
                BookCover(book: book).frame(width: 165, height: 228)
                    .rotation3DEffect(.degrees(hovering && !reduceMotion ? -7 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading)
                    .offset(y: hovering && !reduceMotion ? -6 : 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(1).help(book.title)
                    HStack(spacing: 5) {
                        Text(count.map { "\($0) 张书签" } ?? "等待同步")
                        if book.official { Text("· 公众号") }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").opacity(hovering ? 1 : 0.4)
                    }.font(.system(size: 10)).foregroundStyle(Paper.secondary)
                }.frame(width: 165)
            }.padding(.bottom, 20).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onHover { value in withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { hovering = value } }
            .accessibilityLabel("\(book.title)，\(count.map { "\($0) 张书签" } ?? "等待同步")，打开书籍")
    }
}

struct BookNotesView: View {
    @EnvironmentObject var store: AppStore
    let book: Book
    let back: () -> Void
    @State private var section: String?
    @State private var query = ""
    @State private var kind: NoteFilter = .all
    private var notes: [Note] { store.cache.details[book.id]?.notes ?? [] }
    private var groups: [NoteGroup] { groupedNotes(notes, official: book.official) }
    private var visibleGroups: [NoteGroup] {
        groups.filter { section == nil || $0.id == section }.compactMap { group in
            let filtered = group.notes.filter { note in
                (kind == .all || note.kind == kind.rawValue) && NoteEntry(book: book, note: note).matches(query)
            }
            return filtered.isEmpty ? nil : NoteGroup(id: group.id, title: group.title, notes: filtered)
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: back) { Label("返回书架", systemImage: "arrow.left") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Paper.secondary)
                BookCover(book: book, compact: true).frame(width: 108, height: 151).padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(.system(size: 21, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    Text(book.official ? "公众号文集" : book.author).font(.system(size: 11)).foregroundStyle(Paper.secondary)
                    Text("\(notes.count) 张书签 · \(groups.count) \(book.official ? "篇文章" : "个章节")")
                        .font(.system(size: 11)).foregroundStyle(Paper.secondary)
                }
                Rectangle().fill(Paper.line).frame(height: 1)
                Eyebrow(title: book.official ? "ARTICLES / 文章" : "CONTENTS / 章节")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        chapterButton("全部书签", count: notes.count, id: nil)
                        ForEach(groups) { group in chapterButton(group.title, count: group.notes.count, id: group.id) }
                    }
                }
            }.padding(28).frame(width: 260).background(Color(hex: 0xEEEDE5))
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(title: "BETWEEN THE PAGES")
                        Text(section == nil ? "书中的片刻" : "这一\(book.official ? "篇" : "章")的书签")
                            .font(.system(size: 27, weight: .medium, design: .serif))
                    }
                    Spacer()
                    Picker("笔记类型", selection: $kind) { ForEach(NoteFilter.allCases, id: \.self) { Text($0.rawValue) } }
                        .labelsHidden().frame(width: 100)
                }
                SearchBox(placeholder: "搜索本书引用、想法或\(book.official ? "文章" : "章节")", text: $query)
                if visibleGroups.isEmpty {
                    EmptyBookmarks(title: store.cache.details[book.id] == nil ? "这本书正在等待同步" : "没有匹配的书签", message: store.cache.details[book.id] == nil ? "同步后，划线与想法会出现在这里。" : "试试其他关键词、章节或笔记类型。")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                Color.clear.frame(height: 0).id("top")
                                ForEach(visibleGroups) { group in
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            Text(group.title).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                                            Text("\(group.notes.count)").font(.system(size: 10)).foregroundStyle(Paper.secondary)
                                            Spacer()
                                            if book.official, let id = group.notes.first?.sectionID, let url = ArticleTitles.publicURL(id) {
                                                Link(destination: url) { Image(systemName: "arrow.up.right") }.help("打开公众号原文")
                                            }
                                        }
                                        ForEach(group.notes) { note in BookmarkCard(entry: NoteEntry(book: book, note: note)) }
                                    }.padding(.bottom, 4)
                                }
                            }.padding(.horizontal, 3).padding(.bottom, 30)
                        }.onChange(of: section) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    }
                }
                if let synced = store.cache.details[book.id]?.synced {
                    Text("本书已缓存 · \(readingDate(synced))")
                        .font(.system(size: 10)).foregroundStyle(Paper.secondary)
                }
            }.padding(30).frame(maxWidth: .infinity)
        }
    }
    private func chapterButton(_ title: String, count: Int, id: String?) -> some View {
        Button { section = id } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(title).lineLimit(3).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("\(count)").monospacedDigit().foregroundStyle(Paper.secondary)
            }.font(.system(size: 11, weight: section == id ? .semibold : .regular)).padding(10)
                .foregroundStyle(section == id ? Paper.green : Paper.secondary)
                .background(section == id ? Paper.card : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title)
    }
}
