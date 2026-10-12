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
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.chapterTitle).font(.system(featured ? .subheadline : .caption, design: .serif, weight: .medium))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if linkSource {
                    NavigationLink { MobileSourceNotesView(book: entry.book) } label: {
                        Text(entry.book.title).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                } else {
                    Text(entry.book.title).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.trailing, 32)
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
                        .font(.body).lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
                    HStack(spacing: 12) {
                        Text(selectedID == nil ? "最近一次标记" : "随机重逢").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if selectedID != nil {
                            Button("回到最新") {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = nil }
                            }
                        }
                        Button(action: randomize) { Label("随机一张", systemImage: "shuffle") }
                            .disabled(entries.count < 2).buttonStyle(.bordered)
                    }.font(.caption)
                    MobileBookmarkCard(entry: entries[index], featured: true).id(entries[index].id)
                        .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 8)))
                } else {
                    ContentUnavailableView(store.busy ? "正在整理书签…" : "等待第一张书签", systemImage: "bookmark", description: Text("在微信读书中划线或写下想法，回到这里自动同步。"))
                }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(MobilePaper.background)
            .refreshable { await store.refresh() }.task { await store.refreshIfNeeded() }
    }
    private func randomize() {
        guard !entries.isEmpty, let next = store.cache.randomBookmark(excluding: entries[index].id) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = next.id }
    }
}
struct MobileBookmarksView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sourceID: String?
    @State private var sectionID: String?
    private var entries: [NoteEntry] { store.cache.bookmarks(sourceID: sourceID, sectionID: sectionID, search: search) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Button { dismiss() } label: { Label("返回首页", systemImage: "arrow.left") }.font(.subheadline)
                Text("全部书签").font(.system(.largeTitle, design: .serif, weight: .medium))
                Text("\(entries.count) 张书签 · 标记时间从新到旧").font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        SourcePicker(cache: store.cache, sourceID: $sourceID, sectionID: $sectionID).frame(width: 240)
                        MobileSearchField(text: $search, placeholder: "书名、作者、文章、引用或想法").frame(minWidth: 300)
                    }
                    VStack(spacing: 12) {
                        SourcePicker(cache: store.cache, sourceID: $sourceID, sectionID: $sectionID)
                        MobileSearchField(text: $search, placeholder: "书名、作者、文章、引用或想法")
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 24)
            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView("暂无匹配书签", systemImage: "bookmark", description: Text("试试其他关键词，或选择其他书名／公众号。"))
                } else {
                    WaterfallGrid(items: entries, minimumWidth: 300, spacing: 20) { entry in
                        MobileBookmarkCard(entry: entry)
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }.id([sourceID ?? "", sectionID ?? "", search])
                .refreshable { await store.refresh() }
        }.background(MobilePaper.background).toolbar(.hidden, for: .navigationBar)
    }
}

struct MobileSearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).font(.subheadline).autocorrectionDisabled()
                .textInputAutocapitalization(.never).accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary).accessibilityLabel("清除搜索")
            }
        }.padding(12).background(MobilePaper.card, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct MobileSourceNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let book: Book
    @State private var search = ""
    @State private var section: String?
    private var groups: [NoteGroup] { store.cache.noteGroups(for: book, search: search).filter { section == nil || $0.id == section } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { dismiss() } label: { Label("返回", systemImage: "arrow.left") }.font(.subheadline)
                Text(book.title).font(.system(.title, design: .serif, weight: .medium))
                MobileSearchField(text: $search, placeholder: "引用、想法或章节")
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
        }.background(MobilePaper.background).toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
    }
}
