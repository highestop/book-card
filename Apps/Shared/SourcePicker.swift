import SwiftUI
import BookCardCore

struct SourcePicker: View {
    let cache: Cache
    @Binding var sourceID: String?
    @Binding var sectionID: String?
    @State private var presented = false
    @State private var draftSourceID: String?
    @State private var draftSectionID: String?
    private var selected: Book? { cache.noteBooks.first { $0.id == sourceID } }
    private var groups: [NoteGroup] { selected.map { cache.noteGroups(for: $0) } ?? [] }
    private var chapter: String? { groups.first { $0.id == sectionID }?.title }

    var body: some View {
        Button {
            draftSourceID = sourceID; draftSectionID = sectionID
            presented = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "line.3.horizontal.decrease")
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected?.title ?? "所有书名／公众号").font(.subheadline)
                    if let chapter { Text(chapter).font(.caption).foregroundStyle(.secondary) }
                }.lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2)
            }.padding(12).frame(maxWidth: .infinity)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("筛选书名、公众号、章节或文章")
            .accessibilityValue([selected?.title ?? "所有书名／公众号", chapter].compactMap { $0 }.joined(separator: "，"))
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                SourceFilterPanel(cache: cache, sourceID: $draftSourceID, sectionID: $draftSectionID, apply: {
                    sourceID = draftSourceID; sectionID = draftSectionID
                    presented = false
                }, close: { presented = false })
                    #if os(macOS)
                    .frame(width: 640, height: 500)
                    #else
                    .frame(idealWidth: 640, idealHeight: 540)
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                    #endif
            }
            .onChange(of: cache.noteBooks.map(\.id), initial: true) { _, ids in
                if let sourceID, !ids.contains(sourceID) { self.sourceID = nil; sectionID = nil }
            }
            .onChange(of: groups.map(\.id), initial: true) { _, ids in
                if let sectionID, !ids.contains(sectionID) { self.sectionID = nil }
            }
    }
}

struct SourceFilterPanel: View {
    let cache: Cache
    @Binding var sourceID: String?
    @Binding var sectionID: String?
    let apply: () -> Void
    let close: () -> Void
    private let ink = Color(red: 0.16, green: 0.23, blue: 0.20)
    private let green = Color(red: 0.25, green: 0.38, blue: 0.32)
    private let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    private var sources: [Book] { cache.noteBooks }
    private var selected: Book? { sources.first { $0.id == sourceID } }
    private var groups: [NoteGroup] { selected.map { cache.noteGroups(for: $0) } ?? [] }
    private var count: Int {
        if let sectionID { return groups.first { $0.id == sectionID }?.notes.count ?? 0 }
        if let sourceID { return cache.details[sourceID]?.notes.count ?? 0 }
        return cache.allNotes.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择阅读来源").font(.headline)
                    Text("选好后，点击「完成」应用筛选").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("取消筛选修改")
            }.padding(20)
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        sourceRow("全部来源", id: nil).padding(12)
                        sourceGroup("书籍", books: sources.filter { !$0.official })
                        Divider().padding(.horizontal, 12)
                        sourceGroup("公众号", books: sources.filter(\.official))
                    }.frame(width: geometry.size.width * 0.42).background(ink.opacity(0.035))
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        if let selected {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selected.official ? "文章" : "章节").font(.caption).foregroundStyle(.secondary)
                                Text(selected.title).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            }.padding(16)
                            Divider().padding(.horizontal, 16)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    chapterRow(selected.official ? "全部文章" : "全部章节", count: cache.details[selected.id]?.notes.count ?? 0, id: nil)
                                    ForEach(groups) { group in chapterRow(group.title, count: group.notes.count, id: group.id) }
                                    if groups.isEmpty {
                                        Text("同步后，有书签的\(selected.official ? "文章" : "章节")会显示在这里。")
                                            .font(.caption).foregroundStyle(.secondary).padding(10)
                                    }
                                }.padding(10)
                            }.id(selected.id)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "text.book.closed").font(.system(size: 28, weight: .light)).foregroundStyle(green)
                                Text("先选择一本书或公众号").font(.subheadline)
                                Text("对应的章节与文章\n会显示在这里").font(.caption).foregroundStyle(.secondary)
                            }.multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            HStack {
                Text("当前选择 · \(count) 张书签").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: apply) {
                    Text("完成").font(.subheadline.weight(.medium)).padding(.horizontal, 22).padding(.vertical, 10)
                        .foregroundStyle(.white).background(green, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }.padding(16)
        }.foregroundStyle(ink).background(paper)
            .onChange(of: sources.map(\.id), initial: true) { _, ids in
                if let sourceID, !ids.contains(sourceID) { self.sourceID = nil; sectionID = nil }
            }
            .onChange(of: groups.map(\.id), initial: true) { _, ids in
                if let sectionID, !ids.contains(sectionID) { self.sectionID = nil }
            }
    }

    private func sourceGroup(_ title: String, books: [Book]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text("\(books.count)").font(.caption2).monospacedDigit()
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if books.isEmpty { Text("暂无\(title)").font(.caption).foregroundStyle(.secondary).padding(10) }
                        ForEach(books) { book in sourceRow(book.title, id: book.id).id(book.id) }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }.onAppear {
                    if let sourceID, books.contains(where: { $0.id == sourceID }) { proxy.scrollTo(sourceID, anchor: .center) }
                }
            }
        }.frame(maxHeight: books.isEmpty ? 76 : .infinity)
    }

    private func sourceRow(_ title: String, id: String?) -> some View {
        Button {
            if sourceID != id { sourceID = id; sectionID = nil }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if sourceID == id { Image(systemName: id == nil ? "checkmark" : "chevron.right").font(.caption2) }
            }.font(.subheadline.weight(sourceID == id ? .medium : .regular)).multilineTextAlignment(.leading)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(sourceID == id ? green : ink)
                .background(sourceID == id ? green.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(sourceID == id ? .isSelected : [])
    }

    private func chapterRow(_ title: String, count: Int, id: String?) -> some View {
        Button { sectionID = id } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text("\(count) 张书签").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if sectionID == id { Image(systemName: "checkmark").font(.caption) }
            }.multilineTextAlignment(.leading).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(sectionID == id ? green : ink)
                .background(sectionID == id ? green.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(sectionID == id ? .isSelected : [])
    }
}
