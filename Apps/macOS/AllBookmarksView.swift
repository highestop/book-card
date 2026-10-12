import SwiftUI
import BookCardCore

struct BookmarksState: Hashable {
    var query = ""
    var sourceID: String?
}

struct AllBookmarksView: View {
    @EnvironmentObject var store: AppStore
    let openBook: (String) -> Void
    let backHome: () -> Void
    @Binding var state: BookmarksState
    private var sources: [Book] { store.cache.noteBooks }
    private var entries: [NoteEntry] { store.cache.bookmarks(sourceID: state.sourceID, search: state.query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Button(action: backHome) { Label("返回首页", systemImage: "arrow.left") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Paper.secondary)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(title: "A COLLECTION OF MOMENTS")
                        Text("全部书签").font(.system(size: 32, weight: .medium, design: .serif))
                        Text("\(store.cache.noteBooks.count) 本书与文集，\(store.cache.allNotes.count) 个值得留住的片刻。")
                            .font(.system(size: 12)).foregroundStyle(Paper.secondary)
                    }
                    Spacer(minLength: 24)
                }
                HStack(spacing: 16) {
                    SourcePicker(books: sources, selection: $state.sourceID).frame(width: 240)
                    SearchBox(placeholder: "搜索书名、作者、文章、引用或想法", text: $state.query).frame(maxWidth: 400)
                    Spacer(minLength: 0)
                }
            }.padding(.horizontal, 42).padding(.top, 34).padding(.bottom, 28)
            if entries.isEmpty {
                EmptyBookmarks(title: store.cache.allNotes.isEmpty ? "等待第一张书签" : "没有找到相关书签", message: store.cache.allNotes.isEmpty ? "微信读书中的划线和想法会自动收进这里。" : "试试其他关键词，或选择其他书名／公众号。")
            } else {
                ScrollView {
                    WaterfallGrid(items: entries, minimumWidth: 300, spacing: 24) { entry in
                        BookmarkCard(entry: entry, openBook: { openBook(entry.book.id) })
                    }.padding(.horizontal, 42).padding(.top, 4).padding(.bottom, 40)
                }.id(state)
            }
            HStack {
                Text("\(entries.count) 张书签 · 标记时间从新到旧")
                Spacer()
                Text("所有片刻，妥善收藏。")
            }.font(.system(size: 10)).foregroundStyle(Paper.secondary).padding(.horizontal, 42).padding(.vertical, 17)
                .overlay(alignment: .top) { Rectangle().fill(Paper.line).frame(height: 1) }
        }
    }
}

struct BookNotesView: View {
    @EnvironmentObject var store: AppStore
    let book: Book
    let back: () -> Void
    @State private var section: String?
    @State private var query = ""
    private var notes: [Note] { store.cache.details[book.id]?.notes ?? [] }
    private var groups: [NoteGroup] { groupedNotes(notes, official: book.official) }
    private var visibleGroups: [NoteGroup] {
        groups.filter { section == nil || $0.id == section }.compactMap { group in
            let filtered = group.notes.filter { note in
                NoteEntry(book: book, note: note).matches(query)
            }
            return filtered.isEmpty ? nil : NoteGroup(id: group.id, title: group.title, notes: filtered)
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: back) { Label("返回全部书签", systemImage: "arrow.left") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Paper.secondary)
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
                }
                SearchBox(placeholder: "搜索本书引用、想法或\(book.official ? "文章" : "章节")", text: $query)
                if visibleGroups.isEmpty {
                    EmptyBookmarks(title: store.cache.details[book.id] == nil ? "这本书正在等待同步" : "没有匹配的书签", message: store.cache.details[book.id] == nil ? "同步后，划线与想法会出现在这里。" : "试试其他关键词或章节。")
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
                                        WaterfallGrid(items: group.notes, minimumWidth: 280) { note in
                                            BookmarkCard(entry: NoteEntry(book: book, note: note))
                                        }
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
