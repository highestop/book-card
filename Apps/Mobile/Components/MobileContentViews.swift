import SwiftUI
import UIKit
import BookCardCore

enum MobilePaper {
    static let background = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let card = Color(red: 1, green: 0.995, blue: 0.98)
    static let ink = Color(red: 0.16, green: 0.23, blue: 0.20)
    static let green = Color(red: 0.25, green: 0.38, blue: 0.32)
    static let rust = Color(red: 0.68, green: 0.38, blue: 0.27)
    static func accent(_ id: String) -> Color {
        let colors = [green, rust, Color(red: 0.38, green: 0.46, blue: 0.49), Color(red: 0.5, green: 0.46, blue: 0.39)]
        return colors[id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff } % colors.count]
    }
}
struct MobileRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: rect.width, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.height - rect.width * 0.3))
            p.addLine(to: CGPoint(x: 0, y: rect.height)); p.closeSubpath()
        }
    }
}
struct MobileBookmarkCard: View {
    let entry: NoteEntry
    var featured = false
    var linkSource = true
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var long: Bool {
        (entry.quoteText.map { NoteText.excerpt($0, limit: 220) != $0 } ?? false) ||
        (entry.thoughtText.map { NoteText.excerpt($0, limit: 160) != $0 } ?? false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label((entry.book.official ? "公众号 · " : "读书笔记 · ") + entry.note.kind, systemImage: "bookmark")
                    .font(.caption2).foregroundStyle(MobilePaper.accent(entry.book.id))
                Text(entry.chapterTitle).font(.system(featured ? .title3 : .headline, design: .serif, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if linkSource {
                    NavigationLink { MobileSourceNotesView(book: entry.book) } label: {
                        Text(entry.book.title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                } else {
                    Text(entry.book.title).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.trailing, 24)
            Divider()
            if let quote = entry.quoteText {
                Text(featured || expanded ? quote : NoteText.excerpt(quote, limit: 220))
                    .font(.system(featured ? .title3 : .body, design: .serif)).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let thought = entry.thoughtText {
                VStack(alignment: .leading, spacing: 10) {
                    Label("我的想法", systemImage: "pencil.tip").font(.caption2).foregroundStyle(MobilePaper.rust)
                    Text(featured || expanded ? thought : NoteText.excerpt(thought, limit: 160))
                        .font(.subheadline).lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MobilePaper.background, in: RoundedRectangle(cornerRadius: 8))
            }
            if entry.quoteText == nil && entry.thoughtText == nil {
                Label("图片标记 · 暂无可显示的文字", systemImage: "photo").font(.subheadline).foregroundStyle(.secondary)
            }
            if !featured && long {
                Button(expanded ? "收起全文 ↑" : "展开全文 ↓") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                }.font(.caption)
            }
            HStack {
                Text(entry.note.created.map { readingDate(Date(timeIntervalSince1970: $0)) } ?? "标记时间未提供")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: entry.copyText) { Image(systemName: "square.and.arrow.up").frame(minWidth: 32, minHeight: 32) }
                    .accessibilityLabel("分享书签及来源")
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(MobilePaper.ink)
            .background(MobilePaper.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MobilePaper.ink.opacity(0.09), lineWidth: 1))
            .overlay(alignment: .topTrailing) { MobileRibbon().fill(MobilePaper.accent(entry.book.id)).frame(width: 20, height: 44).padding(.trailing, 24) }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
            .contextMenu { Button("复制书签及来源", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.copyText } }
    }
}
struct MobileHomeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    private var entries: [NoteEntry] { store.cache.allNotes }
    private var index: Int { entries.firstIndex { $0.id == selectedID } ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR READING, KEPT CLOSE").font(.system(size: 9)).tracking(2).foregroundStyle(.secondary)
                    Text("读过的，留下来。").font(.system(.largeTitle, design: .serif, weight: .medium))
                    Text("重逢一段文字，也重逢当时的自己。").font(.subheadline).foregroundStyle(.secondary)
                }
                NavigationLink { MobileBookmarksView() } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("打开全部书签").font(.headline)
                            Text("\(store.cache.noteBooks.count) 本书与文集 · \(entries.count) 张书签").font(.caption).opacity(0.75)
                        }
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.padding(20).foregroundStyle(MobilePaper.card).background(MobilePaper.green, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                if !entries.isEmpty {
                    HStack {
                        Text(index == 0 ? "最近一次标记" : "回顾书签")
                        Spacer(); Text("\(index + 1) / \(entries.count)").monospacedDigit()
                    }.font(.caption).foregroundStyle(.secondary)
                    MobileBookmarkCard(entry: entries[index], featured: true).id(entries[index].id)
                        .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 8)))
                    HStack {
                        Button { step(-1) } label: { Label("更新一张", systemImage: "arrow.left") }.disabled(index == 0)
                        Spacer()
                        Button { step(1) } label: { Label("往前翻阅", systemImage: "arrow.right") }.disabled(index == entries.count - 1)
                    }.font(.subheadline).buttonStyle(.bordered)
                    NavigationLink("打开《\(entries[index].book.title)》的全部书签") { MobileSourceNotesView(book: entries[index].book) }.font(.caption)
                    if index > 0 { Button("回到最新") { selectedID = nil }.font(.caption) }
                } else {
                    ContentUnavailableView(store.busy ? "正在整理书签…" : "等待第一张书签", systemImage: "bookmark", description: Text("在微信读书中划线或写下想法，回到这里自动同步。"))
                }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(MobilePaper.background).navigationTitle("BookCard").navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.refresh() }.task { await store.refreshIfNeeded() }
    }
    private func step(_ delta: Int) {
        guard entries.indices.contains(index + delta) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = entries[index + delta].id }
    }
}
struct MobileBookmarksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    private var entries: [NoteEntry] { store.cache.allNotes.filter { $0.matches(search) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("\(store.cache.noteBooks.count) 本书与文集，\(store.cache.allNotes.count) 个值得留住的片刻。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if entries.isEmpty {
                    ContentUnavailableView("暂无匹配书签", systemImage: "bookmark", description: Text("试试其他关键词。"))
                } else {
                    WaterfallGrid(items: entries, minimumWidth: 300, spacing: 20) { entry in
                        MobileBookmarkCard(entry: entry)
                    }
                }
            }.padding(24)
        }.id(search).background(MobilePaper.background).navigationTitle("全部书签")
            .searchable(text: $search, prompt: "书名、文章、引用或想法")
            .refreshable { await store.refresh() }
    }
}
struct MobileSourceNotesView: View {
    @EnvironmentObject private var store: AppStore
    let book: Book
    @State private var search = ""
    @State private var section: String?
    private var groups: [NoteGroup] { store.cache.noteGroups(for: book, search: search).filter { section == nil || $0.id == section } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Picker(book.official ? "文章" : "章节", selection: $section) {
                        Text("全部\(book.official ? "文章" : "章节")").tag(nil as String?)
                        ForEach(store.cache.noteGroups(for: book)) { group in Text(group.title).tag(Optional(group.id)) }
                    }
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(group.title).font(.headline)
                            Spacer()
                            if book.official, let id = group.notes.first?.sectionID, let url = ArticleTitles.publicURL(id) {
                                Link(destination: url) { Image(systemName: "arrow.up.right") }.accessibilityLabel("打开公众号原文")
                            }
                        }
                        WaterfallGrid(items: group.notes, minimumWidth: 300, spacing: 20) {
                            MobileBookmarkCard(entry: NoteEntry(book: book, note: $0), linkSource: false)
                        }
                    }
                }
                if groups.isEmpty {
                    ContentUnavailableView(store.cache.details[book.id] == nil ? "等待同步这本书" : "暂无匹配笔记", systemImage: "bookmark")
                }
            }.padding(24).frame(maxWidth: .infinity)
        }.background(MobilePaper.background).navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "引用、想法或章节").refreshable { await store.refresh() }
    }
}
